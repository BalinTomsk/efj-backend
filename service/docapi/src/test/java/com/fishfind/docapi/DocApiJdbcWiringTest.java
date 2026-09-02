package com.fishfind.docapi;

import com.fishfind.docapi.repo.DocumentStore;
import com.fishfind.docapi.repo.NewsQueryRepository;
import com.zaxxer.hikari.HikariDataSource;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.yaml.snakeyaml.Yaml;
import org.springframework.aop.support.AopUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;

import javax.sql.DataSource;
import java.time.Duration;
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
        // Never actually connected in this test: HikariDataSource built via the no-arg constructor +
        // setters (see JdbcStoreConfig.mysqlNewsJdbcTemplate) initializes its pool lazily on first
        // getConnection(), so a placeholder URL is enough to satisfy the @Value bind at startup.
        "newsmysql.datasource.url=jdbc:mysql://localhost:3306/unused",
        "newsmysql.datasource.username=unused",
        "newsmysql.datasource.password=unused"
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
     * Resilience4j's {@code @Retry} / {@code @CircuitBreaker} are applied by AOP, which Spring can only
     * do to beans it manages. Constructing the SQL repository with {@code new} inside a cache would
     * leave those annotations silently inert — the SQL calls would lose their retry and breaker
     * without any compile or startup error. Assert the delegates really are advised proxies.
     */
    @Test
    void sqlDelegatesBehindTheCachesAreStillResilienceProxies() {
        Object queryDelegate = context.getBean("jdbcNewsQueryRepository");
        Object storeDelegate = context.getBean("jdbcNewsStore");

        assertThat(AopUtils.isAopProxy(queryDelegate))
                .as("jdbcNewsQueryRepository must be an AOP proxy so @Retry/@CircuitBreaker apply")
                .isTrue();
        assertThat(AopUtils.isAopProxy(storeDelegate))
                .as("jdbcNewsStore must be an AOP proxy so @Retry/@CircuitBreaker apply")
                .isTrue();
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
     * silence rather than a refusal. Both pools must set one.
     */
    @Test
    void bothPoolsSetADriverLevelConnectTimeout() {
        HikariDataSource sqlServer = (HikariDataSource) context.getBean(DataSource.class);
        // mssql-jdbc spells it loginTimeout, in SECONDS. (H2 stands in for the driver here; the
        // property is passed through either way, so this asserts the wiring, not H2's behaviour.)
        assertThat(sqlServer.getDataSourceProperties().getProperty("loginTimeout"))
                .as("SQL Server pool must set a driver loginTimeout")
                .isNotNull();

        // Connector/J spells it connectTimeout, in MILLISECONDS - a unit mismatch here would be an
        // easy and very expensive mistake, so both are asserted explicitly.
        assertThat(mysqlNewsPool().getDataSourceProperties().getProperty("connectTimeout"))
                .as("MySQL news pool must set a driver connectTimeout")
                .isNotNull();
        assertThat(mysqlNewsPool().getConnectionTimeout())
                .as("MySQL news pool shares the same budget as the SQL Server pool")
                .isLessThan(Duration.ofSeconds(10).toMillis());
    }

    /**
     * The bare {@code JdbcTemplate} that every SQL-Server-backed repository injects must be bound to
     * the SQL SERVER datasource — not the MySQL news pool.
     *
     * <p>This is the bug that took most of the API down between the MySQL news migration
     * (2026-08-31) and 2026-09-02. {@code mysqlNewsJdbcTemplate} registers a {@link JdbcTemplate}
     * bean, and Spring Boot's {@code JdbcTemplateAutoConfiguration} is
     * {@code @ConditionalOnMissingBean(JdbcOperations.class)} — so it backed off entirely, the SQL
     * Server template was never created, and all thirteen beans that inject {@code JdbcTemplate} by
     * type silently received the MySQL one. Production then sent T-SQL to MySQL and every
     * SQL-Server-backed endpoint 500'd with
     * {@code "check the manual that corresponds to your MySQL server version"}.
     *
     * <p>The class comment on {@code mysqlNewsJdbcTemplate} documents this exact hazard one layer
     * down, for {@code DataSource}, and dodges it by keeping the {@link HikariDataSource} local. The
     * same trap exists for {@code JdbcTemplate}, and nothing caught it: the pre-existing wiring tests
     * only asserted that beans were AOP proxies, never which database they pointed at.
     */
    @Test
    void sqlServerRepositoriesGetTheSqlServerTemplateNotTheMysqlOne() {
        JdbcTemplate primary = context.getBean(JdbcTemplate.class);
        assertThat(primary.getDataSource()).isInstanceOf(HikariDataSource.class);
        HikariDataSource primaryPool = (HikariDataSource) primary.getDataSource();

        assertThat(primaryPool.getPoolName())
                .as("the by-type JdbcTemplate (injected by fishQueryRepository, riverQueryRepository, "
                        + "regulation*, station/fish/waterbody stores, ...) must be the SQL Server "
                        + "pool; getting the MySQL pool here means T-SQL is being sent to MySQL")
                .isEqualTo("docapi-hikari");

        // ...and it must be a genuinely different pool from the news one, not the same object.
        assertThat(primaryPool)
                .as("SQL Server and MySQL news pools must be distinct")
                .isNotSameAs(mysqlNewsPool());
        assertThat(mysqlNewsPool().getPoolName()).isEqualTo("docapi-news-mysql-hikari");
    }

    /** The MySQL pool is deliberately not a DataSource bean, so reach it through its JdbcTemplate. */
    private HikariDataSource mysqlNewsPool() {
        var jdbc = (org.springframework.jdbc.core.JdbcTemplate) context.getBean("mysqlNewsJdbcTemplate");
        return (HikariDataSource) jdbc.getDataSource();
    }
}
