package com.fishfind.docapi;

import com.fishfind.docapi.repo.DocumentStore;
import com.fishfind.docapi.repo.NewsQueryRepository;
import org.junit.jupiter.api.Test;
import org.springframework.aop.support.AopUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;

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
}
