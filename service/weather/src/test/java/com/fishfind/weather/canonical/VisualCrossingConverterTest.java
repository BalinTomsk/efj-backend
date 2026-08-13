package com.fishfind.weather.canonical;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;

/**
 * The expected numbers here are the ones prod produced for MLI 13068500 through the T-SQL branch, so a
 * divergence between the two paths fails the build rather than showing up as changed weather on a page.
 */
class VisualCrossingConverterTest {

    private static final Instant NOW = Instant.parse("2026-08-13T04:12:00Z");
    private final Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);
    private final VisualCrossingConverter converter = new VisualCrossingConverter(new ObjectMapper(), clock);

    private static String payload(String... days) {
        return "{\"queryCost\":1,\"latitude\":43.13,\"longitude\":-112.47,"
                + "\"timezone\":\"America/Boise\",\"days\":[" + String.join(",", days) + "]}";
    }

    private static String day(String date, String extra) {
        return "{\"datetime\":\"" + date + "\"," + extra + "}";
    }

    @Test
    void convertsUsUnitsToMetric() throws Exception {
        String raw = payload(day("2026-08-13",
                "\"tempmax\":85.0,\"tempmin\":62.0,\"temp\":74.1,\"humidity\":39.7,"
                        + "\"precip\":0.0,\"precipprob\":6.0,\"windspeed\":12.8,\"winddir\":201.2,"
                        + "\"pressure\":1009.7,\"conditions\":\"Partially cloudy\","
                        + "\"description\":\"Partly cloudy throughout the day.\",\"icon\":\"partly-cloudy-day\""));

        CanonicalForecast out = converter.convert(raw, "13068500");
        ForecastDay d = out.days().get(0);

        // 85F = 29.44C, 62F = 16.67C, 74.1F = 23.4C -> 23, 12.8mph = 20.6km/h
        assertThat(d.tempHighC()).isCloseTo(29.44, org.assertj.core.data.Offset.offset(0.01));
        assertThat(d.tempLowC()).isCloseTo(16.67, org.assertj.core.data.Offset.offset(0.01));
        assertThat(d.tempC()).isEqualTo(23);
        assertThat(d.windSpeedKmh()).isCloseTo(20.6, org.assertj.core.data.Offset.offset(0.05));
        assertThat(d.windDirection()).isEqualTo("S");
        assertThat(d.pressureHpa()).isEqualTo(1010);
        assertThat(d.precipChancePct()).isEqualTo(6);
        assertThat(d.humidityPct()).isEqualTo(39.7);
        assertThat(d.weatherCode()).isEqualTo(2);
        assertThat(d.icon()).isEqualTo("om_2.png");
        assertThat(d.conditionsShort()).isEqualTo("Partially cloudy");
        assertThat(d.time()).isEqualTo(ForecastDay.DAILY_SUMMARY_TIME);
    }

    @Test
    void convertsInchesToMillimetresAndSplitsRainEvenly() throws Exception {
        String raw = payload(day("2026-08-13",
                "\"tempmax\":72.1,\"tempmin\":58.9,\"temp\":65.1,\"precip\":0.5,"
                        + "\"precipprob\":75.0,\"windspeed\":9.2,\"winddir\":180.4,\"pressure\":1008.9,"
                        + "\"conditions\":\"Rain\",\"description\":\"Rain.\",\"icon\":\"rain\""));

        ForecastDay d = converter.convert(raw, "13068500").days().get(0);

        // 0.5in = 12.7mm -> 13, split evenly because a daily document has no hourly resolution
        assertThat(d.precipMm()).isEqualTo(13);
        assertThat(d.precipDayMm()).isCloseTo(6.35, org.assertj.core.data.Offset.offset(0.001));
        assertThat(d.precipNightMm()).isCloseTo(6.35, org.assertj.core.data.Offset.offset(0.001));
        assertThat(d.precipDayMm() + d.precipNightMm()).isCloseTo(12.7, org.assertj.core.data.Offset.offset(0.001));
        assertThat(d.weatherCode()).isEqualTo(63);
    }

    @Test
    void clipsToTodayThroughSixDaysAhead() throws Exception {
        String raw = payload(
                day("2026-08-12", "\"tempmax\":94.7,\"tempmin\":53.7,\"icon\":\"clear-day\""),   // yesterday
                day("2026-08-13", "\"tempmax\":85.0,\"tempmin\":62.0,\"icon\":\"clear-day\""),
                day("2026-08-19", "\"tempmax\":81.6,\"tempmin\":53.1,\"icon\":\"clear-day\""),   // today+6
                day("2026-08-20", "\"tempmax\":76.7,\"tempmin\":49.5,\"icon\":\"clear-day\""));  // beyond

        CanonicalForecast out = converter.convert(raw, "13068500");

        assertThat(out.days()).hasSize(2);
        assertThat(out.days()).extracting(ForecastDay::date)
                .containsExactly(LocalDate.parse("2026-08-13"), LocalDate.parse("2026-08-19"));
    }

    @Test
    void embedsTheProviderDocumentAndStampsProvenance() throws Exception {
        String raw = payload(day("2026-08-13", "\"tempmax\":85.0,\"tempmin\":62.0,\"icon\":\"clear-day\""));

        CanonicalForecast out = converter.convert(raw, "13068500");

        assertThat(out.schema()).isEqualTo("fishfind.weather.forecast/v1");
        assertThat(out.provider()).isEqualTo("visual-crossing");
        assertThat(out.providerType()).isEqualTo(WeatherSourceType.VISUAL_CROSSING);
        assertThat(out.mli()).isEqualTo("13068500");
        assertThat(out.fetchedUtc()).isEqualTo(NOW);
        // the raw document survives, which is what makes a stored payload replayable
        assertThat(out.raw().path("queryCost").asInt()).isEqualTo(1);
        assertThat(out.raw().path("days")).hasSize(1);
    }

    @Test
    void unknownIconFallsBackWithoutLosingTheDay() throws Exception {
        String raw = payload(day("2026-08-13",
                "\"tempmax\":85.0,\"tempmin\":62.0,\"icon\":\"meteor-shower\""));

        ForecastDay d = converter.convert(raw, "13068500").days().get(0);

        assertThat(d.weatherCode()).isNull();
        assertThat(d.icon()).isEqualTo("om_na.png");
        assertThat(d.tempHighC()).isNotNull();
    }

    @Test
    void throwsWhenTheDocumentIsNotVisualCrossing() {
        assertThatThrownBy(() -> converter.convert("{\"observations\":[{\"stationID\":\"KX\"}]}", "13068500"))
                .isInstanceOf(ForecastConversionException.class)
                .hasMessageContaining("no days[]");
    }

    @Test
    void throwsWhenEveryDayIsInThePast() {
        String raw = payload(day("2026-08-01", "\"tempmax\":85.0,\"tempmin\":62.0,\"icon\":\"clear-day\""));

        assertThatThrownBy(() -> converter.convert(raw, "13068500"))
                .isInstanceOf(ForecastConversionException.class)
                .hasMessageContaining("entirely in the past");
    }

    @Test
    void throwsOnMalformedJson() {
        assertThatThrownBy(() -> converter.convert("not json", "13068500"))
                .isInstanceOf(ForecastConversionException.class)
                .hasMessageContaining("not valid JSON");
    }
}
