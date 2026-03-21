package com.fishfind.water.service;

import com.fishfind.water.domain.Reading;
import com.fishfind.water.repo.WaterDataRepository;
import com.fishfind.water.repo.WaterStationRepository;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class StationProcessorTest {

    private final CsvFetcher fetcher = mock(CsvFetcher.class);
    private final WaterDataRepository dataRepo = mock(WaterDataRepository.class);
    private final WaterStationRepository stationRepo = mock(WaterStationRepository.class);
    private final StationProcessor processor = new StationProcessor(fetcher, dataRepo, stationRepo);

    @Test
    void processFetchesParsesAndSavesReadingsOnSuccess() throws Exception {
        when(fetcher.fetch("QC", "02JE025")).thenReturn(List.of(
                new String[]{"station", "stamp", "level", "x", "y", "z", "discharge"},
                new String[]{"02JE025", "2024-01-02T03:04:05Z", "1.2", "", "", "", "3.4"}
        ));

        processor.process("02JE025", "QC", -5);

        verify(dataRepo).saveStationData("02JE025", List.of(
                new Reading("02JE025", java.time.OffsetDateTime.parse("2024-01-02T03:04:05Z"), 1.2, 3.4)
        ));
        verify(stationRepo, never()).disableStation("02JE025");
        assertNull(failureStates().get("02JE025"));
    }

    @Test
    void processDisablesStationAfterThreeFailuresInOneDay() throws Exception {
        doThrow(new RuntimeException("fetch failed")).when(fetcher).fetch("QC", "02JE025");

        processor.process("02JE025", "QC", -5);
        processor.process("02JE025", "QC", -5);
        processor.process("02JE025", "QC", -5);

        verify(stationRepo, times(1)).disableStation("02JE025");
        assertNull(failureStates().get("02JE025"));
    }

    @Test
    void incrementFailureCountResetsWhenDayChanges() throws Exception {
        Map<String, Object> states = failureStates();
        states.put("02JE025", newFailureState(LocalDate.now().minusDays(1), 7));

        int failures = (int) invokePrivate("incrementFailureCount", new Class<?>[]{String.class}, "02JE025");

        assertEquals(1, failures);
    }

    @Test
    void parseSkipsHeaderAndMalformedRows() throws Exception {
        @SuppressWarnings("unchecked")
        List<Reading> readings = (List<Reading>) invokePrivate("parse", new Class<?>[]{List.class}, List.of(
                new String[]{"station", "stamp", "level", "a", "b", "c", "discharge"},
                new String[]{"bad"},
                new String[]{"02JE025", "2024-01-02T03:04:05Z", "1.2", "", "", "", "3.4"},
                new String[]{"", "2024-01-02T03:04:05Z", "1.2", "", "", "", "3.4"}
        ));

        assertEquals(List.of(new Reading("02JE025", java.time.OffsetDateTime.parse("2024-01-02T03:04:05Z"), 1.2, 3.4)), readings);
    }

    @Test
    void trimReturnsTrimmedValueOrNull() throws Exception {
        assertEquals("x", invokePrivate("trim", new Class<?>[]{String.class}, " x "));
        assertNull(invokePrivate("trim", new Class<?>[]{String.class}, new Object[]{null}));
    }

    @Test
    void parseDoubleHandlesBlankAndNumericValues() throws Exception {
        assertNull(invokePrivate("parseDouble", new Class<?>[]{String.class}, " "));
        assertEquals(1.25, invokePrivate("parseDouble", new Class<?>[]{String.class}, "1.25"));
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> failureStates() throws Exception {
        Field field = StationProcessor.class.getDeclaredField("failureStates");
        field.setAccessible(true);
        return (Map<String, Object>) field.get(processor);
    }

    private Object invokePrivate(String name, Class<?>[] parameterTypes, Object... args) throws Exception {
        Method method = StationProcessor.class.getDeclaredMethod(name, parameterTypes);
        method.setAccessible(true);
        return method.invoke(processor, args);
    }

    private Object newFailureState(LocalDate day, int count) throws Exception {
        Class<?> type = Class.forName("com.fishfind.water.service.StationProcessor$FailureState");
        var constructor = type.getDeclaredConstructor(LocalDate.class, int.class);
        constructor.setAccessible(true);
        return constructor.newInstance(day, count);
    }
}
