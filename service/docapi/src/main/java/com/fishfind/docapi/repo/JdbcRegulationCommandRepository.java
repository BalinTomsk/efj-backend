package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCallback;

import java.sql.Statement;

/**
 * JDBC regulation command repository backed by {@code dbo.sp_regulation_upsert}. Guarded by
 * Resilience4j retry + circuit breaker, matching {@link JdbcRiverDescriptionCommandRepository}.
 *
 * <p>Invoked via {@code jdbc.execute} with a manual result-set drain, the same pattern used for every
 * other {@code EXEC dbo.sp_...} call in this service — not {@code jdbc.query}, since the procedure's
 * {@code INSERT}/{@code UPDATE} can interleave an update count with its final {@code SELECT}.
 */
public class JdbcRegulationCommandRepository implements RegulationCommandRepository {

    static final String UPSERT_SQL = "EXEC dbo.sp_regulation_upsert ?";

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcRegulationCommandRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "upsertFallback")
    public JsonNode upsert(String bodyJson) {
        String json = jdbc.execute(UPSERT_SQL, (PreparedStatementCallback<String>) ps -> {
            ps.setString(1, bodyJson);
            String scalar = null;
            boolean hasResults = ps.execute();
            while (hasResults || ps.getUpdateCount() != -1) {
                if (hasResults) {
                    try (var rs = ps.getResultSet()) {
                        if (scalar == null && rs != null && rs.next()) {
                            scalar = rs.getString(1);
                        }
                        while (rs != null && rs.next()) {
                            // drain any remaining rows so SQL Server can finish the procedure cleanly
                        }
                    }
                }
                hasResults = ps.getMoreResults(Statement.CLOSE_CURRENT_RESULT);
            }
            return scalar;
        });
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    /** Circuit-breaker fallback for {@link #upsert}. */
    @SuppressWarnings("unused")
    public JsonNode upsertFallback(String bodyJson, Throwable ex) {
        throw new RuntimeException("SQL regulation upsert failed", ex);
    }

    private JsonNode parse(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("Regulation upsert JSON returned by the database is not valid JSON", ex);
        }
    }
}
