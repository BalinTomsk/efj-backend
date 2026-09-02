package com.fishfind.docapi.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.DocumentStore;
import com.fishfind.docapi.repo.FishDocumentRepository;
import com.fishfind.docapi.repo.FishQueryRepository;
import com.fishfind.docapi.repo.JdbcFishQueryRepository;
import com.fishfind.docapi.repo.JdbcNewsQueryRepository;
import com.fishfind.docapi.repo.JdbcRiverDescriptionCommandRepository;
import com.fishfind.docapi.repo.JdbcRiverFishCommandRepository;
import com.fishfind.docapi.repo.JdbcRiverLinkCommandRepository;
import com.fishfind.docapi.repo.JdbcRiverQueryRepository;
import com.fishfind.docapi.repo.JdbcRegulationCommandRepository;
import com.fishfind.docapi.repo.JdbcRegulationQueryRepository;
import com.fishfind.docapi.repo.RegulationCommandRepository;
import com.fishfind.docapi.repo.RegulationQueryRepository;
import com.fishfind.docapi.repo.RiverDescriptionCommandRepository;
import com.fishfind.docapi.repo.RiverFishCommandRepository;
import com.fishfind.docapi.repo.RiverLinkCommandRepository;
import com.fishfind.docapi.repo.RiverQueryRepository;
import com.fishfind.docapi.repo.NewsCacheEvictor;
import com.fishfind.docapi.repo.NewsDocumentCache;
import com.fishfind.docapi.repo.NewsDocumentRepository;
import com.fishfind.docapi.repo.MySqlNewsDocumentRepository;
import com.fishfind.docapi.repo.MySqlNewsQueryRepository;
import com.fishfind.docapi.repo.NewsQueryCache;
import com.fishfind.docapi.repo.NewsQueryRepository;
import com.fishfind.docapi.repo.StationDocumentRepository;
import com.fishfind.docapi.repo.WaterbodyDocumentRepository;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.EnableScheduling;

import javax.sql.DataSource;

/**
 * SQL Server backing, active only under the {@code jdbc} Spring profile: one JDBC {@link DocumentStore}
 * per entity, each calling that entity's stored procedures / JSON function.
 *
 * <p>Bean names match {@link InMemoryStoreConfig} so services inject their store by the same qualifier
 * in either profile. Requires a configured datasource (see {@code application-jdbc.yml}) and the
 * per-entity DB objects; without the {@code jdbc} profile the service uses the in-memory backing and
 * never touches a database.
 */
@Configuration
@Profile("jdbc")
@EnableScheduling
public class JdbcStoreConfig {

    /**
     * The SQL Server {@link JdbcTemplate} — declared explicitly, and {@code @Primary}, because
     * Spring Boot will not create it for us here.
     *
     * <p>{@code JdbcTemplateAutoConfiguration} is {@code @ConditionalOnMissingBean(JdbcOperations.class)}.
     * {@link #mysqlNewsJdbcTemplate} registers a {@link JdbcTemplate} — which IS a
     * {@code JdbcOperations} — so the auto-configuration backs off <strong>entirely</strong> and no
     * SQL Server template is ever built. Every one of the thirteen beans below that injects a bare
     * {@code JdbcTemplate} then silently receives the MySQL one, and production sends T-SQL to MySQL:
     * between the news migration (2026-08-31) and 2026-09-02 that 500'd {@code /fish/search},
     * {@code /river/*} and {@code /region/regulation/*} with "check the manual that corresponds to
     * your MySQL server version". The SQL Server pool never even started.
     *
     * <p>This is the same hazard {@link #mysqlNewsJdbcTemplate} already documents one layer down for
     * {@code DataSource}, where it is dodged by keeping the {@link HikariDataSource} local. That trick
     * cannot work here — the news repositories genuinely need a {@code JdbcTemplate} bean to inject —
     * so instead the SQL Server one is declared and marked {@code @Primary}, making the by-type
     * injections unambiguous and independent of whether the auto-configuration runs.
     *
     * <p>{@code DocApiJdbcWiringTest.sqlServerRepositoriesGetTheSqlServerTemplateNotTheMysqlOne}
     * asserts the binding by pool name; it fails if this bean is removed.
     */
    @Bean
    @Primary
    public JdbcTemplate jdbcTemplate(DataSource dataSource) {
        return new JdbcTemplate(dataSource);
    }

