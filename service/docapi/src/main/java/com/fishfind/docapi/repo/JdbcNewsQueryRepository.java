package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCallback;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.ResultSetExtractor;
import com.fishfind.docapi.web.NewsController.NewsListItem;
import com.fishfind.docapi.web.NewsController.NewsListPage;

import java.sql.Statement;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;

/**
 * JDBC news query repository backed by SQL Server functions.
 * All DB access for news-page queries (list + default) goes through here.
 * Guarded by Resilience4j retry + circuit breaker, matching {@code JdbcDocumentRepository}.
 */
public class JdbcNewsQueryRepository implements NewsQueryRepository {

    static final String LIST_SQL =
            "SELECT rn, news_id, title, source, stamp, flag, has_photo, block_ord, total "
                    + "FROM dbo.fn_news_list(?, ?, ?) ORDER BY rn";

    static final String DEFAULT_SQL =
            "SELECT dbo.fn_default_news_json(news_id, with_photo) "
                    + "FROM dbo.fn_default_news_ids() ORDER BY ord";

    /** Interchange export: the full article as fn_news_json (all fields + base64 photos), or NULL. */
    static final String EXPORT_SQL = "SELECT dbo.fn_news_json(?)";

    /** Interchange import: create a published article from an fn_news_json body, returns the new id. */
    static final String IMPORT_SQL = "EXEC dbo.sp_news_import ?";

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcNewsQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "listFallback")
    public NewsListPage list(String country, int offset, int limit) {
        PreparedStatementSetter binder = ps -> {
            if (country == null) {
                ps.setNull(1, Types.CHAR);
            } else {
                ps.setString(1, country);
            }
            ps.setInt(2, offset);
            ps.setInt(3, limit);
        };

        ResultSetExtractor<NewsListPage> extractor = rs -> {
            List<NewsListItem> items = new ArrayList<>();
            long total = 0L;
            while (rs.next()) {
                // total is COUNT(*) OVER() -- identical on every row; read it once.
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

        return jdbc.query(LIST_SQL, binder, extractor);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "defaultFallback")
    public JsonNode defaultNews() {
        ArrayNode items = objectMapper.createArrayNode();
        for (String json : jdbc.query(DEFAULT_SQL, (rs, i) -> rs.getString(1))) {
            if (json == null || json.isBlank()) {
                continue;
            }
            items.add(parseItem(json));
        }
        ObjectNode root = objectMapper.createObjectNode();
        root.set("items", items);
        return root;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "exportFallback")
    public JsonNode exportNews(String id) {
        List<String> rows = jdbc.query(EXPORT_SQL, ps -> ps.setString(1, id), (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parseItem(json);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "importFallback")
    public String importNews(String json) {
        // Mirror JdbcDocumentRepository's write path: the EXEC may emit incidental update counts as well
        // as the id result set, so drain everything and take the first scalar.
        return jdbc.execute(IMPORT_SQL, (PreparedStatementCallback<String>) ps -> {
            ps.setString(1, json);
            String scalar = null;
            boolean hasResults = ps.execute();
            while (hasResults || ps.getUpdateCount() != -1) {
                if (hasResults) {
                    try (var rs = ps.getResultSet()) {
                        if (scalar == null && rs != null && rs.next()) {
                            scalar = rs.getString(1);
                        }
                        while (rs != null && rs.next()) {
                            // drain
                        }
                    }
                }
                hasResults = ps.getMoreResults(Statement.CLOSE_CURRENT_RESULT);
            }
            return scalar;
        });
    }

    /**
     * Circuit-breaker fallback for {@link #list}.
     */
    @SuppressWarnings("unused")
    public NewsListPage listFallback(String country, int offset, int limit, Throwable ex) {
        throw new RuntimeException("SQL news-list query failed", ex);
    }

    /**
     * Circuit-breaker fallback for {@link #exportNews}.
     */
    @SuppressWarnings("unused")
    public JsonNode exportFallback(String id, Throwable ex) {
        throw new RuntimeException("SQL news-export query failed for id " + id, ex);
    }

    /**
     * Circuit-breaker fallback for {@link #importNews}.
     */
    @SuppressWarnings("unused")
    public String importFallback(String json, Throwable ex) {
        throw new RuntimeException("SQL news-import failed", ex);
    }

    /**
     * Circuit-breaker fallback for {@link #defaultNews}.
     */
    @SuppressWarnings("unused")
    public JsonNode defaultFallback(Throwable ex) {
        throw new RuntimeException("SQL default-news query failed", ex);
    }

    private JsonNode parseItem(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("Home-page news JSON returned by the database is not valid JSON", ex);
        }
    }
}
