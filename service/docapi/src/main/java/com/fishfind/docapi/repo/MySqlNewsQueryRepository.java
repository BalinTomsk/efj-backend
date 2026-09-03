package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.ResultSetExtractor;
import com.fishfind.docapi.web.NewsController.NewsListItem;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;

import java.sql.Types;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * News-page reads ({@code /news/list}, {@code /news/default}) backed by the MySQL {@code news}
 * table (Winhost, migrated 2026-08-31; see {@code envfish-db/mysql/script02_Proc.sql} ->
 * {@code sp_news_list_json}, {@code sp_news_default}). Search/export/import stay on the
 * SQL-Server-backed delegate -- this MySQL database has no interchange ({@code fn_news_json}) or
 * full-text-search objects, and News.aspx (the only other MySQL news consumer) doesn't need them.
 */
public class MySqlNewsQueryRepository implements NewsQueryRepository {

    private static final Logger log = LoggerFactory.getLogger(MySqlNewsQueryRepository.class);

    static final String LIST_SQL = "CALL sp_news_list_json(?, ?, ?)";
    static final String DEFAULT_SQL = "CALL sp_news_default()";

    /** The three fish slots on a news row, in the order the page renders their tags. */
    static final List<String> FISH_SLOTS = List.of("fish1_id", "fish2_id", "fish3_id");

    private final JdbcTemplate mysqlJdbc;
    private final ObjectMapper objectMapper;
    private final NewsQueryRepository sqlServerDelegate;

    public MySqlNewsQueryRepository(JdbcTemplate mysqlJdbc, ObjectMapper objectMapper,
                                    NewsQueryRepository sqlServerDelegate) {
        this.mysqlJdbc = mysqlJdbc;
        this.objectMapper = objectMapper;
        this.sqlServerDelegate = sqlServerDelegate;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "listFallback")
    public NewsListPage list(String country, int offset, int limit) {
        ResultSetExtractor<NewsListPage> extractor = rs -> {
            List<NewsListItem> items = new ArrayList<>();
            long total = 0L;
            while (rs.next()) {
                if (items.isEmpty()) {
                    total = rs.getLong("total");
                }
                items.add(new NewsListItem(
                        rs.getLong("rn"),
                        rs.getString("news_id"),
                        rs.getString("title"),
                        rs.getString("source"),
                        rs.getString("stamp"),
                        rs.getString("flag"),
                        rs.getBoolean("has_photo"),
                        rs.getInt("block_ord")));
            }
            return new NewsListPage(items, total, offset, limit);
        };

        return mysqlJdbc.query(LIST_SQL, ps -> {
            if (country == null) {
                ps.setNull(1, Types.CHAR);
            } else {
                ps.setString(1, country);
            }
            ps.setInt(2, offset);
            ps.setInt(3, limit);
        }, extractor);
    }

