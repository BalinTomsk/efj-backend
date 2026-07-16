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
class StationProcessorGoogleWeatherTest {

    private final StationRef station = new StationRef("KNYC", 40.77, -73.98, "NY");

    @Mock
    private GoogleWeatherFetcher fetcher;

    @Mock
    private WeatherDataRepository weatherDataRepository;

    @InjectMocks
    private StationProcessorGoogleWeather processor;

    @Test
    void fetchesAndPersistsOnSuccess() throws Exception {
        when(fetcher.fetchCurrent(40.77, -73.98)).thenReturn("{\"temperature\":{}}");

        assertThat(processor.process(station)).isEqualTo(ProcessingOutcome.PROCESSED);

        verify(weatherDataRepository).saveStationData("KNYC", "{\"temperature\":{}}");
    }

    @Test
    void skipsPersistWhenFeedNotPublished() throws Exception {
        when(fetcher.fetchCurrent(40.77, -73.98)).thenThrow(new FileNotFoundException("no feed"));

        assertThat(processor.process(station)).isEqualTo(ProcessingOutcome.SKIPPED);

        verify(weatherDataRepository, never()).saveStationData(anyString(), anyString());
    }

    @Test
    void swallowsFetchIoErrorWithoutPersisting() throws Exception {
        when(fetcher.fetchCurrent(40.77, -73.98)).thenThrow(new IOException("HTTP 500"));

        assertThat(processor.process(station)).isEqualTo(ProcessingOutcome.FAILED);

        verify(weatherDataRepository, never()).saveStationData(anyString(), anyString());
    }

    @Test
    void exposesCountryAndMissingSourceMetadata() {
        assertThat(processor.country()).isEqualTo("US");
        assertThat(processor.missingSourceDescription()).isEqualTo("Google Weather source");
        assertThat(processor.logger()).isNotNull();
    }
}
