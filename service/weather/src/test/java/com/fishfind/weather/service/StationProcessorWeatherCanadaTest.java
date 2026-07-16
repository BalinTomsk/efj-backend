package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.WeatherDataRepository;
import java.io.FileNotFoundException;
import java.io.IOException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class StationProcessorWeatherCanadaTest {

    private final StationRef station = new StationRef("CA-1", 43.6532, -79.3832, "ON");

    @Mock
    private WeatherCanadaFetcher fetcher;

    @Mock
    private WeatherDataRepository weatherDataRepository;

    @InjectMocks
    private StationProcessorWeatherCanada processor;

    @Test
    void fetchesAndPersistsOnSuccess() throws Exception {
        when(fetcher.fetchLatestObservation(43.6532, -79.3832)).thenReturn("{\"features\":[{}]}");

        assertThat(processor.process(station)).isEqualTo(ProcessingOutcome.PROCESSED);

        verify(weatherDataRepository).saveStationData("CA-1", "{\"features\":[{}]}");
    }

    @Test
    void skipsPersistWhenNoObservationIsPublished() throws Exception {
        when(fetcher.fetchLatestObservation(43.6532, -79.3832)).thenThrow(new FileNotFoundException("no feed"));

        assertThat(processor.process(station)).isEqualTo(ProcessingOutcome.SKIPPED);

        verify(weatherDataRepository, never()).saveStationData(anyString(), anyString());
    }

    @Test
    void swallowsFetchIoErrorWithoutPersisting() throws Exception {
        when(fetcher.fetchLatestObservation(43.6532, -79.3832)).thenThrow(new IOException("HTTP 500"));

        assertThat(processor.process(station)).isEqualTo(ProcessingOutcome.FAILED);

        verify(weatherDataRepository, never()).saveStationData(anyString(), anyString());
    }

    @Test
    void exposesCountryAndMissingSourceMetadata() {
        assertThat(processor.country()).isEqualTo("CA");
        assertThat(processor.missingSourceDescription()).isEqualTo("Weather Canada source");
        assertThat(processor.logger()).isNotNull();
    }
}
