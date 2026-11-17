package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Saved spots on {@code dbo.user_spot} through its procedures and list function, guarded by the shared
 * {@code sqlBreaker}. Every rule (owner only, 500 per account, valid name and coordinates) is enforced by the
 * procedures, which answer with a result code instead of failing, so a caller mistake never counts against the breaker.
 * {@link #save} may retry (the id is the caller's, so a second attempt updates); {@link #delete} too (deleting twice
 * leaves the same state).
 */
public class JdbcSpotRepository implements SpotRepository {

    static final String LIST_SQL = "SELECT dbo.fn_user_spot_list_json(?)";

    static final String SAVE_SQL = "SET NOCOUNT ON; DECLARE @r INT; "
            + "EXEC dbo.sp_user_spot_save @id = ?, @userid = ?, @name = ?, @lat = ?, @lon = ?, @lake_id = ?, @note = ?, "
            + "@result = @r OUTPUT; SELECT @r AS r;";

    static final String DELETE_SQL = "SET NOCOUNT ON; DECLARE @d INT; "
            + "EXEC dbo.sp_user_spot_delete @id = ?, @userid = ?, @deleted = @d OUTPUT; SELECT @d AS d;";

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcSpotRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "mineFallback")
    public JsonNode mine(String userId) {
        String json = jdbc.queryForObject(LIST_SQL, String.class, userId);
        try {
            return objectMapper.readTree(json == null || json.isBlank() ? "[]" : json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("Saved-spot JSON returned by the database is not valid JSON", ex);
        }
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "saveFallback")
    public int save(String id, String userId, String name, double lat, double lon, String lakeId, String note) {
        Integer r = jdbc.queryForObject(SAVE_SQL, Integer.class, id, userId, name, lat, lon, lakeId, note);
        return r == null ? INVALID : r;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "deleteFallback")
    public boolean delete(String id, String userId) {
        Integer d = jdbc.queryForObject(DELETE_SQL, Integer.class, id, userId);
        return d != null && d > 0;
    }

    @SuppressWarnings("unused")
    public JsonNode mineFallback(String userId, Throwable ex) {
        throw new RuntimeException("SQL saved-spot list failed", ex);
    }

    @SuppressWarnings("unused")
    public int saveFallback(String id, String userId, String name, double lat, double lon, String lakeId, String note,
                            Throwable ex) {
        throw new RuntimeException("SQL saved-spot save failed for " + id, ex);
    }

    @SuppressWarnings("unused")
    public boolean deleteFallback(String id, String userId, Throwable ex) {
        throw new RuntimeException("SQL saved-spot delete failed for " + id, ex);
    }
}
