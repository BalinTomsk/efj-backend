package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.weather.canonical.WeatherGovConverter;
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
class StationProcessorWeatherGovTest {

    private static final Instant NOW = Instant.parse("2026-08-13T04:12:00Z");

    private final StationRef station = new StationRef("KNYC", 40.77, -73.98, "NY");
    private final ObjectMapper mapper = new ObjectMapper().findAndRegisterModules();

    @Mock
    private WeatherGovFetcher fetcher;

    @Mock
    private WeatherGovStationResolver resolver;

    @Mock
    private WeatherDataRepository weatherDataRepository;

    @Captor
    private ArgumentCaptor<String> payload;

    private StationProcessorWeatherGov processor() {
        return new StationProcessorWeatherGov(
                fetcher, resolver, weatherDataRepository,
                new WeatherGovConverter(mapper, Clock.fixed(NOW, ZoneOffset.UTC)),
                mapper);
    }

    private static String gridpointForecast() {
        return "{\"properties\":{\"units\":\"si\",\"periods\":[{\"number\":1,\"name\":\"Today\","
                + "\"startTime\":\"2026-08-13T06:00:00-06:00\",\"isDaytime\":true,\"temperature\":29,"
                + "\"probabilityOfPrecipitation\":{\"value\":20},\"relativeHumidity\":{\"value\":41},"
                + "\"windSpeed\":\"10 to 15 km/h\",\"windDirection\":\"SSW\","
                + "\"icon\":\"https://api.weather.gov/icons/land/day/sct?size=medium\","
                + "\"shortForecast\":\"Mostly Sunny\",\"detailedForecast\":\"Mostly sunny.\"}]}}";
    }

    @Test
    void persistsCanonicalEnvelopeFromTheGridpointForecast() throws Exception {
        when(fetcher.fetchGridpointForecast(40.77, -73.98)).thenReturn(gridpointForecast());

        assertThat(processor().process(station)).isEqualTo(ProcessingOutcome.PROCESSED);

        verify(weatherDataRepository)
                .saveStationData(eq("KNYC"), payload.capture(), eq(WeatherSourceType.WEATHER_GOV));

        var stored = mapper.readTree(payload.getValue());
        assertThat(stored.path("schema").asText()).isEqualTo("fishfind.weather.forecast/v1");
        assertThat(stored.path("provider").asText()).isEqualTo("weather-gov");
        assertThat(stored.path("days")).hasSize(1);
        assertThat(stored.path("days").get(0).path("tempHighC").asDouble()).isEqualTo(29.0);
        assertThat(stored.path("raw").path("properties").path("units").asText()).isEqualTo("si");
    }

    @Test
    void doesNotResolveAnObservationStationAnyMore() throws Exception {
        // A forecast is keyed by GRID CELL, not by observation station, so the nearest-station lookup
        // (and its dbo.weather_gov_station cache) is no longer on this path at all.
        when(fetcher.fetchGridpointForecast(40.77, -73.98)).thenReturn(gridpointForecast());

        assertThat(processor().process(station)).isEqualTo(ProcessingOutcome.PROCESSED);

        verifyNoInteractions(resolver);
    }

    @Test
    void skipsWhenTheCoordinateIsOutsideNwsCoverage() throws Exception {
        // fetchGridpointForecast returns null rather than throwing for "no coverage here".
        when(fetcher.fetchGridpointForecast(anyDouble(), anyDouble())).thenReturn(null);

        assertThat(processor().process(station)).isEqualTo(ProcessingOutcome.SKIPPED);

        verify(weatherDataRepository, never()).saveStationData(anyString(), anyString(), anyInt());
    }

    @Test
    void failsTheStationWhenTheDocumentIsNotAForecast() throws Exception {
        // What this provider used to store: an observation. It now fails loudly instead of being
        // written and silently ignored by the database.
        when(fetcher.fetchGridpointForecast(40.77, -73.98))
                .thenReturn("{\"properties\":{\"temperature\":{\"value\":21.1}}}");

        assertThat(processor().process(station)).isEqualTo(ProcessingOutcome.FAILED);

        verify(weatherDataRepository, never()).saveStationData(anyString(), anyString(), anyInt());
    }

    @Test
    void skipsPersistWhenFeedNotPublished() throws Exception {
        when(fetcher.fetchGridpointForecast(40.77, -73.98)).thenThrow(new FileNotFoundException("no feed"));

        assertThat(processor().process(station)).isEqualTo(ProcessingOutcome.SKIPPED);

        verify(weatherDataRepository, never()).saveStationData(anyString(), anyString(), anyInt());
    }

    @Test
    void swallowsFetchIoErrorWithoutPersisting() throws Exception {
        when(fetcher.fetchGridpointForecast(40.77, -73.98)).thenThrow(new IOException("HTTP 500"));

        assertThat(processor().process(station)).isEqualTo(ProcessingOutcome.FAILED);

        verify(weatherDataRepository, never()).saveStationData(anyString(), anyString(), anyInt());
    }

    @Test
    void exposesCountryAndMissingSourceMetadata() {
        StationProcessorWeatherGov processor = processor();
        assertThat(processor.country()).isEqualTo("US");
        assertThat(processor.missingSourceDescription()).isNotBlank();
        assertThat(processor.logger()).isNotNull();
    }
}
