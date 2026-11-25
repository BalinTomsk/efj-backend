package com.fishfind.water.repo;

import com.fasterxml.jackson.core.JsonFactory;
import com.fasterxml.jackson.core.JsonGenerator;
import com.fishfind.water.domain.Reading;
import com.fishfind.water.domain.UsSeriesReading;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.io.StringWriter;
import java.io.UncheckedIOException;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * Persists parsed station readings into the MySQL {@code envdata} database through its procedures
 * ({@code envfish-db/mysql/envdata/script02_Proc.sql}; no table is touched directly), records each finished cycle in
 * {@code job_run} and runs the retention. A functional copy of the C# twin's {@code WaterDataRepository} (11.0.0).
 *
 * <p>Every method is wrapped in {@code sqlRetry} + {@code sqlBreaker}; an envdata procedure's own refusal
 * (SQLSTATE 45000) is neither retried nor counted (see {@code SqlFailures}).
 */
@Repository
public class WaterDataRepository {

    /**
     * Readings per CA call. One call carries a JSON array, so there is no parameter cap; 500 keeps a call short (a
     * typical file is one or two calls) and bounds the statement envdata expands with JSON_TABLE.
     */
    static final int MAX_READINGS_PER_BATCH = 500;

    /** {@code job_run.service} of this service's cycles (the same as the C# twin's). */
    public static final String SERVICE_NAME = "waterservice";

    static final String SAVE_CA = "CALL sp_water_save_ca(?, ?)";
    static final String SAVE_US = "CALL sp_water_save_us(?, ?, ?)";
    static final String RECORD_CYCLE = "CALL sp_job_run_record(?, ?, ?, ?, ?, ?, ?, @out_job_run_id)";
    static final String CLEAN_OLD = "CALL sp_clean_old_water_data(NULL)";

    private static final DateTimeFormatter STAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final JsonFactory JSON = new JsonFactory();

    private final JdbcTemplate jdbc;

