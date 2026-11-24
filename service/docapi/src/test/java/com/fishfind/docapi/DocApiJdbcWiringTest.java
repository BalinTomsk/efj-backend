package com.fishfind.docapi;

import com.fishfind.docapi.repo.CsNewsClient;
import com.fishfind.docapi.repo.DocumentStore;
import com.fishfind.docapi.repo.NewsQueryRepository;
import com.zaxxer.hikari.HikariDataSource;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.yaml.snakeyaml.Yaml;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;

import javax.sql.DataSource;
import java.time.Duration;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Verifies the {@code jdbc} profile still wires cleanly: JDBC auto-configuration is re-enabled, a
 * datasource is created (H2 stands in for SQL Server here), and the JDBC-backed stores are injected
 * into the services. No stored procedures are invoked at startup, so H2's lack of them is irrelevant.
 */
@SpringBootTest
@ActiveProfiles({"test", "jdbc"})
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:docapi-jdbc-test;MODE=MSSQLServer;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.datasource.driver-class-name=org.h2.Driver",
        // Never called in this test (CsNewsClient connects lazily per request); the bind only needs a value.
        "csnews.url=http://127.0.0.1:1"
})
class DocApiJdbcWiringTest {

    @Autowired
    private ApplicationContext context;

    @Autowired
    private NewsQueryRepository newsQueryRepository;

    @Autowired
    @Qualifier("newsStore")
    private DocumentStore newsStore;

    @Test
    void contextLoadsUnderJdbcProfile() {
    }

    /**
     * The caches must decorate the SQL repositories, not replace them.
     */
    @Test
    void newsReadsAreServedThroughTheCaches() {
        assertThat(newsQueryRepository.getClass().getSimpleName()).isEqualTo("NewsQueryCache");
        assertThat(newsStore.getClass().getSimpleName()).isEqualTo("NewsDocumentCache");
    }

    /**
     * docapi 1.44.0: no bean talks to MySQL. Every bean behind the news controllers holds the one
     * {@link CsNewsClient} (csnews-env), and the MySQL template and its bootstraps are gone. Checked against the
     * real target object's field, not a name, so a future re-wiring to a database fails here.
     */
    @Test
    void everyNewsBeanTalksToCsNewsOnly() throws Exception {
        assertThat(context.containsBean("mysqlNewsJdbcTemplate")).isFalse();
        assertThat(context.containsBean("newsIndexBootstrap")).isFalse();
        assertThat(context.containsBean("newsPhotoTriggerBootstrap")).isFalse();

        CsNewsClient csnews = context.getBean(CsNewsClient.class);
        for (String name : List.of("jdbcNewsStore", "jdbcNewsQueryRepository", "newsWriteRepository",
                "newsAdminCommandRepository", "newsNearRepository")) {
            Object target = org.springframework.test.util.AopTestUtils.getUltimateTargetObject(context.getBean(name));
            var field = target.getClass().getDeclaredField("csnews");
            field.setAccessible(true);
            assertThat(field.get(target)).as("%s must hold the csnews-env client", name).isSameAs(csnews);
        }
    }

    /** No MySQL driver on the classpath: docapi cannot reach the news database even by accident. */
    @Test
    void theMySqlDriverIsGone() {
        org.assertj.core.api.Assertions.assertThatThrownBy(() -> Class.forName("com.mysql.cj.jdbc.Driver"))
                .isInstanceOf(ClassNotFoundException.class);
    }

    /** csnews-env's budget fits inside cproxy's 10 s read timeout, like the database paths. */
    @Test
    void csNewsRequestFitsInsideTheProxyReadTimeout() throws Exception {
        var field = CsNewsClient.class.getDeclaredField("requestTimeout");
        field.setAccessible(true);
        assertThat((Duration) field.get(context.getBean(CsNewsClient.class))).isLessThan(Duration.ofSeconds(10));
    }

