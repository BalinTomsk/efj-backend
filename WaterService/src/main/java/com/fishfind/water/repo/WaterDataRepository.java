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

@Repository
public class WaterDataRepository {

    private final JdbcTemplate jdbc;

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

        jdbc.update(
                """
                DELETE FROM dbo.WaterData
                WHERE mli = ?
                  AND stamp < DATEADD(day, -15, GETDATE())
                """,
                mli
        );

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

    @SuppressWarnings("unused")
    public void fallback(String mli, List<Reading> readings, Throwable ex) {
        throw new RuntimeException("SQL save failed for station " + mli, ex);
    }

    private Timestamp toTimestamp(Instant instant) {
        return Timestamp.from(instant);
    }
}