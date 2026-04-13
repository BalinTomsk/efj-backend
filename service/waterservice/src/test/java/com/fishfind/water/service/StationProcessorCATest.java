package com.fishfind.water.service;

import com.fishfind.water.domain.Reading;
import com.fishfind.water.repo.WaterDataRepository;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class StationProcessorCATest {

    private final CsvFetcherCA fetcher = mock(CsvFetcherCA.class);
    private final WaterDataRepository dataRepo = mock(WaterDataRepository.class);
    private final StationProcessorCA processor = new StationProcessorCA(fetcher, dataRepo);

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
        assertNull(failureStates().get("02JE025"));
    }

    @Test
    void processRetainsFailureStateAfterThreeConsecutiveFailedDays() throws Exception {
        doThrow(new RuntimeException("fetch failed")).when(fetcher).fetch("QC", "02JE025");
        Map<String, Object> states = failureStates();

        processor.process("02JE025", "QC", -5);
        states.put("02JE025", newFailureState(LocalDate.now().minusDays(1), 2));
        processor.process("02JE025", "QC", -5);

        assertEquals(3, failureCount(states.get("02JE025")));
    }

    @Test
    void processDoesNotTrackFailureStateWhenSourceCsvIsMissing() throws Exception {
        doThrow(new java.io.FileNotFoundException("HTTP error 404")).when(fetcher).fetch("MB", "05MD011");

        processor.process("05MD011", "MB", -6);

        assertFalse(failureStates().containsKey("05MD011"));
    }

    @Test
    void incrementFailureCountDoesNotIncreaseTwiceOnSameDay() throws Exception {
        Map<String, Object> states = failureStates();
        states.put("02JE025", newFailureState(LocalDate.now(), 2));

        int failures = (int) invokePrivate("incrementFailureCount", new Class<?>[]{String.class}, "02JE025");

        assertEquals(2, failures);
    }

    @Test
    void incrementFailureCountIncreasesForConsecutiveDay() throws Exception {
        Map<String, Object> states = failureStates();
        states.put("02JE025", newFailureState(LocalDate.now().minusDays(1), 2));

        int failures = (int) invokePrivate("incrementFailureCount", new Class<?>[]{String.class}, "02JE025");

        assertEquals(3, failures);
    }

    @Test
    void incrementFailureCountResetsWhenDayGapExists() throws Exception {
        Map<String, Object> states = failureStates();
        states.put("02JE025", newFailureState(LocalDate.now().minusDays(2), 7));

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
        Field field = StationProcessorBase.class.getDeclaredField("failureStates");
        field.setAccessible(true);
        return (Map<String, Object>) field.get(processor);
    }

    private Object invokePrivate(String name, Class<?>[] parameterTypes, Object... args) throws Exception {
        Class<?> owner = "incrementFailureCount".equals(name) ? StationProcessorBase.class : StationProcessorCA.class;
        Method method = owner.getDeclaredMethod(name, parameterTypes);
        method.setAccessible(true);
        return method.invoke(processor, args);
    }

    private Object newFailureState(LocalDate day, int count) throws Exception {
        Class<?> type = Class.forName("com.fishfind.water.service.StationProcessorBase$FailureState");
        var constructor = type.getDeclaredConstructor(LocalDate.class, int.class);
        constructor.setAccessible(true);
        return constructor.newInstance(day, count);
    }

    private int failureCount(Object failureState) throws Exception {
        Method method = failureState.getClass().getDeclaredMethod("count");
        method.setAccessible(true);
        return (int) method.invoke(failureState);
    }
}
