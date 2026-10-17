package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCallback;
import org.springframework.jdbc.core.PreparedStatementSetter;

import java.sql.Statement;

/**
 * JDBC river-link command repository backed by {@code dbo.sp_lake_source_update} /
 * {@code dbo.sp_lake_mouth_update} and {@code dbo.sp_lake_link_assign}. Guarded by Resilience4j retry + circuit breaker, matching {@link
 * JdbcRiverDescriptionCommandRepository}.
 *
 * <p>Invoked via {@code jdbc.execute} with a manual result-set drain, the same pattern used for every
 * other {@code EXEC dbo.sp_...} call in this service (see {@link JdbcRiverDescriptionCommandRepository})
 * — not {@code jdbc.query}, since the procedure's {@code UPDATE} can interleave an update count with
 * its final {@code SELECT}.
 */
public class JdbcRiverLinkCommandRepository implements RiverLinkCommandRepository {

    static final String PATCH_SOURCE_SQL = "EXEC dbo.sp_lake_source_update ?, ?";
    static final String PATCH_MOUTH_SQL = "EXEC dbo.sp_lake_mouth_update ?, ?";
    static final String ASSIGN_POINT_SQL = "EXEC dbo.sp_lake_link_assign ?, ?, ?";

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcRiverLinkCommandRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "patchSourceFallback")
    public JsonNode patchSource(String lakeId, String patchJson) {
        return execPatch(PATCH_SOURCE_SQL, lakeId, patchJson);
    }

    /** Circuit-breaker fallback for {@link #patchSource}. */
    @SuppressWarnings("unused")
    public JsonNode patchSourceFallback(String lakeId, String patchJson, Throwable ex) {
        throw new RuntimeException("SQL river-source patch failed for id " + lakeId, ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "patchMouthFallback")
    public JsonNode patchMouth(String lakeId, String patchJson) {
        return execPatch(PATCH_MOUTH_SQL, lakeId, patchJson);
    }

    /** Circuit-breaker fallback for {@link #patchMouth}. */
    @SuppressWarnings("unused")
    public JsonNode patchMouthFallback(String lakeId, String patchJson, Throwable ex) {
        throw new RuntimeException("SQL river-mouth patch failed for id " + lakeId, ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "assignPointFallback")
    public JsonNode assignPoint(String lakeId, int side, String pointId) {
        return exec(ASSIGN_POINT_SQL, ps -> {
            ps.setString(1, lakeId);
            ps.setInt(2, side);
            ps.setString(3, pointId);
        });
    }

    /** Circuit-breaker fallback for {@link #assignPoint}. */
    @SuppressWarnings("unused")
    public JsonNode assignPointFallback(String lakeId, int side, String pointId, Throwable ex) {
        throw new RuntimeException("SQL river-link assign failed for id " + lakeId, ex);
    }

    private JsonNode execPatch(String sql, String lakeId, String patchJson) {
        return exec(sql, ps -> {
            ps.setString(1, lakeId);
            ps.setString(2, patchJson);
        });
    }

    private JsonNode exec(String sql, PreparedStatementSetter params) {
        String json = jdbc.execute(sql, (PreparedStatementCallback<String>) ps -> {
            params.setValues(ps);
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

    private JsonNode parse(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("River-link patch JSON returned by the database is not valid JSON", ex);
        }
    }
}
