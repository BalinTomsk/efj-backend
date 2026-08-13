package com.fishfind.weather.canonical;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.assertj.core.data.Offset;
import org.junit.jupiter.api.Test;

/**
 * Open-Meteo is already metric, so these tests are about the REDUCTION the database used to perform:
 * latest hour of each day wins, rainfall splits at 06:00–17:59, daytime temperature is a mean. The
 * expectations mirror the T-SQL exactly so a station's numbers do not shift during the rollout.
 */
class OpenMeteoConverterTest {

    private static final Instant NOW = Instant.parse("2026-08-13T04:12:00Z");
    private final Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);
    private final OpenMeteoConverter converter = new OpenMeteoConverter(new ObjectMapper(), clock);

    @Test
    void latestHourOfTheDayWins() throws Exception {
        String raw = """
                {"hourly":{
                   "time":["2026-08-13T22:00","2026-08-13T23:00"],
                   "temperature_2m":[15.0,16.0],
                   "relative_humidity_2m":[80,82],
                   "precipitation_probability":[10,20],
                   "pressure_msl":[1010,1011],
                   "wind_speed_10m":[5.0,5.5],
                   "wind_direction_10m":[180,191],
                   "weather_code":[0,0],
                   "rain":[0.0,0.0]},
                 "daily":{"time":["2026-08-13"],
                   "temperature_2m_max":[24.7],"temperature_2m_min":[11.8]}}
                """;

        ForecastDay d = converter.convert(raw, "01015800").days().get(0);

        assertThat(d.time()).isEqualTo("23:00:00");
        assertThat(d.tempC()).isEqualTo(16);              // the 23:00 hour, not the 22:00 one
        assertThat(d.humidityPct()).isEqualTo(82.0);
        assertThat(d.windSpeedKmh()).isEqualTo(5.5);
        assertThat(d.windDegrees()).isEqualTo(191.0);
        assertThat(d.windDirection()).isEqualTo("S");
        assertThat(d.pressureHpa()).isEqualTo(1011);
        assertThat(d.tempHighC()).isEqualTo(24.7);        // from the daily arrays
        assertThat(d.tempLowC()).isEqualTo(11.8);
        assertThat(d.weatherCode()).isZero();
        assertThat(d.icon()).isEqualTo("om_0.png");
        assertThat(d.conditionsShort()).isEqualTo("Clear");
        assertThat(d.conditionsLong()).isEqualTo("Clear sky");
    }

    @Test
    void rainSplitsAtTheDaytimeBoundaryAndDaytimeTemperatureIsAMean() throws Exception {
        String raw = """
                {"hourly":{
                   "time":["2026-08-13T05:00","2026-08-13T06:00","2026-08-13T17:00","2026-08-13T18:00"],
                   "temperature_2m":[9.0,10.0,20.0,21.0],
                   "rain":[1.0,2.0,3.0,4.0],
                   "weather_code":[61,61,61,61]},
                 "daily":{"time":["2026-08-13"],
                   "temperature_2m_max":[21.0],"temperature_2m_min":[9.0]}}
                """;

        ForecastDay d = converter.convert(raw, "01015800").days().get(0);

        // 06:00 and 17:00 are daytime (2.0 + 3.0); 05:00 and 18:00 are not (1.0 + 4.0)
        assertThat(d.precipDayMm()).isCloseTo(5.0, Offset.offset(0.001));
        assertThat(d.precipNightMm()).isCloseTo(5.0, Offset.offset(0.001));
        assertThat(d.precipMm()).isEqualTo(10);
        // daytime mean of 10.0 and 20.0
        assertThat(d.tempDayC()).isCloseTo(15.0, Offset.offset(0.001));
    }

    @Test
    void emitsOneRowPerDay() throws Exception {
        String raw = """
                {"hourly":{
                   "time":["2026-08-13T12:00","2026-08-13T13:00","2026-08-14T12:00"],
                   "temperature_2m":[15.0,16.0,17.0],
                   "rain":[0.0,0.0,0.0],
                   "weather_code":[2,2,3]},
                 "daily":{"time":["2026-08-13","2026-08-14"],
                   "temperature_2m_max":[20.0,21.0],"temperature_2m_min":[10.0,11.0]}}
                """;

        CanonicalForecast out = converter.convert(raw, "01015800");

        assertThat(out.days()).hasSize(2);
        assertThat(out.days().get(0).tempC()).isEqualTo(16);   // 13:00 beats 12:00
        assertThat(out.days().get(1).tempHighC()).isEqualTo(21.0);
        assertThat(out.days().get(1).weatherCode()).isEqualTo(3);
    }

    @Test
    void stampsProvenanceAndKeepsTheRawDocument() throws Exception {
        String raw = """
                {"hourly":{"time":["2026-08-13T23:00"],"temperature_2m":[16.0],
                   "rain":[0.0],"weather_code":[0]},
                 "daily":{"time":["2026-08-13"],
                   "temperature_2m_max":[24.7],"temperature_2m_min":[11.8]},
                 "timezone":"America/New_York"}
                """;

        CanonicalForecast out = converter.convert(raw, "01015800");

        assertThat(out.schema()).isEqualTo("fishfind.weather.forecast/v1");
        assertThat(out.provider()).isEqualTo("open-meteo");
        assertThat(out.providerType()).isEqualTo(WeatherSourceType.OPEN_METEO);
        assertThat(out.fetchedUtc()).isEqualTo(NOW);
        assertThat(out.raw().path("timezone").asText()).isEqualTo("America/New_York");
    }

    @Test
    void throwsWhenTheDocumentIsNotOpenMeteo() {
        assertThatThrownBy(() -> converter.convert("{\"days\":[{\"datetime\":\"2026-08-13\"}]}", "01015800"))
                .isInstanceOf(ForecastConversionException.class)
                .hasMessageContaining("no hourly.time[]");
    }

    @Test
    void throwsOnMalformedJson() {
        assertThatThrownBy(() -> converter.convert("<html>502</html>", "01015800"))
                .isInstanceOf(ForecastConversionException.class)
                .hasMessageContaining("not valid JSON");
    }
}