    /**
     * A dedicated MySQL datasource/{@link JdbcTemplate} for the news read endpoints only (the
     * {@code news} table migrated to Winhost MySQL 2026-08-31 — see {@code envfish-db/mysql/}).
     * Deliberately <strong>not</strong> exposed as a {@code DataSource} bean: registering a second
     * {@link javax.sql.DataSource} bean would make Spring Boot's {@code DataSourceAutoConfiguration}
     * back off from creating the primary SQL Server datasource (its {@code @ConditionalOnMissingBean}
     * fires on the first {@code DataSource}-typed bean it finds, regardless of qualifier). Keeping the
     * {@link HikariDataSource} as a local inside this method — only the {@link JdbcTemplate} is
     * returned — sidesteps that entirely and leaves the existing SQL Server wiring untouched. Trade-off:
     * this pool isn't picked up by the Actuator {@code db} health indicator and isn't closed on
     * graceful shutdown, both acceptable for a small secondary read-only pool.
     */
    @Bean
    public JdbcTemplate mysqlNewsJdbcTemplate(
            @Value("${newsmysql.datasource.url}") String url,
            @Value("${newsmysql.datasource.username}") String username,
            @Value("${newsmysql.datasource.password}") String password) {
        HikariDataSource ds = new HikariDataSource();
        ds.setJdbcUrl(url);
        ds.setUsername(username);
        ds.setPassword(password);
        ds.setDriverClassName("com.mysql.cj.jdbc.Driver");
        ds.setPoolName("docapi-news-mysql-hikari");
        ds.setMaximumPoolSize(5);
        ds.setMinimumIdle(1);
        // Same time budget as the SQL Server pool in application-jdbc.yml, and for the same reason:
        // cproxy's 10s read timeout means anything slower than that reaches the caller as an opaque
        // 502. This pool sits on the SAME network path to the same provider, so it hits the same
        // intermittently-dropped TCP handshakes — moving news to MySQL did not escape that.
        ds.setConnectionTimeout(4000);   // > connectTimeout below, so the driver's error surfaces
        ds.setValidationTimeout(2000);   // must stay under connectionTimeout
        // Connector/J takes both of these in MILLISECONDS (unlike mssql-jdbc's loginTimeout, which is
        // seconds). connectTimeout bounds the TCP connect; socketTimeout is a last-resort guard on a
        // stalled read and is deliberately generous, not part of the budget.
        ds.addDataSourceProperty("connectTimeout", "3000");
        ds.addDataSourceProperty("socketTimeout", "30000");
        ds.setMaxLifetime(1740000); // 29 min
        return new JdbcTemplate(ds);
    }

    /**
     * The SQL-Server-backed news store, registered as its own bean <strong>on purpose</strong>:
     * Resilience4j applies {@code @Retry} / {@code @CircuitBreaker} by AOP, which Spring can only do to
     * beans it manages. Constructing this with {@code new} elsewhere would leave those annotations
     * silently inert — the SQL calls would lose their retry and breaker with no compile or startup
     * error. {@code DocApiJdbcWiringTest} asserts this bean really is an advised proxy. Still used
     * directly for {@code POST}/{@code PUT} (news CRUD writes haven't moved to MySQL).
     */
    @Bean
    public DocumentStore sqlServerNewsStore(JdbcTemplate jdbc) {
        return new NewsDocumentRepository(jdbc);
    }

    /**
     * {@code GET /api/v1/news/{guid}} reads through MySQL ({@code sp_news_doc_get}); writes delegate to
     * {@link #sqlServerNewsStore}. Its own bean (not constructed inline in {@link #newsStore}) for the
     * same AOP-proxying reason as {@link #sqlServerNewsStore}.
     */
    @Bean
    public DocumentStore jdbcNewsStore(
            @Qualifier("mysqlNewsJdbcTemplate") JdbcTemplate mysqlJdbc,
            @Qualifier("sqlServerNewsStore") DocumentStore sqlServerNewsStore) {
        return new MySqlNewsDocumentRepository(mysqlJdbc, sqlServerNewsStore);
    }

    /**
     * The news store services actually inject: {@link NewsDocumentCache} in front of
     * {@link #jdbcNewsStore}, so {@code GET /api/v1/news/{guid}} is served from the last-25 LRU and a
     * miss reads through (MySQL for the get, retry/breaker intact because the delegate is the proxied
     * bean).
     */
    @Bean
    public DocumentStore newsStore(@Qualifier("jdbcNewsStore") DocumentStore jdbcNewsStore) {
        return new NewsDocumentCache(jdbcNewsStore);
    }

    @Bean
    public DocumentStore waterbodyStore(JdbcTemplate jdbc) {
        return new WaterbodyDocumentRepository(jdbc);
    }

    @Bean
    public DocumentStore fishStore(JdbcTemplate jdbc) {
        return new FishDocumentRepository(jdbc);
    }

