package com.fishfind.weather.repo;

import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCallback;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Statement;

/**
 * Persists raw weather payloads into the legacy {@code dbo.ows_meteo} table and
 * runs the post-processing procedures used by the original service.
 *
 * <p>The direct {@code UPDATE dbo.ows_meteo} below is an intentional, grandfathered exception
 * to the house rule that application code goes through a view/function/procedure rather than
 * a raw table: this mirrors the legacy {@code WeatherDataWorkerOpen} .NET service exactly, and
 * the rule only applies to methods added or changed going forward. If a save procedure for
 * this table (e.g. {@code spSaveStationWeather}) is ever introduced, switch this method to
 * call it instead of writing a new raw-table statement elsewhere.
 */
@Repository
public class WeatherDataRepository {
    private static final Logger log = LoggerFactory.getLogger(WeatherDataRepository.class);

    private final JdbcTemplate jdbc;

    public WeatherDataRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Transactional
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fallbackSave")
    public void saveStationData(String mli, String jsonData) {
        if (mli == null || mli.isBlank()) {
            throw new IllegalArgumentException("mli must not be null or blank");
        }
        if (jsonData == null || jsonData.isBlank()) {
            return;
        }

        int rows = jdbc.update(
                "UPDATE dbo.ows_meteo SET type = ?, ows = ?, stamp = GETDATE() WHERE mli = ?",
                2,
                jsonData,
                mli
        );
        if (rows == 0) {
            log.warn("No ows_meteo row matched; payload dropped. mli={} bytes={}", mli, jsonData.length());
        }
    }

    @Transactional
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fallbackProcedure")
    public void pushSpeciesFromLakeToStation() {
        executeProcedureAllowingResults("EXEC dbo.spPushSpeciesFromLakeToStation");
    }

    @Transactional
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fallbackProcedure")
    public void totalUpdateProbability() {
        executeProcedureAllowingResults("EXEC dbo.spTotalUpdateProbability");
    }

    @SuppressWarnings("unused")
    public void fallbackSave(String mli, String jsonData, Throwable ex) {
        throw new RuntimeException("SQL save failed for station " + mli, ex);
    }

    @SuppressWarnings("unused")
    public void fallbackProcedure(Throwable ex) {
        throw new RuntimeException("SQL stored procedure execution failed", ex);
    }

    private void executeProcedureAllowingResults(String sql) {
        jdbc.execute(sql, (PreparedStatementCallback<Void>) ps -> {
            boolean hasResults = ps.execute();
            while (hasResults || ps.getUpdateCount() != -1) {
                if (hasResults) {
                    try (var ignored = ps.getResultSet()) {
                        // Drain incidental result sets so SQL Server can complete the procedure cleanly.
                    }
                }
                hasResults = ps.getMoreResults(Statement.CLOSE_CURRENT_RESULT);
            }
            return null;
        });
    }
}
