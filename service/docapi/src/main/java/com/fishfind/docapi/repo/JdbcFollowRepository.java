package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Follows on {@code dbo.user_follow} through {@code sp_user_follow_set} and {@code fn_user_follow_list_json}, guarded by
 * the shared {@code sqlBreaker}. The procedure answers with a result code instead of failing, so a caller mistake never
 * counts against the breaker; setting the same state twice is harmless, so both calls may retry.
 */
public class JdbcFollowRepository implements FollowRepository {

    static final String LIST_SQL = "SELECT dbo.fn_user_follow_list_json(?)";

    static final String SET_SQL = "SET NOCOUNT ON; DECLARE @r INT; "
            + "EXEC dbo.sp_user_follow_set @userid = ?, @kind = ?, @target = ?, @follow = ?, @result = @r OUTPUT; "
            + "SELECT @r AS r;";

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcFollowRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "mineFallback")
    public JsonNode mine(String userId) {
        String json = jdbc.queryForObject(LIST_SQL, String.class, userId);
        try {
            return objectMapper.readTree(json == null || json.isBlank() ? "{\"waters\":[],\"fish\":[]}" : json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("Follow JSON returned by the database is not valid JSON", ex);
        }
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "setFallback")
    public int set(String userId, int kind, String targetId, boolean follow) {
        Integer r = jdbc.queryForObject(SET_SQL, Integer.class, userId, kind, targetId, follow);
        return r == null ? INVALID : r;
    }

    @SuppressWarnings("unused")
    public JsonNode mineFallback(String userId, Throwable ex) {
        throw new RuntimeException("SQL follow list failed", ex);
    }

    @SuppressWarnings("unused")
    public int setFallback(String userId, int kind, String targetId, boolean follow, Throwable ex) {
        throw new RuntimeException("SQL follow set failed for " + targetId, ex);
    }
}
