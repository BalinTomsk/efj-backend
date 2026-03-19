package com.fishfind.water.repo;

import com.fishfind.water.domain.Reading;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;

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
/*
        jdbc.update(
                """
                DELETE FROM dbo.WaterData
                WHERE mli = ?
                  AND stamp < DATEADD(day, -15, GETDATE())
                """,
                mli
        );
*/
        final String mergeSql =
                """
                MERGE dbo.WaterData AS trg
                USING (
                    SELECT
                        CAST(? AS varchar(64)) AS mli,
                        CAST(? AS datetime2)   AS stamp
                ) AS src
                ON trg.mli = src.mli
                   AND trg.stamp = src.stamp
                WHEN MATCHED THEN
                    UPDATE SET
                        elevation = ?,
                        discharge = ?
                WHEN NOT MATCHED THEN
                    INSERT (mli, stamp, elevation, discharge)
                    VALUES (src.mli, src.stamp, ?, ?);
                """;

        for (Reading reading : readings) {
            if (reading == null || reading.stamp() == null) {
                continue;
            }

            Timestamp stamp = Timestamp.from(reading.stamp().toInstant());

            jdbc.update(
                    mergeSql,
                    mli,
                    stamp,
                    reading.waterLevel(),  // goes to legacy "elevation" column
                    reading.discharge(),
                    reading.waterLevel(),
                    reading.discharge()
            );
        }
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
     * Converts an instant to a JDBC timestamp.
     *
     * @param instant instant to convert
     * @return JDBC timestamp representation
     */
    private Timestamp toTimestamp(Instant instant) {
        return Timestamp.from(instant);
    }
}
