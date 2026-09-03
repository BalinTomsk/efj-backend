package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.ResultSetExtractor;
import com.fishfind.docapi.web.NewsController.NewsListItem;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;

import java.sql.Types;
import java.util.ArrayList;
import java.util.List;

/**
 * News-page reads ({@code /news/list}, {@code /news/default}) backed by the MySQL {@code news}
 * table (Winhost, migrated 2026-08-31; see {@code envfish-db/mysql/script02_Proc.sql} ->
 * {@code sp_news_list_json}, {@code sp_news_default}). Search/export/import stay on the
 * SQL-Server-backed delegate -- this MySQL database has no interchange ({@code fn_news_json}) or
 * full-text-search objects, and News.aspx (the only other MySQL news consumer) doesn't need them.
 */
public class MySqlNewsQueryRepository implements NewsQueryRepository {

    static final String LIST_SQL = "CALL sp_news_list_json(?, ?, ?)";
    static final String DEFAULT_SQL = "CALL sp_news_default()";

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
        ObjectNode root = objectMapper.createObjectNode();
        root.set("items", items);
        return root;
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