    /**
     * The assembled home page. The article rows come from MySQL; the names of the water body and the
     * fish species each lead article mentions come from SQL Server, because this MySQL database holds
     * only the {@code news} table — see {@link #enrichRefNames}.
     */
    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "defaultFallback")
    public JsonNode defaultNews() {
        ArrayNode items = objectMapper.createArrayNode();
        for (String json : mysqlJdbc.query(DEFAULT_SQL, (rs, i) -> rs.getString(1))) {
            if (json == null || json.isBlank()) {
                continue;
            }
            items.add(parseItem(json));
        }
        enrichRefNames(items);
        ObjectNode root = objectMapper.createObjectNode();
        root.set("items", items);
        return root;
    }

    /**
     * Fills in {@code lake_name} and the {@code fishes} array on every item, so one call to
     * {@code /news/default} carries everything the home page's article tag row renders — the lake tag
     * ({@code Resources/wfRiverViewer.aspx?LakeId=…}) and up to three species tags
     * ({@code Resources/wfFishViewer.aspx?fishId=…}), each with the name to display.
     *
     * <p>Those names live in SQL Server: the MySQL database that now backs the news reads has only the
     * {@code news} table, so {@code sp_news_default} can return {@code lake_id} and
     * {@code fish1_id}…{@code fish3_id} but not what they are called. Every id across the whole page is
     * therefore collected first and resolved in <strong>one</strong> SQL Server round trip
     * ({@code dbo.fn_news_ref_names_json}) rather than a lookup per tag.
     *
     * <p><strong>Degrades instead of failing.</strong> Moving news to MySQL was about surviving a SQL
     * Server outage; re-introducing a hard SQL Server dependency on the home page would undo that. So a
     * failed lookup is logged and the items keep their ids with {@code lake_name} null and an empty
     * {@code fishes} array — headlines, photos and body text still render. Note this runs beneath
     * {@link NewsQueryCache}, so a degraded page would be cached until the next eviction; that is the
     * accepted trade for never 500-ing the home page.
     */
    private void enrichRefNames(ArrayNode items) {
        List<String> lakeIds = new ArrayList<>();
        List<String> fishIds = new ArrayList<>();

        for (JsonNode item : items) {
            String lakeId = textOrNull(item, "lake_id");
            if (lakeId != null && !lakeIds.contains(lakeId)) {
                lakeIds.add(lakeId);
            }
            for (String slot : FISH_SLOTS) {
                String fishId = textOrNull(item, slot);
                if (fishId != null && !fishIds.contains(fishId)) {
                    fishIds.add(fishId);
                }
            }
        }

        Map<String, JsonNode> lakesById = new HashMap<>();
        Map<String, JsonNode> fishesById = new HashMap<>();

        if (!lakeIds.isEmpty() || !fishIds.isEmpty()) {
            try {
                JsonNode resolved = sqlServerDelegate.resolveRefNames(lakeIds, fishIds);
                indexById(resolved.path("lakes"), lakesById);
                indexById(resolved.path("fishes"), fishesById);
            } catch (RuntimeException ex) {
                log.warn("Home-page lake/fish name lookup failed; serving /news/default with ids only", ex);
            }
        }

        for (JsonNode item : items) {
            ObjectNode node = (ObjectNode) item;

            JsonNode lake = lakesById.get(textOrNull(item, "lake_id"));
            node.put("lake_name", lake == null ? null : textOrNull(lake, "name"));

            // One array in slot order, skipping empty slots and ids that resolved to nothing -- the same
            // shape dbo.fn_default_news_json's lead document builds, so both backings look identical to
            // a client. An article with no fishes gets [], never a missing field.
            ArrayNode fishes = objectMapper.createArrayNode();
            for (String slot : FISH_SLOTS) {
                JsonNode fish = fishesById.get(textOrNull(item, slot));
                String name = (fish == null) ? null : textOrNull(fish, "name");
                if (name == null) {
                    continue;
                }
                ObjectNode tag = objectMapper.createObjectNode();
                tag.put("id", textOrNull(fish, "id"));
                tag.put("name", name);
                tag.put("latin", textOrNull(fish, "latin"));
                fishes.add(tag);
            }
            node.set("fishes", fishes);
        }
    }

    /** Indexes a {@code [{id, name, …}]} array by its {@code id}, so items can look their tags up. */
    private void indexById(JsonNode array, Map<String, JsonNode> target) {
        if (!array.isArray()) {
            return;
        }
        for (JsonNode element : array) {
            String id = textOrNull(element, "id");
            if (id != null) {
                target.put(id, element);
            }
        }
    }

    /**
     * A non-blank text field, or null. JSON null, a missing field and an empty string all collapse to
     * null — {@code news.lake_id} is a nullable {@code CHAR(36)}, so any of the three can turn up.
     */
    private static String textOrNull(JsonNode node, String field) {
        JsonNode value = node.path(field);
        if (value.isMissingNode() || value.isNull()) {
            return null;
        }
        String text = value.asText("");
        return text.isBlank() ? null : text;
    }

    /**
     * Lake/fish names live only in SQL Server (this MySQL database has just the {@code news} table),
     * so the lookup goes to the delegate -- which is the Resilience4j-proxied bean, keeping its retry
     * and circuit breaker intact. {@link #enrichRefNames} is the caller.
     */
    @Override
    public JsonNode resolveRefNames(List<String> lakeIds, List<String> fishIds) {
        return sqlServerDelegate.resolveRefNames(lakeIds, fishIds);
    }

    /** Not in scope for the MySQL move -- delegates to the SQL-Server-backed repository unchanged. */
    @Override
    public JsonNode exportNews(String id) {
        return sqlServerDelegate.exportNews(id);
    }

    /** Not in scope for the MySQL move -- delegates to the SQL-Server-backed repository unchanged. */
    @Override
    public String importNews(String json) {
        return sqlServerDelegate.importNews(json);
    }

    /** Not in scope for the MySQL move -- delegates to the SQL-Server-backed repository unchanged. */
    @Override
    public NewsSearchPage search(String query) {
        return sqlServerDelegate.search(query);
    }

    /**
     * Circuit-breaker fallback for {@link #list}.
     */
    @SuppressWarnings("unused")
    public NewsListPage listFallback(String country, int offset, int limit, Throwable ex) {
        throw new RuntimeException("MySQL news-list query failed", ex);
    }

    /**
     * Circuit-breaker fallback for {@link #defaultNews}.
     */
    @SuppressWarnings("unused")
    public JsonNode defaultFallback(Throwable ex) {
        throw new RuntimeException("MySQL default-news query failed", ex);
    }

    private JsonNode parseItem(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("MySQL home-page news JSON returned by the database is not valid JSON", ex);
        }
    }
}
