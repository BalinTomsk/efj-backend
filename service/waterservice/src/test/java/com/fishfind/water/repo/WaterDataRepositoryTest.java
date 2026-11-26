package com.fishfind.water.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.water.config.SqlFailures;
import com.fishfind.water.domain.Reading;
import com.fishfind.water.domain.UsSeriesReading;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.UncategorizedSQLException;
import org.springframework.jdbc.core.JdbcTemplate;

import java.sql.SQLException;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.List;
import java.util.stream.IntStream;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

/**
 * Pins the SQL text and the JSON the envdata procedures expand with JSON_TABLE ({@code sp_water_save_ca} rows,
 * {@code sp_water_save_us} series) and the SQL failure rule. A mock never parses SQL: {@link WaterEngineTest} runs
 * the same repositories against a real MySQL engine.
 */
class WaterDataRepositoryTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final WaterDataRepository repository = new WaterDataRepository(jdbc);

    @Test
    void saveStationDataRejectsBlankMli() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> repository.saveStationData(" ", List.of()));

        assertEquals("mli must not be null or blank", ex.getMessage());
    }

    @Test
    void saveStationDataSkipsEmptyInput() {
        repository.saveStationData("02JE025", List.of());

        verifyNoInteractions(jdbc);
    }

    @Test
    void saveStationDataSendsValidDeduplicatedReadingsAsOneJsonArray() throws Exception {
        OffsetDateTime stamp = OffsetDateTime.of(2024, 1, 2, 3, 4, 0, 0, ZoneOffset.ofHours(-5));
        Reading first = new Reading("02JE025", stamp, 1.2, 3.4);
        Reading duplicate = new Reading("02JE025", stamp, 9.9, 8.8);
        Reading missingStamp = new Reading("02JE025", null, 2.0, 4.0);

        repository.saveStationData("02JE025", Arrays.asList(first, null, missingStamp, duplicate));

        ArgumentCaptor<String> rows = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(eq("CALL sp_water_save_ca(?, ?)"), eq("02JE025"), rows.capture());
        // Time in UTC, the latest duplicate wins.
        assertEquals("[{\"s\":\"2024-01-02 08:04:00\",\"e\":9.9,\"d\":8.8}]", rows.getValue());
    }

    @Test
    void saveStationDataSplitsIntoCallsOf500Readings() throws Exception {
        OffsetDateTime t = OffsetDateTime.of(2026, 11, 24, 10, 0, 0, 0, ZoneOffset.UTC);
        List<Reading> readings = IntStream.range(0, 1001)
                .mapToObj(i -> new Reading("x", t.minusMinutes(5L * i), 1.0, 2.0))
                .toList();

        repository.saveStationData("02JE025", readings);

        ArgumentCaptor<String> rows = ArgumentCaptor.forClass(String.class);
        verify(jdbc, times(3)).update(eq("CALL sp_water_save_ca(?, ?)"), eq("02JE025"), rows.capture());
        assertEquals(List.of(500, 500, 1),
                rows.getAllValues().stream().map(json -> readTree(json).size()).toList());
    }

    @Test
    void caRowsJsonWritesMissingAndNonFiniteValuesAsNull() {
        String json = WaterDataRepository.buildCaRowsJson(List.of(
                new Reading("x", OffsetDateTime.of(2026, 11, 24, 10, 0, 0, 0, ZoneOffset.UTC), null, Double.NaN)));

        assertEquals("[{\"s\":\"2026-11-24 10:00:00\",\"e\":null,\"d\":null}]", json);
    }

    @Test
    void saveUsStationDataRejectsBlankState() {
        assertThrows(IllegalArgumentException.class, () -> repository.saveUsStationData("08313000", " ", List.of()));
    }

    @Test
    void saveUsStationDataSendsAllSeriesOfAStationInOneCall() {
        LocalDate day = LocalDate.of(2026, 11, 23);
        repository.saveUsStationData("08313000", "NMX", List.of(
                new UsSeriesReading("Streamflow", "ft^3/s", day, 12.5),
                new UsSeriesReading("pH", null, day, 7.62),
                new UsSeriesReading(" ", "x", day, 1),                       // no name: dropped
                new UsSeriesReading("Gage height", "ft", day, Double.NaN),   // not finite: dropped
                new UsSeriesReading("Streamflow", "ft^3/s", day.plusDays(1), 13)));

        ArgumentCaptor<String> series = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(eq("CALL sp_water_save_us(?, ?, ?)"), eq("08313000"), eq("NM"), series.capture());
        JsonNode root = readTree(series.getValue());
        assertEquals(2, root.size());
        assertEquals("Streamflow", root.get(0).get("name").asText());
        assertEquals("ft^3/s", root.get(0).get("unit").asText());
        assertEquals(2, root.get(0).get("points").size());
        assertEquals("2026-11-23", root.get(0).get("points").get(0).get("d").asText());
        assertEquals(12.5, root.get(0).get("points").get(0).get("v").asDouble());
        assertTrue(root.get(1).get("unit").isNull());
    }

    @Test
    void saveUsStationDataSkipsAStationWithNoValidSeries() {
        repository.saveUsStationData("08313000", "NM",
                List.of(new UsSeriesReading("", "ft", LocalDate.of(2026, 11, 23), 1)));

        verifyNoInteractions(jdbc);
    }

    @Test
    void recordCycleCallsJobRunRecordWithTheOutParameterAsASessionVariable() {
        LocalDateTime started = LocalDateTime.of(2026, 11, 25, 18, 0);
        LocalDateTime finished = started.plusMinutes(40);

        repository.recordCycle("water-ca", started, finished, "partial", 1500, "x".repeat(300));

        verify(jdbc).update("CALL sp_job_run_record(?, ?, ?, ?, ?, ?, ?, @out_job_run_id)",
                "waterservice", "water-ca", started, finished, "partial", 1500, "x".repeat(255));
    }

    @Test
    void cleanOldWaterDataCallsTheRetentionProcedure() {
        repository.cleanOldWaterData();

        verify(jdbc).update("CALL sp_clean_old_water_data(NULL)");
    }

    @Test
    void sqlFailureRuleIgnoresAProcedureRefusal() {
        // SQLSTATE 45000 = an envdata procedure's own SIGNAL (e.g. unknown station mli): a bad request, not an outage.
        SQLException refusal = new SQLException("sp_water_save_ca: unknown station mli", "45000", 1644);
        assertFalse(SqlFailures.isSqlFailure(new UncategorizedSQLException("CALL", "CALL", refusal)));
        assertTrue(SqlFailures.isProcedureRefusal(new RuntimeException(new UncategorizedSQLException("x", "x", refusal))));

        assertTrue(SqlFailures.isSqlFailure(new SQLException("Communications link failure", "08S01")));
        assertTrue(SqlFailures.isSqlFailure(new DataIntegrityViolationException("dup")));
        assertFalse(SqlFailures.isSqlFailure(new IllegalArgumentException("mli")));
    }

    @Test
    void fallbacksWrapTheOriginalException() {
        IllegalStateException cause = new IllegalStateException("db down");

        RuntimeException ca = assertThrows(RuntimeException.class, () -> repository.fallback("02JE025", List.of(), cause));
        RuntimeException us = assertThrows(RuntimeException.class,
                () -> repository.fallbackUs("08313000", "NM", List.of(), cause));
        RuntimeException record = assertThrows(RuntimeException.class,
                () -> repository.fallbackRecord("water", null, null, "ok", 1, null, cause));

        assertEquals("SQL save failed for station 02JE025", ca.getMessage());
        assertEquals("SQL save failed for US station 08313000", us.getMessage());
        assertInstanceOf(IllegalStateException.class, record.getCause());
    }

    private static JsonNode readTree(String json) {
        try {
            return MAPPER.readTree(json);
        } catch (Exception ex) {
            throw new AssertionError(ex);
        }
    }
}
