package com.fishfind.water.repo;

import com.fishfind.water.config.EnvdataDataSourceConfig;
import com.fishfind.water.config.SqlFailures;
import com.fishfind.water.domain.Reading;
import com.fishfind.water.domain.StationRef;
import com.fishfind.water.domain.UsSeriesReading;
import com.zaxxer.hikari.HikariDataSource;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.stream.IntStream;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * The real repositories against a real MySQL engine, so every CALL is parsed and bound the way production does it (a
 * mocked JdbcTemplate never parses SQL). Runs only when {@code WATER_TEST_MYSQL} holds the JDBC URL (with
 * {@code user=}/{@code password=}) of a privileged account on a THROWAWAY database built from
 * {@code envfish-db/mysql/envdata} (script0 + script01_* + script02_Proc): it seeds a station, writes rows and deletes
 * them again. The repositories themselves connect through {@link EnvdataDataSourceConfig} with
 * {@code WATER_TEST_MYSQL_APP} when set: a URL of an account with production's grants (EXECUTE on the database,
 * SELECT on {@code v_station_water_due}, REQUIRE SSL), so the grants are proven too.
 * <pre>
 * WATER_TEST_MYSQL=jdbc:mysql://127.0.0.1:3306/envtest?user=root&amp;sslMode=DISABLED
 * WATER_TEST_MYSQL_APP=jdbc:mysql://127.0.0.1:3306/envtest?user=waterservice&amp;password=...
 * </pre>
 */
@EnabledIfEnvironmentVariable(named = "WATER_TEST_MYSQL", matches = "jdbc:mysql:.+")
class WaterEngineTest {

    private static final int SID = 990001;
    private static final String MLI = "ENGINE-TEST-1";

    private static JdbcTemplate admin;
    private static HikariDataSource appDataSource;
    private static JdbcTemplate app;

    private WaterDataRepository data;
    private StationHttp503BackoffRepository backoff;
    private WaterStationRepository stations;

    @BeforeAll
    static void connect() {
        admin = new JdbcTemplate(new DriverManagerDataSource(System.getenv("WATER_TEST_MYSQL")));
        String appUrl = System.getenv("WATER_TEST_MYSQL_APP");
        EnvdataDataSourceConfig config = new EnvdataDataSourceConfig();
        appDataSource = config.dataSource(appUrl == null || appUrl.isBlank() ? System.getenv("WATER_TEST_MYSQL") : appUrl,
                "", "");
        app = config.jdbcTemplate(appDataSource);
    }

    @AfterAll
    static void disconnect() {
        if (appDataSource != null) {
            appDataSource.close();
        }
    }

    @BeforeEach
    void seed() {
        clean();
        data = new WaterDataRepository(app);
        backoff = new StationHttp503BackoffRepository(app);
        stations = new WaterStationRepository(app);
        // Readings need a partition for their day: the retention procedure adds them (30 back, some ahead).
        data.cleanOldWaterData();
    }

    @AfterEach
    void clean() {
        admin.update("DELETE FROM water_reading WHERE station_id = ?", SID);
        admin.update("DELETE FROM station_current WHERE station_id = ?", SID);
        admin.update("DELETE FROM job_run WHERE job = 'engine-test'");
        admin.update("DELETE FROM station WHERE station_id = ?", SID);
    }

    private static void seedStation(String country) {
        admin.update("INSERT INTO station (station_id, mli, ws_id, country, state, lat, lon, loc_name, master_stamp, "
                + "mirror_stamp) VALUES (?, ?, UUID(), ?, 'ON', 45, -79, 'engine test', UTC_TIMESTAMP(), UTC_TIMESTAMP())",
                SID, MLI, country);
    }

    @Test
    void repositoriesConnectOverTlsAsTheConfiguredAccount() {
        // MySqlUrl adds sslMode=REQUIRED when the URL names none: envdata's accounts are REQUIRE SSL.
        String cipher = app.queryForObject("SHOW SESSION STATUS LIKE 'Ssl_cipher'", (rs, i) -> rs.getString(2));
        String appUrl = System.getenv("WATER_TEST_MYSQL_APP");
        if (appUrl != null && !appUrl.isBlank() && !appUrl.toLowerCase().contains("sslmode=disabled")) {
            assertFalse(cipher == null || cipher.isBlank(), "no TLS cipher on the app connection");
        }
        if (appUrl != null && appUrl.contains("user=waterservice")) {
            assertTrue(app.queryForObject("SELECT CURRENT_USER()", String.class).startsWith("waterservice@"));
            // Production's grants: no direct table access.
            assertThrows(RuntimeException.class, () -> app.queryForObject("SELECT COUNT(*) FROM station", Long.class));
        }
    }

