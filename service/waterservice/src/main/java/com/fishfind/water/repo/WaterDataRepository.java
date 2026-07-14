package com.fishfind.water.repo;

import com.fishfind.water.domain.Reading;
import com.fishfind.water.domain.UsSeriesReading;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCallback;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.sql.Statement;
import java.sql.Types;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Persists parsed station readings into the legacy {@code dbo.WaterData} table.
 */
@Repository
public class WaterDataRepository {

    private final JdbcTemplate jdbc;

    /**
     * Creates a repository backed by Spring JDBC.
     *
     * @param jdbc JDBC template used for SQL operations
     */
    public WaterDataRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * Saves all readings for a single water station immediately.
     *
     * Logic:
     * 1. Remove old WaterData rows older than 15 days for this station.
     * 2. Upsert each CSV reading into WaterData using (mli, stamp) as the natural key.
     * 3. Store CSV "Water Level" into legacy DB column "elevation".
     * 4. Store CSV "Discharge" into DB column "discharge".
     *
     * Notes:
     * - Resilience4j is applied only to SQL operations.
     * - Entire station save runs in one transaction.
     * - CSV timestamp should already be parsed as OffsetDateTime/Instant in Reading.
     *
     * @param mli station identifier
     * @param readings readings to upsert for the station
     */
    @Transactional
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fallback")
    public void saveStationData(String mli, List<Reading> readings) {
        if (mli == null || mli.isBlank()) {
            throw new IllegalArgumentException("mli must not be null or blank");
        }

        if (readings == null || readings.isEmpty()) {
            return;
        }
        final String upsertSql = "EXEC dbo.sp_UpdateWaterData ?, ?, ?, ?";

        List<Reading> unique = deduplicateByTimestamp(readings);
        if (unique.isEmpty()) {
            return;
        }

        // One JDBC batch instead of one round-trip per reading: the DB is remote, and a cycle can push
        // tens of thousands of readings.
        jdbc.batchUpdate(upsertSql, unique, unique.size(), (ps, reading) -> {
            ps.setString(1, mli);
            ps.setTimestamp(2, toTimestamp(reading.stamp().toInstant()));
            ps.setObject(3, reading.waterLevel(), Types.DOUBLE);  // goes to legacy "elevation" column
            ps.setObject(4, reading.discharge(), Types.DOUBLE);
        });
    }

    /**
     * Saves USGS station series using the legacy stored procedure used by the old ASP.NET worker.
     *
     * @param mli station identifier
     * @param state US state code
     * @param seriesList parsed USGS variable payloads
     */
    @Transactional
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fallbackUs")
    public void saveUsStationData(String mli, String state, List<UsSeriesReading> seriesList) {
        if (mli == null || mli.isBlank()) {
            throw new IllegalArgumentException("mli must not be null or blank");
        }
        if (state == null || state.isBlank()) {
            throw new IllegalArgumentException("state must not be null or blank");
        }
        if (seriesList == null || seriesList.isEmpty()) {
            return;
        }

        final String sql = "EXEC dbo.sp_push_us_water_data ?, ?, ?, ?, ?";
        for (UsSeriesReading series : seriesList) {
            if (series == null || series.name() == null || series.name().isBlank() || series.xmlDoc() == null
                    || series.xmlDoc().isBlank()) {
                continue;
            }

            jdbc.execute(sql, (PreparedStatementCallback<Void>) ps -> {
                ps.setString(1, mli);
                ps.setString(2, state);
                ps.setString(3, series.name());
                ps.setString(4, series.unit());
                ps.setString(5, series.xmlDoc());

                boolean hasResults = ps.execute();
                while (hasResults || ps.getUpdateCount() != -1) {
                    if (hasResults) {
                        try (var ignored = ps.getResultSet()) {
                            // Drain result sets produced by the legacy procedure so the driver can complete cleanly.
                        }
                    }
                    hasResults = ps.getMoreResults(Statement.CLOSE_CURRENT_RESULT);
                }
                return null;
            });
        }
    }

    /**
     * Pushes lake species associations down to stations after station processing completes.
     */
    @Transactional
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fallbackProcedure")
    public void pushSpeciesFromLakeToStation() {
        executeProcedureAllowingResults("EXEC dbo.spPushSpeciesFromLakeToStation");
    }

    /**
     * Deletes stale water data after each station-processing cycle completes.
     */
    @Transactional
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fallbackProcedure")
    public void cleanOldWaterData() {
        executeProcedureAllowingResults("EXEC dbo.sp_clean_old_water_data");
    }

    /**
     * Collapses duplicate timestamps from a single CSV batch so each station/timestamp pair is saved once.
     *
     * @param readings raw parsed readings
     * @return readings keyed by timestamp in original iteration order, keeping the latest duplicate
     */
    private List<Reading> deduplicateByTimestamp(List<Reading> readings) {
        Map<Instant, Reading> uniqueReadings = new LinkedHashMap<>();
        for (Reading reading : readings) {
            if (reading == null || reading.stamp() == null) {
                continue;
            }

            uniqueReadings.put(
                    reading.stamp().toInstant(),
                    reading
            );
        }

        return List.copyOf(uniqueReadings.values());
    }

    /**
     * Converts a Resilience4j fallback callback into an unchecked failure for the caller.
     *
     * @param mli station identifier
     * @param readings readings that failed to save
     * @param ex original SQL-related exception
     */
    @SuppressWarnings("unused")
    public void fallback(String mli, List<Reading> readings, Throwable ex) {
        throw new RuntimeException("SQL save failed for station " + mli, ex);
    }

    /**
     * Converts a Resilience4j fallback callback for US stored-procedure saves into an unchecked failure.
     *
     * @param mli station identifier
     * @param state US state code
     * @param seriesList payloads that failed to save
     * @param ex original SQL-related exception
     */
    @SuppressWarnings("unused")
    public void fallbackUs(String mli, String state, List<UsSeriesReading> seriesList, Throwable ex) {
        throw new RuntimeException("SQL save failed for US station " + mli, ex);
    }

    /**
     * Converts a stored-procedure fallback into an unchecked failure.
     *
     * @param ex original SQL-related exception
     */
    @SuppressWarnings("unused")
    public void fallbackProcedure(Throwable ex) {
        throw new RuntimeException("SQL stored procedure execution failed", ex);
    }

    /**
     * Converts an instant to a JDBC timestamp.
     *
     * @param instant instant to convert
     * @return JDBC timestamp representation
     */
    private Timestamp toTimestamp(Instant instant) {
        return Timestamp.from(instant);
    }

    /**
     * Executes a stored procedure that may emit update counts and incidental result sets.
     */
    private void executeProcedureAllowingResults(String sql) {
        jdbc.execute(sql, (PreparedStatementCallback<Void>) ps -> {
            boolean hasResults = ps.execute();
            while (hasResults || ps.getUpdateCount() != -1) {
                if (hasResults) {
                    try (var ignored = ps.getResultSet()) {
                        // Drain any result set so SQL Server can finish the procedure cleanly.
                    }
                }
                hasResults = ps.getMoreResults(Statement.CLOSE_CURRENT_RESULT);
            }
            return null;
        });
    }
}