    public WaterDataRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * Saves all readings for a single Canadian station in one transaction.
     *
     * <p>Readings are de-duplicated by timestamp (last one wins), then upserted through
     * {@code sp_water_save_ca(mli, rows)}, at most {@value #MAX_READINGS_PER_BATCH} per call: the CSV "Water Level"
     * is {@code e}, "Discharge" is {@code d}, the time is UTC. The procedure overwrites a reading at the same time,
     * stores {@code -999} as NULL and refreshes the station's current state. Retention is not per call:
     * {@link #cleanOldWaterData()} drops whole days.
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

        List<Reading> unique = deduplicateByTimestamp(readings);
        for (int from = 0; from < unique.size(); from += MAX_READINGS_PER_BATCH) {
            List<Reading> chunk = unique.subList(from, Math.min(unique.size(), from + MAX_READINGS_PER_BATCH));
            jdbc.update(SAVE_CA, mli, buildCaRowsJson(chunk));
        }
    }

    /**
     * Saves all of one USGS station's series in ONE call to {@code sp_water_save_us(mli, state, series)}, which
     * merges every series of a day into one reading, converts the units (pressure to mm Hg) and refreshes the
     * station's current state.
     *
     * @param mli station identifier
     * @param state US state code (first two characters are sent)
     * @param seriesList one point per series
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

        List<UsSeriesReading> series = seriesList.stream()
                .filter(s -> s != null && s.name() != null && !s.name().isBlank() && s.day() != null
                        && Double.isFinite(s.value()))
                .toList();
        if (series.isEmpty()) {
            return;
        }

        jdbc.update(SAVE_US, mli, state.length() > 2 ? state.substring(0, 2) : state, buildUsSeriesJson(series));
    }

    /**
     * Records one finished cycle in envdata's {@code job_run} ({@code sp_job_run_record}). env_service picks
     * unhanded cycles up and does the fish hand-over to SQL Server (species push + probability update), which this
     * service did itself until 1.14.0.
     *
     * @param job {@code water-ca}, {@code water-us} or {@code water}
     * @param startedUtc cycle start, UTC
     * @param finishedUtc cycle end, UTC
     * @param status {@code ok} or {@code partial}
     * @param items stations processed successfully
     * @param note free text (at most 255 characters are kept), or {@code null}
     */
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fallbackRecord")
    public void recordCycle(String job, LocalDateTime startedUtc, LocalDateTime finishedUtc, String status,
                            int items, String note) {
        jdbc.update(RECORD_CYCLE, SERVICE_NAME, job, startedUtc, finishedUtc, status, items,
                note == null ? null : (note.length() > 255 ? note.substring(0, 255) : note));
    }

    /**
     * Retention after each cycle ({@code sp_clean_old_water_data(NULL)}: raw readings 30 days by dropping whole day
     * partitions, daily aggregates and job runs 30 days). Partition DDL commits implicitly, so this is never inside a
     * transaction. A no-op on most calls: only a new day adds or drops a partition.
     */
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fallbackProcedure")
    public void cleanOldWaterData() {
        jdbc.update(CLEAN_OLD);
    }

    /**
     * The {@code rows} JSON of {@code sp_water_save_ca}: {@code [{"s":"yyyy-MM-dd HH:mm:ss","e":level,"d":discharge}]},
     * time in UTC, a missing or non-finite value as {@code null}.
     */
    static String buildCaRowsJson(List<Reading> readings) {
        StringWriter out = new StringWriter();
        try (JsonGenerator json = JSON.createGenerator(out)) {
            json.writeStartArray();
            for (Reading reading : readings) {
                json.writeStartObject();
                json.writeStringField("s", STAMP.format(reading.stamp().atZoneSameInstant(ZoneOffset.UTC)));
                writeNumberOrNull(json, "e", reading.waterLevel());
                writeNumberOrNull(json, "d", reading.discharge());
                json.writeEndObject();
            }
            json.writeEndArray();
        } catch (IOException ex) {
            throw new UncheckedIOException(ex);
        }
        return out.toString();
    }

    /**
     * The {@code series} JSON of {@code sp_water_save_us}:
     * {@code [{"name":"Streamflow","unit":"ft^3/s","points":[{"d":"yyyy-MM-dd","v":12.5}]}]}, grouped by name and
     * unit in first-seen order.
     */
    static String buildUsSeriesJson(List<UsSeriesReading> series) {
        Map<List<String>, List<UsSeriesReading>> groups = new LinkedHashMap<>();
        for (UsSeriesReading point : series) {
            groups.computeIfAbsent(java.util.Arrays.asList(point.name(), point.unit()), k -> new java.util.ArrayList<>())
                    .add(point);
        }

        StringWriter out = new StringWriter();
        try (JsonGenerator json = JSON.createGenerator(out)) {
            json.writeStartArray();
            for (Map.Entry<List<String>, List<UsSeriesReading>> group : groups.entrySet()) {
                json.writeStartObject();
                json.writeStringField("name", group.getKey().get(0));
                String unit = group.getKey().get(1);
                if (unit == null) {
                    json.writeNullField("unit");
                } else {
                    json.writeStringField("unit", unit);
                }
                json.writeArrayFieldStart("points");
                for (UsSeriesReading point : group.getValue()) {
                    json.writeStartObject();
                    json.writeStringField("d", point.day().toString());
                    json.writeNumberField("v", point.value());
                    json.writeEndObject();
                }
                json.writeEndArray();
                json.writeEndObject();
            }
            json.writeEndArray();
        } catch (IOException ex) {
            throw new UncheckedIOException(ex);
        }
        return out.toString();
    }

    private static void writeNumberOrNull(JsonGenerator json, String name, Double value) throws IOException {
        if (value != null && Double.isFinite(value)) {
            json.writeNumberField(name, value);
        } else {
            json.writeNullField(name);
        }
    }

    /**
     * Collapses duplicate timestamps from a single CSV batch so each station/timestamp pair is saved once.
     *
     * @return readings keyed by timestamp in original iteration order, keeping the latest duplicate
     */
    private static List<Reading> deduplicateByTimestamp(List<Reading> readings) {
        Map<Instant, Reading> unique = new LinkedHashMap<>();
        readings.stream()
                .filter(Objects::nonNull)
                .filter(r -> r.stamp() != null)
                .forEach(r -> unique.put(r.stamp().toInstant(), r));
        return List.copyOf(unique.values());
    }

    @SuppressWarnings("unused")
    public void fallback(String mli, List<Reading> readings, Throwable ex) {
        throw new RuntimeException("SQL save failed for station " + mli, ex);
    }

    @SuppressWarnings("unused")
    public void fallbackUs(String mli, String state, List<UsSeriesReading> seriesList, Throwable ex) {
        throw new RuntimeException("SQL save failed for US station " + mli, ex);
    }

    @SuppressWarnings("unused")
    public void fallbackRecord(String job, LocalDateTime startedUtc, LocalDateTime finishedUtc, String status,
                               int items, String note, Throwable ex) {
        throw new RuntimeException("Recording cycle " + job + " in job_run failed", ex);
    }

    @SuppressWarnings("unused")
    public void fallbackProcedure(Throwable ex) {
        throw new RuntimeException("SQL stored procedure execution failed", ex);
    }
}
