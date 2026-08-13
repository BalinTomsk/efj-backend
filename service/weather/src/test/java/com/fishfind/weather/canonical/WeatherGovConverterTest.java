package com.fishfind.weather.canonical;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import org.assertj.core.data.Offset;
import org.junit.jupiter.api.Test;

/**
 * weather.gov is the odd provider: it publishes PERIODS of roughly half a day, flagged isDaytime,
 * rather than days. These tests are mostly about assembling those back into calendar days -- including
 * the case that trips people up, a response whose first period is "Tonight" because the forecast was
 * issued in the evening.
 */
class WeatherGovConverterTest {

    private static final Instant NOW = Instant.parse("2026-08-13T04:12:00Z");
    private final WeatherGovConverter converter =
            new WeatherGovConverter(new ObjectMapper(), Clock.fixed(NOW, ZoneOffset.UTC));

    private static String forecast(String... periods) {
        return "{\"@context\":[],\"type\":\"Feature\",\"properties\":{\"updated\":\"2026-08-13T03:00:00Z\","
                + "\"units\":\"si\",\"periods\":[" + String.join(",", periods) + "]}}";
    }

    private static String period(int number, String name, String start, boolean isDaytime,
                                 int temperature, String extra) {
        return "{\"number\":" + number + ",\"name\":\"" + name + "\",\"startTime\":\"" + start + "\","
                + "\"endTime\":\"" + start + "\",\"isDaytime\":" + isDaytime + ","
                + "\"temperature\":" + temperature + ",\"temperatureUnit\":\"C\"," + extra + "}";
    }

    @Test
    void pairsDayAndNightPeriodsIntoOneDay() throws Exception {
        String raw = forecast(
                period(1, "Today", "2026-08-13T06:00:00-06:00", true, 29,
                        "\"probabilityOfPrecipitation\":{\"unitCode\":\"wmoUnit:percent\",\"value\":20},"
                                + "\"relativeHumidity\":{\"unitCode\":\"wmoUnit:percent\",\"value\":41},"
                                + "\"windSpeed\":\"10 to 15 km/h\",\"windDirection\":\"SSW\","
                                + "\"icon\":\"https://api.weather.gov/icons/land/day/sct?size=medium\","
                                + "\"shortForecast\":\"Mostly Sunny\","
                                + "\"detailedForecast\":\"Mostly sunny, with a high near 29.\""),
                period(2, "Tonight", "2026-08-13T18:00:00-06:00", false, 16,
                        "\"probabilityOfPrecipitation\":{\"unitCode\":\"wmoUnit:percent\",\"value\":0},"
                                + "\"windSpeed\":\"5 km/h\",\"windDirection\":\"S\","
                                + "\"icon\":\"https://api.weather.gov/icons/land/night/skc?size=medium\","
                                + "\"shortForecast\":\"Clear\",\"detailedForecast\":\"Clear.\""));

        CanonicalForecast out = converter.convert(raw, "13068500");

        assertThat(out.days()).hasSize(1);
        ForecastDay day = out.days().get(0);
        assertThat(day.date()).isEqualTo(LocalDate.parse("2026-08-13"));
        // high from the daytime period, low from the night one
        assertThat(day.tempHighC()).isEqualTo(29.0);
        assertThat(day.tempLowC()).isEqualTo(16.0);
        assertThat(day.tempC()).isEqualTo(29);
        // units=si means no conversion at all
        assertThat(day.windSpeedKmh()).isEqualTo(15.0);     // upper bound of "10 to 15 km/h"
        assertThat(day.windDirection()).isEqualTo("SSW");
        assertThat(day.humidityPct()).isEqualTo(41.0);
        assertThat(day.precipChancePct()).isEqualTo(20);
        assertThat(day.conditionsShort()).isEqualTo("Mostly Sunny");
        assertThat(day.weatherCode()).isEqualTo(2);          // "sct" -> partly cloudy
        assertThat(day.icon()).isEqualTo("om_2.png");
        assertThat(day.time()).isEqualTo(ForecastDay.DAILY_SUMMARY_TIME);
    }