    @Test
    void caSaveWritesReadingsAndCurrentStateInOneTransaction() {
        seedStation("CA");
        OffsetDateTime t = OffsetDateTime.now(ZoneOffset.UTC).truncatedTo(ChronoUnit.HOURS).minusHours(1);
        List<Reading> readings = IntStream.range(0, 700)
                .mapToObj(i -> new Reading(MLI, t.minusMinutes(5L * i), 1.5, i == 0 ? -999.0 : 20.0 + i))
                .toList();

        // The production path is @Transactional; run it inside one here too, so two 500/200 calls share a transaction.
        new TransactionTemplate(new DataSourceTransactionManager(appDataSource))
                .executeWithoutResult(status -> data.saveStationData(MLI, readings));

        assertEquals(700L, admin.queryForObject(
                "SELECT COUNT(*) FROM water_reading WHERE station_id = ?", Long.class, SID));
        // The newest reading's -999 discharge is stored as NULL; the current state keeps the newest real value.
        assertEquals(null, admin.queryForObject("SELECT discharge FROM water_reading WHERE station_id = ? AND ts = ?",
                Double.class, SID, t.toLocalDateTime()));
        assertEquals(21.0, admin.queryForObject(
                "SELECT discharge FROM station_current WHERE station_id = ?", Double.class, SID));
        List<StationRef> due = stations.findSupported("CA");
        assertTrue(due.stream().anyMatch(s -> s.mli().equals(MLI)));
    }

    @Test
    void usSaveMergesAllSeriesOfADayInMetricAndMmHg() {
        seedStation("US");
        LocalDate day = LocalDate.now(ZoneOffset.UTC).minusDays(1);

        data.saveUsStationData(MLI, "WI", List.of(
                new UsSeriesReading("Streamflow", "ft^3/s", day, 100),
                new UsSeriesReading("Barometric pressure", "mmHg", day, 755.34),
                new UsSeriesReading("pH", "water, unfiltered, field, standard units", day, 7.62)));

        assertEquals("2.8317|755.3|7.62", admin.queryForObject(
                "SELECT CONCAT(ROUND(discharge, 4), '|', pressure_mm, '|', ph) FROM water_reading WHERE station_id = ?",
                String.class, SID));
        assertEquals("WI", admin.queryForObject("SELECT state FROM station WHERE station_id = ?", String.class, SID));
    }

    @Test
    void usSaveConvertsHectopascalsToMmHg() {
        seedStation("US");
        LocalDate day = LocalDate.now(ZoneOffset.UTC).minusDays(1);

        data.saveUsStationData(MLI, "UT", List.of(
                new UsSeriesReading("Barometric pressure", "uncorrected, hectopascals", day, 1013.25)));

        assertEquals("760.0", admin.queryForObject(
                "SELECT CAST(pressure_mm AS CHAR) FROM water_reading WHERE station_id = ?", String.class, SID));
    }

    @Test
    void unknownStationIsRefusedWith45000AndNotCountedAsAnOutage() {
        RuntimeException refused = assertThrows(RuntimeException.class, () -> data.saveStationData("NO-SUCH-STATION",
                List.of(new Reading("x", OffsetDateTime.now(ZoneOffset.UTC), 1.0, 1.0))));

        assertTrue(SqlFailures.isProcedureRefusal(refused), refused.toString());
        assertFalse(SqlFailures.isSqlFailure(refused));
    }

    @Test
    void backoffJobRunAndCleanupRunOnTheEngine() {
        seedStation("CA");
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        backoff.recordHttp503("environment-canada", "CA", MLI, "ON", today.minusDays(2));
        backoff.recordHttp503("environment-canada", "CA", MLI, "ON", today.minusDays(1));
        backoff.recordHttp503("environment-canada", "CA", MLI, "ON", today);
        assertEquals(2, admin.queryForObject("SELECT backoff_state FROM station WHERE station_id = ?", Integer.class, SID));
        assertTrue(backoff.summaryByState().stream()
                .anyMatch(s -> "ON".equals(s.state()) && "WEEKLY".equals(s.backoffStage())));
        assertFalse(stations.findSupported("CA").stream().anyMatch(s -> s.mli().equals(MLI)));

        backoff.reset("environment-canada", "CA", MLI);
        backoff.refreshDue(today);
        assertEquals(1, admin.queryForObject("SELECT supported FROM station WHERE station_id = ?", Integer.class, SID));

        LocalDateTime now = LocalDateTime.now(ZoneOffset.UTC).withNano(0);
        data.recordCycle("engine-test", now.minusMinutes(3), now, "partial", 5, "failed=2");
        assertEquals("waterservice|partial|5|failed=2", admin.queryForObject(
                "SELECT CONCAT(service, '|', status, '|', items, '|', note) FROM v_job_run_pending WHERE job = 'engine-test'",
                String.class));
        data.recordCycle("engine-test", now.minusMinutes(3), now, "ok", 5, null);
        assertEquals(2L, admin.queryForObject(
                "SELECT COUNT(*) FROM v_job_run_pending WHERE job = 'engine-test' AND started = ?", Long.class,
                now.minusMinutes(3)));

        data.cleanOldWaterData();
        assertTrue(admin.queryForObject("SELECT COUNT(*) FROM information_schema.partitions WHERE table_schema = DATABASE() "
                + "AND table_name = 'water_reading' AND partition_name LIKE 'p\\_2%'", Long.class) > 30L);
    }
}
