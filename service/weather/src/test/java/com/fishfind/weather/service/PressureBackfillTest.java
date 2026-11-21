package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.weather.canonical.CanonicalForecast;
import com.fishfind.weather.canonical.ForecastDay;
import com.fishfind.weather.canonical.PressureFill;
import com.fishfind.weather.canonical.WeatherGovConverter;
import com.fishfind.weather.canonical.WeatherSourceType;
import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.WeatherDataRepository;
import java.io.IOException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Captor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * Open-Meteo pressure for providers whose forecast has none (Weather.gov): the pure day mapping, and that
 * the backfill is best-effort -- off, out of budget or failing, the station is still saved.
 */
@ExtendWith(MockitoExtension.class)
class PressureBackfillTest {

    private static final Instant NOW = Instant.parse("2026-08-13T04:12:00Z");
    private static final LocalDate D13 = LocalDate.of(2026, 8, 13);
    private static final LocalDate D14 = LocalDate.of(2026, 8, 14);
    private static final String PRESSURE_DOCUMENT =
            "{\"hourly\":{\"time\":[\"2026-08-13T22:00\",\"2026-08-13T23:00\",\"2026-08-14T00:00\","
                    + "\"2026-08-14T23:00\"],\"pressure_msl\":[1004.6,1003.5,1001.0,null]}}";

    private final StationRef station = new StationRef("KNYC", 40.77, -73.98, "NY");
    private final ObjectMapper mapper = new ObjectMapper().findAndRegisterModules();

    @Mock
    private OpenMeteoFetcher openMeteo;

    @Mock
    private WeatherApiUsageTracker usage;

    @Mock
    private WeatherGovFetcher weatherGov;

    @Mock
    private WeatherGovStationResolver resolver;

    @Mock
    private WeatherDataRepository repository;

    @Captor
    private ArgumentCaptor<String> payload;

    @Test
    void dailyPressureTakesTheLastHourOfEachDayRounded() throws IOException {
        Map<LocalDate, Integer> byDay = PressureFill.dailyPressure(PRESSURE_DOCUMENT);

        // 13th: 23:00 = 1003.5 -> 1004 (half away from zero); 14th: 23:00 is null, so 00:00 = 1001
        assertThat(byDay).containsEntry(D13, 1004).containsEntry(D14, 1001);
    }

    @Test
    void fillKeepsExistingPressureAndFillsOnlyMissingDays() throws IOException {
        CanonicalForecast forecast = forecast(day(D13, 1010), day(D14, null), day(D14.plusDays(1), null));

        CanonicalForecast filled = PressureFill.fill(forecast, PressureFill.dailyPressure(PRESSURE_DOCUMENT));

        assertThat(filled.days()).extracting(ForecastDay::pressureHpa).containsExactly(1010, 1001, null);
    }

    @Test
    void weatherGovSavesOpenMeteoPressureInTheEnvelope() throws Exception {
        when(weatherGov.fetchGridpointForecast(40.77, -73.98)).thenReturn(gridpointForecast());
        when(usage.tryConsume(eq(PressureBackfill.USAGE_KEY), any(), eq(1000))).thenReturn(true);
        when(openMeteo.fetchPressure(40.77, -73.98)).thenReturn(PRESSURE_DOCUMENT);

        assertThat(processor(backfill(true, 1000)).process(station)).isEqualTo(ProcessingOutcome.PROCESSED);

        verify(repository).saveStationData(eq("KNYC"), payload.capture(), eq(WeatherSourceType.WEATHER_GOV));
        assertThat(mapper.readTree(payload.getValue()).path("days").get(0).path("pressureHpa").asInt())
                .isEqualTo(1004);
    }

    @Test
    void weatherGovStillSavesWhenOpenMeteoFails() throws Exception {
        when(weatherGov.fetchGridpointForecast(40.77, -73.98)).thenReturn(gridpointForecast());
        when(usage.tryConsume(eq(PressureBackfill.USAGE_KEY), any(), anyInt())).thenReturn(true);
        when(openMeteo.fetchPressure(anyDouble(), anyDouble())).thenThrow(new IOException("HTTP 500"));

        assertThat(processor(backfill(true, 1000)).process(station)).isEqualTo(ProcessingOutcome.PROCESSED);

        verify(repository).saveStationData(eq("KNYC"), payload.capture(), eq(WeatherSourceType.WEATHER_GOV));
        assertThat(mapper.readTree(payload.getValue()).path("days").get(0).has("pressureHpa")).isFalse();
    }

    @Test
    void makesNoCallWhenDisabledOrOutOfBudget() throws Exception {
        CanonicalForecast forecast = forecast(day(D13, null));
        when(usage.tryConsume(eq(PressureBackfill.USAGE_KEY), any(), eq(0))).thenReturn(false);

        assertThat(backfill(false, 1000).fill(forecast, station)).isSameAs(forecast);
        assertThat(backfill(true, 0).fill(forecast, station)).isSameAs(forecast);

        verifyNoInteractions(openMeteo);
    }

    // --- helpers -------------------------------------------------------------------------------------

    private PressureBackfill backfill(boolean enabled, int dailyLimit) {
        return new PressureBackfill(openMeteo, usage, enabled, dailyLimit);
    }

    private StationProcessorWeatherGov processor(PressureBackfill backfill) {
        return new StationProcessorWeatherGov(weatherGov, resolver, repository,
                new WeatherGovConverter(mapper, Clock.fixed(NOW, ZoneOffset.UTC)), mapper, backfill);
    }

    private static CanonicalForecast forecast(ForecastDay... days) {
        return new CanonicalForecast("weather-gov", WeatherSourceType.WEATHER_GOV, "KNYC", NOW, List.of(days), null);
    }

    private static ForecastDay day(LocalDate date, Integer hpa) {
        return new ForecastDay(date, ForecastDay.DAILY_SUMMARY_TIME, null, null, null, null, null, null, null,
                null, hpa, null, null, null, null, null, null, null, null);
    }

    private static String gridpointForecast() {
        return "{\"properties\":{\"units\":\"si\",\"periods\":[{\"number\":1,\"name\":\"Today\","
                + "\"startTime\":\"2026-08-13T06:00:00-06:00\",\"isDaytime\":true,\"temperature\":29,"
                + "\"probabilityOfPrecipitation\":{\"value\":20},\"relativeHumidity\":{\"value\":41},"
                + "\"windSpeed\":\"10 to 15 km/h\",\"windDirection\":\"SSW\","
                + "\"icon\":\"https://api.weather.gov/icons/land/day/sct?size=medium\","
                + "\"shortForecast\":\"Mostly Sunny\",\"detailedForecast\":\"Mostly sunny.\"}]}}";
    }
}