    @Test
    void aResponseThatStartsWithTonightStillProducesThatDay() throws Exception {
        // Issued in the evening: the first period is a night, so the day has no daytime half at all.
        String raw = forecast(
                period(1, "Tonight", "2026-08-13T20:00:00-06:00", false, 14,
                        "\"windSpeed\":\"8 km/h\",\"windDirection\":\"N\","
                                + "\"icon\":\"https://api.weather.gov/icons/land/night/rain,40?size=medium\","
                                + "\"shortForecast\":\"Rain Likely\",\"detailedForecast\":\"Rain likely.\""),
                period(2, "Wednesday", "2026-08-14T06:00:00-06:00", true, 24,
                        "\"windSpeed\":\"12 km/h\",\"windDirection\":\"NW\","
                                + "\"icon\":\"https://api.weather.gov/icons/land/day/bkn?size=medium\","
                                + "\"shortForecast\":\"Partly Sunny\",\"detailedForecast\":\"Partly sunny.\""));

        CanonicalForecast out = converter.convert(raw, "13068500");

        assertThat(out.days()).hasSize(2);
        ForecastDay tonight = out.days().get(0);
        assertThat(tonight.date()).isEqualTo(LocalDate.parse("2026-08-13"));
        assertThat(tonight.tempHighC()).isNull();            // there was no daytime half
        assertThat(tonight.tempLowC()).isEqualTo(14.0);
        assertThat(tonight.tempC()).isEqualTo(14);           // falls back to the night period
        assertThat(tonight.conditionsShort()).isEqualTo("Rain Likely");
        assertThat(tonight.weatherCode()).isEqualTo(63);

        assertThat(out.days().get(1).tempHighC()).isEqualTo(24.0);
    }

    @Test
    void precipitationAmountIsLeftNullBecauseForecastDoesNotPublishIt() throws Exception {
        String raw = forecast(period(1, "Today", "2026-08-13T06:00:00-06:00", true, 20,
                "\"probabilityOfPrecipitation\":{\"value\":70},\"windSpeed\":\"5 km/h\","
                        + "\"windDirection\":\"E\",\"icon\":\"https://api.weather.gov/icons/land/day/rain?size=medium\","
                        + "\"shortForecast\":\"Rain\",\"detailedForecast\":\"Rain.\""));

        ForecastDay day = converter.convert(raw, "13068500").days().get(0);

        // a chance is published, a quantity is not -- inventing 0 mm would read as "no rain fell"
        assertThat(day.precipChancePct()).isEqualTo(70);
        assertThat(day.precipMm()).isNull();
        assertThat(day.precipDayMm()).isNull();
        assertThat(day.precipNightMm()).isNull();
        // and NWS gives a cardinal direction, never a bearing
        assertThat(day.windDegrees()).isNull();
        assertThat(day.windDirection()).isEqualTo("E");
    }

    @Test
    void stampsProvenanceAndKeepsTheRawDocument() throws Exception {
        String raw = forecast(period(1, "Today", "2026-08-13T06:00:00-06:00", true, 20,
                "\"windSpeed\":\"5 km/h\",\"windDirection\":\"E\","
                        + "\"icon\":\"https://api.weather.gov/icons/land/day/skc?size=medium\","
                        + "\"shortForecast\":\"Sunny\",\"detailedForecast\":\"Sunny.\""));

        CanonicalForecast out = converter.convert(raw, "13068500");

        assertThat(out.schema()).isEqualTo("fishfind.weather.forecast/v1");
        assertThat(out.provider()).isEqualTo("weather-gov");
        assertThat(out.providerType()).isEqualTo(WeatherSourceType.WEATHER_GOV);
        assertThat(out.fetchedUtc()).isEqualTo(NOW);
        assertThat(out.raw().path("properties").path("units").asText()).isEqualTo("si");
    }

    @Test
    void throwsWhenTheDocumentIsAnObservationRatherThanAForecast() {
        // This is what the service used to store for weather.gov: /observations/latest, which has
        // properties but no periods[]. It must fail loudly rather than write nothing.
        String observation = "{\"@context\":[],\"id\":\"https://api.weather.gov/stations/KBOI/observations/latest\","
                + "\"type\":\"Feature\",\"geometry\":{},\"properties\":{\"temperature\":{\"value\":21.1}}}";

        assertThatThrownBy(() -> converter.convert(observation, "13068500"))
                .isInstanceOf(ForecastConversionException.class)
                .hasMessageContaining("no properties.periods[]");
    }

    @Test
    void throwsOnMalformedJson() {
        assertThatThrownBy(() -> converter.convert("<html>503</html>", "13068500"))
                .isInstanceOf(ForecastConversionException.class)
                .hasMessageContaining("not valid JSON");
    }

    @Test
    void windSpeedTakesTheUpperBoundAndToleratesOddText() {
        assertThat(WeatherGovConverter.windSpeedOf("10 to 15 km/h")).isEqualTo(15.0, Offset.offset(0.001));
        assertThat(WeatherGovConverter.windSpeedOf("5 km/h")).isEqualTo(5.0, Offset.offset(0.001));
        assertThat(WeatherGovConverter.windSpeedOf("Calm")).isNull();
        assertThat(WeatherGovConverter.windSpeedOf(null)).isNull();
    }

    @Test
    void unknownIconTokenFallsBackWithoutLosingTheDay() {
        assertThat(WeatherGovConverter.codeOf(
                "https://api.weather.gov/icons/land/day/tsra_hi,40?size=medium")).isEqualTo(95);
        assertThat(WeatherGovConverter.codeOf(
                "https://api.weather.gov/icons/land/day/volcano?size=medium")).isNull();
        assertThat(WeatherGovConverter.codeOf(null)).isNull();
    }
}
