package com.fishfind.weather.repo;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fishfind.weather.canonical.CanonicalForecast;
import com.fishfind.weather.canonical.ForecastDay;
import com.fishfind.weather.canonical.WeatherSourceType;
import com.fishfind.weather.config.EnvdataDataSourceConfig;
import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.service.StationPostProcessingService;
import com.zaxxer.hikari.HikariDataSource;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

/**
 * The real repositories against a real MySQL engine, so every CALL is parsed and bound the way production does it (a
 * mocked JdbcTemplate never parses SQL). Runs only when {@code WEATHER_TEST_MYSQL} holds the JDBC URL (with
 * {@code user=}/{@code password=}) of a privileged account on a THROWAWAY database built from
 * {@code envfish-db/mysql/envdata}: it seeds a station, writes rows and deletes them again. The repositories connect
 * through {@link EnvdataDataSourceConfig} with {@code WEATHER_TEST_MYSQL_APP} when set: a URL of an account with
 * production's grants (EXECUTE; SELECT on {@code v_station_weather_due}, {@code v_weather_gov_station},
 * {@code v_provider_coverage}; REQUIRE SSL), so the grants are proven too.
 */
@EnabledIfEnvironmentVariable(named = "WEATHER_TEST_MYSQL", matches = "jdbc:mysql:.+")
class WeatherEngineTest {

    private static final int SID = 990101;
    private static final String MLI = "ENGINE-WX-1";

    private static JdbcTemplate admin;
    private static HikariDataSource appDataSource;
    private static JdbcTemplate app;

    private final ObjectMapper mapper = new ObjectMapper().findAndRegisterModules()
            .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    @BeforeAll
    static void connect() {
        admin = new JdbcTemplate(new DriverManagerDataSource(System.getenv("WEATHER_TEST_MYSQL")));
        String appUrl = System.getenv("WEATHER_TEST_MYSQL_APP");
        EnvdataDataSourceConfig config = new EnvdataDataSourceConfig();
        appDataSource = config.dataSource(
                appUrl == null || appUrl.isBlank() ? System.getenv("WEATHER_TEST_MYSQL") : appUrl, "", "");
        app = config.jdbcTemplate(appDataSource);
    }

    @AfterAll
    static void disconnect() {
        if (appDataSource != null) {
            appDataSource.close();
        }
    }

    @BeforeEach
    @AfterEach
    void clean() {
        admin.update("DELETE FROM weather_day WHERE station_id = ?", SID);
        admin.update("DELETE FROM weather_raw WHERE station_id = ?", SID);
        admin.update("DELETE FROM weather_gov_station WHERE station_id = ?", SID);
        admin.update("DELETE FROM provider_coverage WHERE station_id = ?", SID);
        admin.update("DELETE FROM job_run WHERE job LIKE 'engine-test%'");
        admin.update("DELETE FROM station WHERE station_id = ?", SID);
    }

    private static void seedStation() {
        admin.update("INSERT INTO station (station_id, mli, ws_id, country, state, lat, lon, loc_name, master_stamp, "
                + "mirror_stamp, has_fish) VALUES (?, ?, UUID(), 'CA', 'ON', 45, -79, 'engine test', UTC_TIMESTAMP(), "
                + "UTC_TIMESTAMP(), 1)", SID, MLI);
    }

    private static ForecastDay day(LocalDate date, Double tempHigh, Integer pressureHpa) {
        return new ForecastDay(date, "12:00:00", tempHigh, null, null, null, null, null, null, null, pressureHpa,
                null, null, null, null, null, null, null, null);
    }

    @Test
    void repositoriesConnectOverTlsAsTheConfiguredAccount() {
        String appUrl = System.getenv("WEATHER_TEST_MYSQL_APP");
        String cipher = app.queryForObject("SHOW SESSION STATUS LIKE 'Ssl_cipher'", (rs, i) -> rs.getString(2));
        if (appUrl != null && !appUrl.toLowerCase().contains("sslmode=disabled")) {
            assertThat(cipher).isNotBlank();
        }
        if (appUrl != null && appUrl.contains("user=weather")) {
            assertThat(app.queryForObject("SELECT CURRENT_USER()", String.class)).startsWith("weather@");
        }
    }

