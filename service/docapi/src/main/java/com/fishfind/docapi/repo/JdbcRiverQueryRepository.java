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

    private JsonNode parse(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("River JSON returned by the database is not valid JSON", ex);
        }
    }
}
