package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;

/**
 * JDBC regulation query repository backed by {@code dbo.fn_lake_regulation_json} /
 * {@code dbo.fn_region_regulation_json}. Guarded by Resilience4j retry + circuit breaker, matching
 * {@link JdbcRiverQueryRepository}.
 */
public class JdbcRegulationQueryRepository implements RegulationQueryRepository {

    static final String LAKE_SQL = "SELECT dbo.fn_lake_regulation_json(?)";
    static final String REGION_SQL = "SELECT dbo.fn_region_regulation_json(?, ?)";

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcRegulationQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "lakeRegulationFallback")
    public JsonNode lakeRegulation(String lakeId) {
        List<String> rows = jdbc.query(LAKE_SQL, ps -> ps.setString(1, lakeId), (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    /** Circuit-breaker fallback for {@link #lakeRegulation}. */
    @SuppressWarnings("unused")
    public JsonNode lakeRegulationFallback(String lakeId, Throwable ex) {
        throw new RuntimeException("SQL lake-regulation query failed for id " + lakeId, ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "regionFallback")
    public JsonNode region(String country, String state) {
        List<String> rows = jdbc.query(REGION_SQL,
                ps -> {
                    ps.setString(1, country);
                    ps.setString(2, state);
                },
                (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    /** Circuit-breaker fallback for {@link #region}. */
    @SuppressWarnings("unused")
    public JsonNode regionFallback(String country, String state, Throwable ex) {
        throw new RuntimeException("SQL region-regulation query failed for " + country + "/" + state, ex);
    }

    private JsonNode parse(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("Regulation JSON returned by the database is not valid JSON", ex);
        }
    }
}
