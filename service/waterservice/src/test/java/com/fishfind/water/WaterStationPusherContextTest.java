package com.fishfind.water;

import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.retry.RetryRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.UncategorizedSQLException;

import java.sql.SQLException;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class WaterStationPusherContextTest {

    @Autowired
    private RetryRegistry retryRegistry;

    @Autowired
    private CircuitBreakerRegistry circuitBreakerRegistry;

    @Test
    void contextLoadsWithTestConfiguration() {
    }

    @Test
    void sqlRetryAndBreakerIgnoreAProcedureRefusal() {
        // SQLSTATE 45000 = an envdata procedure's SIGNAL (unknown station): neither retried nor counted by the breaker.
        UncategorizedSQLException refusal = new UncategorizedSQLException("CALL", "CALL",
                new SQLException("sp_water_save_ca: unknown station mli", "45000", 1644));
        UncategorizedSQLException outage = new UncategorizedSQLException("CALL", "CALL",
                new SQLException("Communications link failure", "08S01"));

        var retry = retryRegistry.retry("sqlRetry").getRetryConfig().getExceptionPredicate();
        assertFalse(retry.test(refusal));
        assertTrue(retry.test(outage));
        assertFalse(retry.test(new IllegalArgumentException("mli")));

        var breaker = circuitBreakerRegistry.circuitBreaker("sqlBreaker").getCircuitBreakerConfig();
        assertTrue(breaker.getIgnoreExceptionPredicate().test(refusal));
        assertFalse(breaker.getIgnoreExceptionPredicate().test(outage));
    }
}