    /**
     * The DB failure path must finish inside cproxy's read timeout.
     *
     * <p>cproxy fronts this service with a 10s read timeout (and one retry for idempotent GETs), so a
     * request docapi cannot answer within roughly that window reaches the caller as an opaque 502
     * with no diagnosis. On 2026-09-02 the settings were 30s Hikari connect timeout, no driver-level
     * timeouts, and Resilience4j retrying 3x with 2s waits — a worst case near 94s for a single
     * request, which is exactly what a flaky network path to the DB host turned into an apparent
     * "hang". Every /api/* call that touched a database timed out at the proxy.
     *
     * <p>This asserts the BUDGET rather than the literal numbers, so the knobs can be retuned freely
     * as long as the guarantee survives.
     */
    @Test
    void dbFailurePathFitsInsideTheProxyReadTimeout() throws Exception {
        final Duration proxyReadTimeout = Duration.ofSeconds(10);

        // The Hikari value comes from application-jdbc.yml, which IS active here, so the running
        // context carries the production number.
        DataSource dataSource = context.getBean(DataSource.class);
        assertThat(dataSource).isInstanceOf(HikariDataSource.class);
        long connectTimeoutMs = ((HikariDataSource) dataSource).getConnectionTimeout();

        // The retry values must NOT be read from the context: application-test.yml deliberately
        // overrides sqlRetry to 3 attempts / 10ms so the suite runs fast. Asserting those would make
        // this test pass while production stayed misconfigured — the exact blind spot it exists to
        // close — so the PRODUCTION yaml is parsed directly.
        Map<String, Object> retry = prodSqlRetryConfig();
        int attempts = (int) retry.get("max-attempts");
        long waitMs = parseDurationMs(String.valueOf(retry.get("wait-duration")));

        Duration worstCase = Duration.ofMillis(attempts * connectTimeoutMs + (attempts - 1L) * waitMs);

        assertThat(worstCase)
                .as("worst-case DB failure path (%d attempts x %dms connect + %d x %dms wait) must "
                                + "stay inside cproxy's %s read timeout, or failures can only ever "
                                + "surface as an opaque 502",
                        attempts, connectTimeoutMs, attempts - 1, waitMs, proxyReadTimeout)
                .isLessThan(proxyReadTimeout);
    }

    /**
     * Only failures a second attempt could plausibly clear may be retried.
     *
     * <p>The list was originally `DataAccessException` + `SQLException` — the root of Spring's DAO
     * hierarchy, which retries *everything*. During the 2026-09-02 incident that retried a
     * `BadSqlGrammarException` (T-SQL sent to MySQL) twice for nothing, and it would retry a
     * `DataIntegrityViolationException` on a write the same way.
     *
     * <p>Asserted behaviourally, by assignability against the configured types, rather than by
     * comparing strings — the point is which failures retry, not how the list is spelled. Note the
     * three configured entries are not redundant: Spring files connection failures under different
     * branches (see the comment in application.yml), so a "just use TransientDataAccessException"
     * simplification would silently stop retrying driver-level connect failures — the exact case
     * this retry exists for.
     */
    @Test
    void onlyTransientFailuresAreRetried() throws Exception {
        List<Class<?>> configured = prodRetryExceptionClasses();

        // Must retry: the three shapes an intermittently lossy network path actually produces.
        assertRetried(configured, org.springframework.dao.TransientDataAccessResourceException.class,
                true, "Hikari pool timeout (SQLTransientConnectionException)");
        assertRetried(configured, org.springframework.dao.DataAccessResourceFailureException.class,
                true, "driver connect failure (SQLNonTransientConnectionException)");
        assertRetried(configured, org.springframework.dao.RecoverableDataAccessException.class,
                true, "connection dropped mid-use (SQLRecoverableException)");
        assertRetried(configured, org.springframework.dao.QueryTimeoutException.class,
                true, "query timeout");
        assertRetried(configured, org.springframework.dao.ConcurrencyFailureException.class,
                true, "deadlock / optimistic locking");

        // Must NOT retry: permanent faults. Retrying these only multiplies latency, and on a write
        // path it can compound the damage.
        assertRetried(configured, org.springframework.jdbc.BadSqlGrammarException.class,
                false, "bad SQL grammar - the 2026-09-02 case");
        assertRetried(configured, org.springframework.dao.DataIntegrityViolationException.class,
                false, "constraint violation");
        assertRetried(configured, org.springframework.dao.DuplicateKeyException.class,
                false, "duplicate key");
        assertRetried(configured, org.springframework.dao.PermissionDeniedDataAccessException.class,
                false, "permission denied");
        assertRetried(configured, org.springframework.dao.InvalidDataAccessApiUsageException.class,
                false, "programming error");
    }

    private static void assertRetried(List<Class<?>> configured, Class<?> thrown,
                                      boolean expected, String why) {
        boolean retried = configured.stream().anyMatch(c -> c.isAssignableFrom(thrown));
        assertThat(retried)
                .as("%s (%s) should %sbe retried", why, thrown.getSimpleName(),
                        expected ? "" : "NOT ")
                .isEqualTo(expected);
    }

