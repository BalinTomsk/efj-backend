package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.StationHttp503BackoffRepository;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class StationHttp503BackoffServiceTest {

    private static final StationRef STATION = new StationRef("06887500", 1.0, 2.0, "KS");

    @Mock
    private StationHttp503BackoffRepository repository;

    @InjectMocks
    private StationHttp503BackoffService service;

    @Test
    void refreshDueDelegatesToRepository() {
        LocalDate today = LocalDate.of(2026, 7, 17);

        service.refreshDue(today);

        verify(repository).refreshDue(today);
    }

    @Test
    void recordsHttp503WithStationState() {
        LocalDate today = LocalDate.of(2026, 7, 17);

        service.recordHttp503("weather-gov", "US", STATION, today);

        verify(repository).recordHttp503("weather-gov", "US", "06887500", "KS", today);
    }

    @Test
    void successfulProcessingResetsBackoff() {
        service.recordProcessed("weather-gov", "US", STATION);

        verify(repository).reset("weather-gov", "US", "06887500");
    }

    @Test
    void summaryByStateDelegatesToRepository() {
        List<StationHttp503BackoffRepository.BackoffSummary> expected = List.of(
                new StationHttp503BackoffRepository.BackoffSummary("KS", "WEEKLY", 3));
        when(repository.summaryByState()).thenReturn(expected);

        assertThat(service.summaryByState()).isEqualTo(expected);
    }
}
