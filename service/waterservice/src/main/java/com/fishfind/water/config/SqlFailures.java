package com.fishfind.water.config;

import io.github.resilience4j.common.circuitbreaker.configuration.CircuitBreakerConfigCustomizer;
import io.github.resilience4j.common.retry.configuration.RetryConfigCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.dao.DataAccessException;

import java.sql.SQLException;

/**
 * Which SQL failures the {@code sqlRetry} retry and the {@code sqlBreaker} circuit breaker handle: any database or
 * data-access error, EXCEPT an envdata procedure's own refusal, SQLSTATE {@code 45000} (e.g. "unknown station mli").
 * That is a bad request, not an outage: retrying it changes nothing, and counting it would let one bad station open
 * the breaker for every other one. Same rule as the C# twin's {@code ResiliencePipelines.IsSqlFailure}.
 *
 * <p>Set in code rather than in {@code application.yml} (git-ignored): the customizers run after the properties, and
 * clear any {@code retry-exceptions} list there, which Resilience4j would otherwise OR with this predicate.
 */
@Configuration
public class SqlFailures {

    /** SQLSTATE of {@code SIGNAL SQLSTATE '45000'} in envdata's procedures. */
    public static final String PROCEDURE_REFUSAL = "45000";

    /**
     * @return {@code true} when {@code ex} is a SQL failure worth retrying / counting
     */
    public static boolean isSqlFailure(Throwable ex) {
        if (isProcedureRefusal(ex)) {
            return false;
        }
        return ex instanceof DataAccessException || ex instanceof SQLException;
    }

    /**
     * @return {@code true} when {@code ex} or one of its causes is a {@link SQLException} with SQLSTATE 45000
     */
    public static boolean isProcedureRefusal(Throwable ex) {
        for (Throwable t = ex; t != null; t = t.getCause() == t ? null : t.getCause()) {
            if (t instanceof SQLException sql) {
                for (SQLException s = sql; s != null; s = s.getNextException()) {
                    if (PROCEDURE_REFUSAL.equals(s.getSQLState())) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    @Bean
    public RetryConfigCustomizer sqlRetryCustomizer() {
        return RetryConfigCustomizer.of("sqlRetry", builder -> builder
                .retryExceptions()
                .retryOnException(t -> isSqlFailure((Throwable) t)));
    }

    @Bean
    public CircuitBreakerConfigCustomizer sqlBreakerCustomizer() {
        return CircuitBreakerConfigCustomizer.of("sqlBreaker", builder -> builder
                .ignoreException(SqlFailures::isProcedureRefusal));
    }
}