    /**
     * The test profile may run faster than production, but it must not retry a DIFFERENT set of
     * failures — that would mean the suite exercises behaviour production does not have.
     */
    @Test
    @SuppressWarnings("unchecked")
    void retryExceptionListMirrorsProduction() throws Exception {
        List<String> prod = (List<String>) prodSqlRetryConfig().get("retry-exceptions");
        List<String> test;
        try (var in = new ClassPathResource("application-test.yml").getInputStream()) {
            Map<String, Object> root = new Yaml().load(in);
            Map<String, Object> r4j = (Map<String, Object>) root.get("resilience4j");
            Map<String, Object> instances =
                    (Map<String, Object>) ((Map<String, Object>) r4j.get("retry")).get("instances");
            test = (List<String>) ((Map<String, Object>) instances.get("sqlRetry")).get("retry-exceptions");
        }
        assertThat(test)
                .as("application-test.yml's sqlRetry retry-exceptions must mirror application.yml's; "
                        + "only the timings may differ")
                .containsExactlyElementsOf(prod);
    }

    /** The configured retry-exception types, loaded from the PRODUCTION application.yml. */
    @SuppressWarnings("unchecked")
    private List<Class<?>> prodRetryExceptionClasses() throws Exception {
        List<String> names = (List<String>) prodSqlRetryConfig().get("retry-exceptions");
        assertThat(names).as("sqlRetry must declare an explicit retry-exceptions list").isNotEmpty();
        List<Class<?>> out = new java.util.ArrayList<>();
        for (String n : names) out.add(Class.forName(n));
        return out;
    }

    /** resilience4j.retry.instances.sqlRetry from the PRODUCTION application.yml. */
    @SuppressWarnings("unchecked")
    private Map<String, Object> prodSqlRetryConfig() throws Exception {
        try (var in = new ClassPathResource("application.yml").getInputStream()) {
            // The production application.yml is a single document; the test profile lives in a
            // separate file, so nothing here can shadow these values.
            Map<String, Object> root = new Yaml().load(in);
            Map<String, Object> r4j = (Map<String, Object>) root.get("resilience4j");
            Map<String, Object> instances = (Map<String, Object>) ((Map<String, Object>) r4j.get("retry")).get("instances");
            return (Map<String, Object>) instances.get("sqlRetry");
        }
    }

    /** Minimal "500ms" / "2s" parser — enough for the two forms this config uses. */
    private static long parseDurationMs(String text) {
        String t = text.trim();
        if (t.endsWith("ms")) return Long.parseLong(t.substring(0, t.length() - 2).trim());
        if (t.endsWith("s")) return Long.parseLong(t.substring(0, t.length() - 1).trim()) * 1000L;
        return Long.parseLong(t);
    }

    /**
     * Hikari's connect timeout only bounds how long the POOL waits; without a driver-level login
     * timeout the underlying socket can still sit far longer on a dropped TCP handshake, which is
     * silence rather than a refusal.
     */
    @Test
    void theSqlServerPoolSetsADriverLevelConnectTimeout() {
        HikariDataSource sqlServer = (HikariDataSource) context.getBean(DataSource.class);
        // mssql-jdbc spells it loginTimeout, in SECONDS. (H2 stands in for the driver here; the
        // property is passed through either way, so this asserts the wiring, not H2's behaviour.)
        assertThat(sqlServer.getDataSourceProperties().getProperty("loginTimeout"))
                .as("SQL Server pool must set a driver loginTimeout")
                .isNotNull();
    }

    /**
     * The bare {@code JdbcTemplate} every SQL-Server-backed repository injects must be the SQL Server pool.
     * Between the MySQL news migration (2026-08-31) and 2026-09-02 a second (MySQL) template made Spring
     * Boot's auto-configured one back off, and T-SQL went to MySQL. That template is gone since 1.44.0; this
     * keeps any future second template from repeating it.
     */
    @Test
    void sqlServerRepositoriesGetTheSqlServerTemplate() {
        JdbcTemplate primary = context.getBean(JdbcTemplate.class);
        assertThat(primary.getDataSource()).isInstanceOf(HikariDataSource.class);
        assertThat(((HikariDataSource) primary.getDataSource()).getPoolName()).isEqualTo("docapi-hikari");
        assertThat(context.getBeansOfType(JdbcTemplate.class)).hasSize(1);
    }
}
