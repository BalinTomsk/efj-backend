package com.fishfind.weather.service;

import com.fishfind.weather.repo.WeatherDataRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class StationPostProcessingServiceTest {

    @Mock
    private WeatherDataRepository weatherDataRepository;

    @InjectMocks
    private StationPostProcessingService service;

    @Test
    void recordsTheCycleInJobRunThenRunsTheRetention() {
        Instant started = Instant.parse("2026-11-25T08:00:00Z");

        service.runAfterStationProcessing("Open-Meteo", "CA", started, 1150, 0);

        InOrder inOrder = Mockito.inOrder(weatherDataRepository);
        inOrder.verify(weatherDataRepository).recordCycle(eq("open-meteo-ca"),
                eq(LocalDateTime.ofInstant(started, ZoneOffset.UTC)), any(), eq("ok"), eq(1150), isNull());
        inOrder.verify(weatherDataRepository).cleanOldWeatherData();
        inOrder.verifyNoMoreInteractions();
    }

    @Test
    void aCycleWithFailuresIsPartial() {
        service.runAfterStationProcessing("Weather.gov", "US", Instant.now(), 880, 20);

        verify(weatherDataRepository).recordCycle(eq("weather.gov-us"), any(), any(), eq("partial"), eq(880),
                eq("failed=20"));
    }

    @Test
    void aCycleThatSavedNothingIsNotRecordedButStillCleansUp() {
        service.runAfterStationProcessing("Wunderground", "US", Instant.now(), 0, 0);

        verify(weatherDataRepository, never()).recordCycle(anyString(), any(), any(), anyString(), anyInt(), any());
        verify(weatherDataRepository).cleanOldWeatherData();
    }

    @Test
    void jobNameIsLowerCaseAndFitsTheColumn() {
        assertThat(StationPostProcessingService.jobName("Open", "CA")).isEqualTo("open-ca");
        assertThat(StationPostProcessingService.jobName("x".repeat(40), "US")).hasSize(32);
    }
}
