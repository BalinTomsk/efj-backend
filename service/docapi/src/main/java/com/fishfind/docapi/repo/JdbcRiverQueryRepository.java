package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;

/**
 * JDBC river query repository backed by {@code dbo.fn_river_unfished_json} /
 * {@code dbo.fn_lake_view_json}. Guarded by Resilience4j retry + circuit breaker, matching
 * {@code JdbcNewsQueryRepository}.
 */
public class JdbcRiverQueryRepository implements RiverQueryRepository {

    /** Next un-processed water body as a single JSON document. */
    static final String UNFISHED_SQL = "SELECT dbo.fn_river_unfished_json(?, ?, ?)";

    /**
     * Full description document for one water body (name/stats/source/mouth/fish/gallery). Same
     * function the admin "Save JSON" View-tab export uses ({@code Editor/HandlerImage.ashx?lakejson=&
     * tab=view}); already live in {@code envfish-db} — no new DB object for this endpoint.
     */
    static final String DESCRIPTION_SQL = "SELECT dbo.fn_lake_view_json(?)";

    /**
     * Assigned-species document for one water body. Same function the admin "Save JSON" Fishing-tab
     * export uses ({@code Editor/EditLakeFish.aspx} → {@code HandlerImage.ashx?lakejson=&tab=fishing});
     * already live in {@code envfish-db} — no new DB object for this endpoint.
     */
    static final String FISH_SQL = "SELECT dbo.fn_lake_fishing_json(?)";

    /**
     * Source-tab document (the {@code side = 16} Tributaries link). Same function the admin "Save
     * JSON" Source-tab export uses ({@code Editor/EditLakeLink.aspx?Type=16} →
     * {@code HandlerImage.ashx?lakejson=&tab=source}); already live in {@code envfish-db}.
     */
    static final String SOURCE_SQL = "SELECT dbo.fn_lake_source_json(?)";

    /** Mouth-tab document ({@code side = 32}), same shape as {@link #SOURCE_SQL}. */
    static final String MOUTH_SQL = "SELECT dbo.fn_lake_mouth_json(?)";

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcRiverQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "unfishedFallback")
    public JsonNode unfished(String country, String state, int river) {
        List<String> rows = jdbc.query(
                UNFISHED_SQL,
                ps -> {
                    ps.setString(1, country);
                    ps.setString(2, state);
                    ps.setInt(3, river);
                },
                (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "descriptionFallback")
    public JsonNode description(String lakeId) {
        List<String> rows = jdbc.query(DESCRIPTION_SQL, ps -> ps.setString(1, lakeId), (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    /** Circuit-breaker fallback for {@link #unfished}. */
    @SuppressWarnings("unused")
    public JsonNode unfishedFallback(String country, String state, int river, Throwable ex) {
        throw new RuntimeException("SQL river-unfished query failed", ex);
    }

    /** Circuit-breaker fallback for {@link #description}. */
    @SuppressWarnings("unused")
    public JsonNode descriptionFallback(String lakeId, Throwable ex) {
        throw new RuntimeException("SQL river-description query failed for id " + lakeId, ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fishFallback")
    public JsonNode fish(String lakeId) {
        List<String> rows = jdbc.query(FISH_SQL, ps -> ps.setString(1, lakeId), (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    /** Circuit-breaker fallback for {@link #fish}. */
    @SuppressWarnings("unused")
    public JsonNode fishFallback(String lakeId, Throwable ex) {
        throw new RuntimeException("SQL river-fish query failed for id " + lakeId, ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "sourceFallback")
    public JsonNode source(String lakeId) {
        List<String> rows = jdbc.query(SOURCE_SQL, ps -> ps.setString(1, lakeId), (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    /** Circuit-breaker fallback for {@link #source}. */
    @SuppressWarnings("unused")
    public JsonNode sourceFallback(String lakeId, Throwable ex) {
        throw new RuntimeException("SQL river-source query failed for id " + lakeId, ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "mouthFallback")
    public JsonNode mouth(String lakeId) {
        List<String> rows = jdbc.query(MOUTH_SQL, ps -> ps.setString(1, lakeId), (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    /** Circuit-breaker fallback for {@link #mouth}. */
    @SuppressWarnings("unused")
    public JsonNode mouthFallback(String lakeId, Throwable ex) {
        throw new RuntimeException("SQL river-mouth query failed for id " + lakeId, ex);
    }

    private JsonNode parse(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("River JSON returned by the database is not valid JSON", ex);
        }
    }
}