    /**
     * The SQL-backed fish query repository ({@code dbo.SearchFishList}), a bean in its own right so
     * Resilience4j can proxy it — see {@link #jdbcNewsStore} for why this matters. There is no cache in
     * front of it: species search terms are open-ended, so unlike {@code /news/list} there is nothing
     * fixed to cache.
     */
    @Bean
    public FishQueryRepository fishQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcFishQueryRepository(jdbc, objectMapper);
    }

    /**
     * The SQL-backed river query repository ({@code dbo.fn_river_unfished_json}), a bean in its own
     * right so Resilience4j can proxy it — see {@link #jdbcNewsStore} for why this matters. Not cached
     * (the result changes as fish get assigned), so just the one proxied bean per profile.
     */
    @Bean
    public RiverQueryRepository riverQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcRiverQueryRepository(jdbc, objectMapper);
    }

    /**
     * The SQL-backed river-fish command repository ({@code dbo.sp_lake_fish_upsert_batch}), a bean in
     * its own right so Resilience4j can proxy it — see {@link #jdbcNewsStore} for why this matters.
     * Separate from {@link #riverQueryRepository} because it writes, not reads.
     */
    @Bean
    public RiverFishCommandRepository riverFishCommandRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcRiverFishCommandRepository(jdbc, objectMapper);
    }

    /**
     * The SQL-backed river-description command repository ({@code dbo.sp_lake_description_update}),
     * a bean in its own right so Resilience4j can proxy it — see {@link #jdbcNewsStore} for why this
     * matters. Separate from {@link #riverQueryRepository} because it writes, not reads.
     */
    @Bean
    public RiverDescriptionCommandRepository riverDescriptionCommandRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcRiverDescriptionCommandRepository(jdbc, objectMapper);
    }

    /**
     * The SQL-backed river-link command repository ({@code dbo.sp_lake_source_update} /
     * {@code dbo.sp_lake_mouth_update}), a bean in its own right so Resilience4j can proxy it — see
     * {@link #jdbcNewsStore} for why this matters. Separate from {@link #riverQueryRepository} because
     * it writes, not reads.
     */
    @Bean
    public RiverLinkCommandRepository riverLinkCommandRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcRiverLinkCommandRepository(jdbc, objectMapper);
    }

    /**
     * The SQL-backed regulation query repository ({@code dbo.fn_lake_regulation_json} /
     * {@code dbo.fn_region_regulation_json}), a bean in its own right so Resilience4j can proxy it —
     * see {@link #jdbcNewsStore} for why this matters.
     */
    @Bean
    public RegulationQueryRepository regulationQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcRegulationQueryRepository(jdbc, objectMapper);
    }

    /**
     * The SQL-backed regulation command repository ({@code dbo.sp_regulation_upsert}), a bean in its
     * own right so Resilience4j can proxy it — see {@link #jdbcNewsStore} for why this matters.
     * Separate from {@link #regulationQueryRepository} because it writes, not reads.
     */
    @Bean
    public RegulationCommandRepository regulationCommandRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcRegulationCommandRepository(jdbc, objectMapper);
    }

    @Bean
    public DocumentStore stationStore(JdbcTemplate jdbc) {
        return new StationDocumentRepository(jdbc);
    }

    /**
     * The SQL-Server-backed news query repository, a bean in its own right so Resilience4j can proxy
     * it — see {@link #jdbcNewsStore} for why this matters. Still used directly for {@code /news/search},
     * {@code /news/export/{id}} and {@code /news/import} (not in the MySQL move).
     */
    @Bean
    public NewsQueryRepository sqlServerNewsQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcNewsQueryRepository(jdbc, objectMapper);
    }

    /**
     * {@code /news/list} and {@code /news/default} read through MySQL ({@code sp_news_list_json} /
     * {@code sp_news_default}); {@code search}/{@code exportNews}/{@code importNews} delegate to
     * {@link #sqlServerNewsQueryRepository}. Its own bean (not constructed inline) for the same
     * AOP-proxying reason as {@link #jdbcNewsStore}.
     */
    @Bean
    public NewsQueryRepository jdbcNewsQueryRepository(
            @Qualifier("mysqlNewsJdbcTemplate") JdbcTemplate mysqlJdbc,
            ObjectMapper objectMapper,
            @Qualifier("sqlServerNewsQueryRepository") NewsQueryRepository sqlServerNewsQueryRepository) {
        return new MySqlNewsQueryRepository(mysqlJdbc, objectMapper, sqlServerNewsQueryRepository);
    }

    /**
     * What {@code NewsController} injects: {@link NewsQueryCache} in front of
     * {@link #jdbcNewsQueryRepository}, serving {@code /news/list} and {@code /news/default} from
     * memory and reading through on a miss. {@code @Primary} because two beans now implement
     * {@link NewsQueryRepository} and the controller injects by type.
     */
    @Bean
    @Primary
    public NewsQueryRepository newsQueryRepository(
            @Qualifier("jdbcNewsQueryRepository") NewsQueryRepository jdbcNewsQueryRepository) {
        return new NewsQueryCache(jdbcNewsQueryRepository);
    }

    /**
     * Drives the once-a-day cache clear. Registered only here, because the caches themselves exist
     * only under the {@code jdbc} profile — the in-memory backing has nothing to evict.
     */
    @Bean
    public NewsCacheEvictor newsCacheEvictor(NewsQueryRepository newsQueryRepository,
                                             @Qualifier("newsStore") DocumentStore newsStore,
                                             JdbcTemplate jdbc) {
        return new NewsCacheEvictor((NewsQueryCache) newsQueryRepository, (NewsDocumentCache) newsStore, jdbc);
    }
}
