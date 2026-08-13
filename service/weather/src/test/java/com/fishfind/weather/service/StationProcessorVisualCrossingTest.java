package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.weather.canonical.VisualCrossingConverter;
import com.fishfind.weather.canonical.WeatherSourceType;
import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.WeatherDataRepository;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Captor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class StationProcessorVisualCrossingTest {

    private static final Instant NOW = Instant.parse("2026-08-13T04:12:00Z");

    private final StationRef station = new StationRef("KNYC", 40.77, -73.98, "NY");
    private final ObjectMapper mapper = new ObjectMapper().findAndRegisterModules();

    @Mock
    private VisualCrossingFetcher fetcher;

    @Mock
    private WeatherDataRepository weatherDataRepository;

    @Captor
    private ArgumentCaptor<String> payload;

    // a real converter, so the test asserts what actually reaches the database
    private StationProcessorVisualCrossing processor() {
        return new StationProcessorVisualCrossing(
                fetcher, weatherDataRepository,
                new VisualCrossingConverter(mapper, Clock.fixed(NOW, ZoneOffset.UTC)),
                mapper);
    }

    private static String forecastPayload() {
        return "{\"queryCost\":1,\"timezone\":\"America/New_York\",\"days\":[{"
                + "\"datetime\":\"2026-08-13\",\"tempmax\":85.0,\"tempmin\":62.0,\"temp\":74.1,"
                + "\"humidity\":39.7,\"precip\":0.0,\"precipprob\":6.0,\"windspeed\":12.8,"
                + "\"winddir\":201.2,\"pressure\":1009.7,\"conditions\":\"Partially cloudy\","
                + "\"description\":\"Partly cloudy throughout the day.\",\"icon\":\"partly-cloudy-day\"}]}";
    }

    @Test
    void persistsCanonicalEnvelopeStampedWithItsProvider() throws Exception {
        when(fetcher.fetchCurrent(40.77, -73.98)).thenReturn(forecastPayload());

        assertThat(processor().process(station)).isEqualTo(ProcessingOutcome.PROCESSED);

        verify(weatherDataRepository)
                .saveStationData(eq("KNYC"), payload.capture(), eq(WeatherSourceType.VISUAL_CROSSING));

        var stored = mapper.readTree(payload.getValue());
        assertThat(stored.path("schema").asText()).isEqualTo("fishfind.weather.forecast/v1");
        assertThat(stored.path("provider").asText()).isEqualTo("visual-crossing");
        assertThat(stored.path("mli").asText()).isEqualTo("KNYC");
        assertThat(stored.path("days")).hasSize(1);
        // metric on the way out, US units on the way in
        assertThat(stored.path("days").get(0).path("tempHighC").asDouble()).isCloseTo(29.44, within());
        // and the provider's own document is still in there, so the payload stays replayable
        assertThat(stored.path("raw").path("timezone").asText()).isEqualTo("America/New_York");
    }

    private static org.assertj.core.data.Offset<Double> within() {
        return org.assertj.core.data.Offset.offset(0.01);
    }

    @Test
    void failsTheStationWhenTheProviderChangesShape() throws Exception {
        // the old T-SQL parser wrote nothing and reported success for this; now it is a counted failure
        when(fetcher.fetchCurrent(40.77, -73.98)).thenReturn("{\"observations\":[{\"stationID\":\"KX\"}]}");

        assertThat(processor().process(station)).isEqualTo(ProcessingOutcome.FAILED);

        verify(weatherDataRepository, never()).saveStationData(anyString(), anyString(), anyInt());
    }

    @Test
    void skipsPersistWhenFeedNotPublished() throws Exception {
        when(fetcher.fetchCurrent(40.77, -73.98)).thenThrow(new FileNotFoundException("no feed"));

        assertThat(processor().process(station)).isEqualTo(ProcessingOutcome.SKIPPED);

        verify(weatherDataRepository, never()).saveStationData(anyString(), anyString(), anyInt());
    }

    @Test
    void swallowsFetchIoErrorWithoutPersisting() throws Exception {
        when(fetcher.fetchCurrent(40.77, -73.98)).thenThrow(new IOException("HTTP 500"));

        assertThat(processor().process(station)).isEqualTo(ProcessingOutcome.FAILED);

        verify(weatherDataRepository, never()).saveStationData(anyString(), anyString(), anyInt());
    }

    @Test
    void exposesCountryAndMissingSourceMetadata() {
        StationProcessorVisualCrossing processor = processor();
        assertThat(processor.country()).isEqualTo("US");
        assertThat(processor.missingSourceDescription()).isEqualTo("Visual Crossing source");
        assertThat(processor.logger()).isNotNull();
    }
}
