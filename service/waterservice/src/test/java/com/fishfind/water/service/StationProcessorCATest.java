package com.fishfind.water.service;

import com.fishfind.water.domain.Reading;
import com.fishfind.water.repo.WaterDataRepository;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Method;
import java.time.OffsetDateTime;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class StationProcessorCATest {

    private final CsvFetcherCA fetcher = mock(CsvFetcherCA.class);
    private final WaterDataRepository dataRepo = mock(WaterDataRepository.class);
    private final SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();
    private final StationProcessorCA processor = new StationProcessorCA(fetcher, dataRepo, meterRegistry);

    @Test
    void processFetchesParsesAndSavesReadingsOnSuccess() throws Exception {
        when(fetcher.fetch("QC", "02JE025")).thenReturn(
                "station,stamp,level,x,y,z,discharge\n02JE025,2024-01-02T03:04:05Z,1.2,,,,3.4\n");

        processor.process("02JE025", "QC", -5);

        verify(dataRepo).saveStationData("02JE025", List.of(
                new Reading("02JE025", OffsetDateTime.parse("2024-01-02T03:04:05Z"), 1.2, 3.4)
        ));
    }

    @Test
    void processDoesNotThrowWhenStationFetchFails() throws Exception {
        doThrow(new RuntimeException("fetch failed")).when(fetcher).fetch("QC", "02JE025");
        processor.process("02JE025", "QC", -5);
    }

    @Test
    void processDoesNotThrowWhenSourceCsvIsMissing() throws Exception {
        doThrow(new java.io.FileNotFoundException("HTTP error 404")).when(fetcher).fetch("MB", "05MD011");

        processor.process("05MD011", "MB", -6);
    }

    @Test
    void parseSkipsHeaderShortRowsBlankKeysAndUnparseableRowsAndCountsThem() throws Exception {
        String csv = String.join("\n",
                "station,stamp,level,a,b,c,discharge",   // header
                "bad",                                      // too few columns
                "02JE025,2024-01-02T03:04:05Z,1.2,,,,3.4",  // good
                ",2024-01-02T03:04:05Z,1.2,,,,3.4",         // blank station id
                "02JE025,not-a-timestamp,1.2,,,,3.4");      // unparseable timestamp

        @SuppressWarnings("unchecked")
        List<Reading> readings = (List<Reading>) invokePrivate("parse",
                new Class<?>[]{String.class, String.class}, csv, "02JE025");

        assertEquals(List.of(
                new Reading("02JE025", OffsetDateTime.parse("2024-01-02T03:04:05Z"), 1.2, 3.4)
        ), readings);
        // 3 bad rows skipped (short, blank-key, unparseable) recorded on the metric.
        assertEquals(3.0, meterRegistry.counter("water.csv.rows.skipped", "country", "CA").count());
    }

    @Test
    void parseReturnsEmptyForBlankBody() throws Exception {
        @SuppressWarnings("unchecked")
        List<Reading> readings = (List<Reading>) invokePrivate("parse",
                new Class<?>[]{String.class, String.class}, "   ", "02JE025");

        assertEquals(List.of(), readings);
    }

    @Test
    void parseDoubleHandlesBlankAndNumericValues() throws Exception {
        assertNull(invokePrivate("parseDouble", new Class<?>[]{String.class}, " "));
        assertEquals(1.25, invokePrivate("parseDouble", new Class<?>[]{String.class}, "1.25"));
    }

    private Object invokePrivate(String name, Class<?>[] parameterTypes, Object... args) throws Exception {
        Method method = StationProcessorCA.class.getDeclaredMethod(name, parameterTypes);
        method.setAccessible(true);
        return method.invoke(processor, args);
    }
}
