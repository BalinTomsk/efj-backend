package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;

/**
 * JDBC side of {@code /news/near} (1.34.0): the tagged stories from MySQL (the same narrow columns as
 * {@code MySqlNewsQueryRepository.LAKE_SQL}, never a photo or paragraph column) and the distances from SQL Server
 * ({@code dbo.fn_lakes_near_json}, envfish-db 2026-11-15). Both reads go through the shared {@code sqlRetry} /
 * {@code sqlBreaker} like every other repository bean.
 */
public class JdbcNewsNearRepository implements NewsNearRepository {

    static final String TAGGED_SQL = """
            SELECT news_id, news_title AS title, news_source AS source,
                   DATE_FORMAT(news_stamp, '%Y-%m-%d') AS stamp, country, lake_id
              FROM news
             WHERE news_publish = 1
               AND lake_id IS NOT NULL
               AND lake_id <> ''
             ORDER BY news_stamp DESC, news_id DESC
             LIMIT ?""";

    static final String NEAR_SQL = "SELECT dbo.fn_lakes_near_json(?, ?, ?, ?)";

    private final JdbcTemplate sqlServer;
    private final JdbcTemplate mysql;
    private final ObjectMapper objectMapper;

    public JdbcNewsNearRepository(JdbcTemplate sqlServer, JdbcTemplate mysql, ObjectMapper objectMapper) {
        this.sqlServer = sqlServer;
        this.mysql = mysql;
        this.objectMapper = objectMapper;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "taggedNewsFallback")
    public List<TaggedNews> taggedNews(int limit) {
        return mysql.query(TAGGED_SQL, ps -> ps.setInt(1, limit), (rs, i) -> new TaggedNews(
                rs.getString("news_id"),
                rs.getString("title"),
                rs.getString("source"),
                rs.getString("stamp"),
                rs.getString("country"),
                rs.getString("lake_id")));
    }

    @SuppressWarnings("unused")
    public List<TaggedNews> taggedNewsFallback(int limit, Throwable ex) {
        throw new RuntimeException("MySQL tagged-news query failed", ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "lakesNearFallback")
    public JsonNode lakesNear(String lakeIdsJson, double lat, double lon, int radiusKm) {
        List<String> rows = sqlServer.query(NEAR_SQL, ps -> {
            ps.setString(1, lakeIdsJson);
            ps.setDouble(2, lat);
            ps.setDouble(3, lon);
            ps.setDouble(4, radiusKm);
        }, (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        if (json == null || json.isBlank()) {
            // The controller sends a validated point and radius, so NULL is a contract break, not "none near".
            throw new IllegalStateException("fn_lakes_near_json returned NULL for a validated point");
        }
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Database returned malformed lakes-near JSON", e);
        }
    }

    @SuppressWarnings("unused")
    public JsonNode lakesNearFallback(String lakeIdsJson, double lat, double lon, int radiusKm, Throwable ex) {
        throw new RuntimeException("SQL lakes-near query failed for " + lat + "," + lon, ex);
    }
}
