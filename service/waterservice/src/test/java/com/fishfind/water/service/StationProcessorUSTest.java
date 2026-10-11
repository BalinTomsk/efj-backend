package com.fishfind.water.service;

import com.fishfind.water.domain.UsSeriesReading;
import com.fishfind.water.domain.UsgsObservation;
import com.fishfind.water.repo.WaterDataRepository;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class StationProcessorUSTest {
    private static final ZoneId MOUNTAIN = UsgsWaterDataClient.resolveTimeZone("MST", "Y");

    private static UsgsObservation obs(String code, String time, String value, String statistic) {
        return new UsgsObservation(code, statistic, OffsetDateTime.parse(time), value);
    }

    private static UsgsObservation obs(String code, String time, String value) {
        return obs(code, time, value, "00011");
    }

    @Test
    void buildReadingsUsesLegacyNameAndUnit() {
        // sp_push_us_water_data keys its unit conversion on the exact legacy unit string ('ft^3/s').
        List<UsSeriesReading> series = StationProcessorUS.buildReadings(
                List.of(obs("00060", "2026-10-11T18:00:00+00:00", "12.5")), MOUNTAIN);

        assertEquals(List.of(new UsSeriesReading("Streamflow", "ft^3/s",
                "<root><a d=\"2026-10-11\" v=\"12.5\" /></root>")), series);
    }

    @Test
    void buildReadingsDatesByTheStationsLocalDay() {
        // 03:00 UTC on Oct 11 is still Oct 10 in New Mexico (MDT, UTC-6). Dating it by UTC would write a
        // reading into tomorrow's row.
        List<UsSeriesReading> series = StationProcessorUS.buildReadings(
                List.of(obs("00065", "2026-10-11T03:00:00+00:00", "3.34")), MOUNTAIN);

        assertEquals("<root><a d=\"2026-10-10\" v=\"3.34\" /></root>", series.get(0).xmlDoc());
    }

    @Test
    void buildReadingsDropsUnmappedNonInstantaneousAndNonNumeric() {
        List<UsSeriesReading> series = StationProcessorUS.buildReadings(List.of(
                obs("99999", "2026-10-11T18:00:00+00:00", "410"),          // not a legacy parameter
                obs("00060", "2026-10-11T18:00:00+00:00", "12", "00003"),  // daily mean, not instantaneous
                obs("00065", "2026-10-11T18:00:00+00:00", "Ice"),
                obs("00010", "2026-10-11T18:00:00+00:00", "17.2", null)),  // no statistic: kept
                MOUNTAIN);

        assertEquals(1, series.size());
        assertEquals("Temperature", series.get(0).name());
        assertEquals("water, &#176;C", series.get(0).unit());
    }

    @Test
    void resolveTimeZoneHonoursTheDaylightSavingFlag() {
        Instant july = Instant.parse("2026-07-01T12:00:00Z");

        assertEquals(ZoneOffset.ofHours(-6), UsgsWaterDataClient.resolveTimeZone("MST", "Y").getRules().getOffset(july));
        assertEquals(ZoneOffset.ofHours(-7), UsgsWaterDataClient.resolveTimeZone("MST", "N").getRules().getOffset(july));
        assertEquals(ZoneOffset.ofHours(-10), UsgsWaterDataClient.resolveTimeZone("HST", "N").getRules().getOffset(july));
        assertEquals(ZoneOffset.UTC, UsgsWaterDataClient.resolveTimeZone(null, null));
    }

    @Test
    void stationMissingFromTheSnapshotIsSkipped() throws Exception {
        UsgsWaterDataClient client = mock(UsgsWaterDataClient.class);
        WaterDataRepository repo = mock(WaterDataRepository.class);
        when(client.fetchLatest(null)).thenReturn(Map.of(
                "08313000", List.of(obs("00060", "2026-10-11T18:00:00+00:00", "12.5"))));
        when(client.timeZoneFor("08313000")).thenReturn(MOUNTAIN);
        StationProcessorUS processor = new StationProcessorUS(client, repo);

        processor.prepareCycle(List.of("08313000", "05112000"), null);

        assertEquals(ProcessingOutcome.PROCESSED, processor.processWithOutcome("08313000", "NM", 0));
        assertEquals(ProcessingOutcome.SKIPPED, processor.processWithOutcome("05112000", "MN", 0));
        verify(client).ensureTimeZones(List.of("08313000"));
        verify(repo).saveUsStationData(eq("08313000"), eq("NM"), any());
        verify(repo, never()).saveUsStationData(eq("05112000"), any(), any());
    }

    @Test
    void stationBeforeAnySnapshotIsSkipped() {
        StationProcessorUS processor = new StationProcessorUS(mock(UsgsWaterDataClient.class), mock(WaterDataRepository.class));

        assertEquals(ProcessingOutcome.SKIPPED, processor.processWithOutcome("08313000", "NM", 0));
    }
}
