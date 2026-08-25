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
 * JDBC river-fish command repository backed by {@code dbo.sp_lake_fish_upsert_batch}. Guarded by
 * Resilience4j retry + circuit breaker, matching {@link JdbcRiverQueryRepository}.
 *
 * <p>Invoked via {@code jdbc.execute} with a manual result-set drain, the same pattern
 * {@code JdbcDocumentRepository.executeReturningScalar} and {@code JdbcNewsQueryRepository.importNews}
 * use for every other {@code EXEC dbo.sp_...} call in this service — a stored procedure's DML
 * statements can interleave update counts with its final {@code SELECT}, which the simpler
 * {@code jdbc.query} row-mapper path is not built to skip over.
 */
public class JdbcRiverFishCommandRepository implements RiverFishCommandRepository {

    static final String UPSERT_SQL = "EXEC dbo.sp_lake_fish_upsert_batch ?, ?";

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcRiverFishCommandRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "upsertFishFallback")
    public JsonNode upsertFish(String lakeId, String fishJsonArray) {
        String json = jdbc.execute(UPSERT_SQL, (PreparedStatementCallback<String>) ps -> {
            ps.setString(1, lakeId);
            ps.setString(2, fishJsonArray);
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

    /** Circuit-breaker fallback for {@link #upsertFish}. */
    @SuppressWarnings("unused")
    public JsonNode upsertFishFallback(String lakeId, String fishJsonArray, Throwable ex) {
        throw new RuntimeException("SQL river-fish upsert failed for id " + lakeId, ex);
    }

    private JsonNode parse(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("River-fish upsert JSON returned by the database is not valid JSON", ex);
        }
    }
}