    @Test
    void canonicalPayloadIsStoredAndShreddedWithPressureInMmHg() throws Exception {
        seedStation();
        WeatherDataRepository data = new WeatherDataRepository(app);
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        CanonicalForecast forecast = new CanonicalForecast("open-meteo", WeatherSourceType.OPEN_METEO, MLI,
                Instant.now(), List.of(day(today.minusDays(1), 5.5, 1013), day(today, 3.0, null)), null);

        data.saveStationData(MLI, mapper.writeValueAsString(forecast), WeatherSourceType.OPEN_METEO);

        assertThat(admin.queryForObject("SELECT COUNT(*) FROM weather_day WHERE station_id = ?", Long.class, SID))
                .isEqualTo(2L);
        assertThat(admin.queryForObject("SELECT pressure_mm FROM weather_day WHERE station_id = ? AND dt = ?",
                BigDecimal.class, SID, today.minusDays(1))).isEqualByComparingTo("759.8");
        assertThat(admin.queryForObject(
                "SELECT COUNT(*) FROM weather_raw WHERE station_id = ? AND provider_type = 2", Long.class, SID))
                .isEqualTo(1L);
    }

    @Test
    void aNonCanonicalPayloadIsStoredButNotShredded() {
        seedStation();
        new WeatherDataRepository(app).saveStationData(MLI, "{\"legacy\":true}", WeatherSourceType.WEATHER_GOV);

        assertThat(admin.queryForObject("SELECT COUNT(*) FROM weather_raw WHERE station_id = ?", Long.class, SID))
                .isEqualTo(1L);
        assertThat(admin.queryForObject("SELECT COUNT(*) FROM weather_day WHERE station_id = ?", Long.class, SID))
                .isZero();
    }

    @Test
    void unknownStationIsLoggedAndDroppedNotAFailure() {
        new WeatherDataRepository(app).saveStationData("NO-SUCH-STATION", "{}", WeatherSourceType.OPEN_METEO);
    }

    @Test
    void stationListNwsCacheCoverageJobRunAndCleanupRunOnTheEngine() {
        seedStation();
        WeatherStationRepository stations = new WeatherStationRepository(app);
        WeatherGovStationRepository nws = new WeatherGovStationRepository(app);
        WeatherStationCoverageRepository coverage = new WeatherStationCoverageRepository(app);
        WeatherDataRepository data = new WeatherDataRepository(app);

        assertThat(stations.countSupportedStations("CA")).isGreaterThanOrEqualTo(1);
        List<StationRef> due = stations.findSupportedStations("CA", 100_000);
        assertThat(due).anyMatch(s -> s.mli().equals(MLI) && "ON".equals(s.state()));

        assertThat(nws.find(MLI)).isEmpty();
        nws.save(MLI, 45, -79, null);
        assertThat(nws.find(MLI)).hasValueSatisfying(c -> assertThat(c.stationId()).isNull());
        nws.save(MLI, 45, -79, "KMKE");
        assertThat(nws.find(MLI)).hasValueSatisfying(c -> assertThat(c.stationId()).isEqualTo("KMKE"));

        coverage.save(MLI, "weather-canada", false);
        coverage.save(MLI, "weather-canada", true);
        assertThat(admin.queryForObject("SELECT covered FROM provider_coverage WHERE station_id = ? AND provider = ?",
                Integer.class, SID, "weather-canada")).isEqualTo(1);

        LocalDateTime now = LocalDateTime.now(ZoneOffset.UTC).withNano(0);
        data.recordCycle("engine-test", now.minusMinutes(2), now, "ok", 7, null);
        assertThat(admin.queryForObject("SELECT CONCAT(service, '|', status, '|', items) FROM v_job_run_pending "
                + "WHERE job = 'engine-test'", String.class)).isEqualTo("weather|ok|7");

        // Through the post-processing service: job name from the report name, as the C# twin records it.
        new StationPostProcessingService(data).runAfterStationProcessing("Engine-Test", "us", Instant.now(), 3, 1);
        assertThat(admin.queryForObject("SELECT CONCAT(status, '|', note) FROM v_job_run_pending "
                + "WHERE job = 'engine-test-us'", String.class)).isEqualTo("partial|failed=1");
    }
}
