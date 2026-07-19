package com.fishfind.water.service;

import com.fishfind.water.domain.StationRef;
import com.fishfind.water.repo.StationHttp503BackoffRepository;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class StationHttp503BackoffServiceTest {

    private static final StationRef STATION = new StationRef("02JE025", "QC", -5);

    private final StationHttp503BackoffRepository repository = mock(StationHttp503BackoffRepository.class);
    private final StationHttp503BackoffService service = new StationHttp503BackoffService(repository);

    @Test
    void refreshDueDelegatesToRepository() {
        LocalDate today = LocalDate.of(2026, 7, 18);

        service.refreshDue(today);

        verify(repository).refreshDue(today);
    }

    @Test
    void recordsHttp503WithStationState() {
        LocalDate today = LocalDate.of(2026, 7, 18);

        service.recordHttp503("environment-canada", "CA", STATION, today);

        verify(repository).recordHttp503("environment-canada", "CA", "02JE025", "QC", today);
    }

    @Test
    void successfulProcessingResetsBackoff() {
        service.recordProcessed("environment-canada", "CA", STATION);

        verify(repository).reset("environment-canada", "CA", "02JE025");
    }

    @Test
    void summaryByStateDelegatesToRepository() {
        List<StationHttp503BackoffRepository.BackoffSummary> expected = List.of(
                new StationHttp503BackoffRepository.BackoffSummary("QC", "WEEKLY", 3));
        when(repository.summaryByState()).thenReturn(expected);

        assertEquals(expected, service.summaryByState());
    }
}
