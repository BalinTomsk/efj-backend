package com.fishfind.docapi.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.DocumentStore;
import com.fishfind.docapi.repo.FollowRepository;
import com.fishfind.docapi.repo.JdbcFollowRepository;
import com.fishfind.docapi.repo.JdbcSpotRepository;
import com.fishfind.docapi.repo.SpotRepository;
import com.fishfind.docapi.repo.FishDocumentRepository;
import com.fishfind.docapi.repo.FishQueryRepository;
import com.fishfind.docapi.repo.JdbcFishQueryRepository;
import com.fishfind.docapi.repo.JdbcRiverDescriptionCommandRepository;
import com.fishfind.docapi.repo.CatchLogCommandRepository;
import com.fishfind.docapi.repo.JdbcCatchLogCommandRepository;
import com.fishfind.docapi.repo.JdbcRiverFishCommandRepository;
import com.fishfind.docapi.repo.JdbcRiverLinkCommandRepository;
import com.fishfind.docapi.repo.JdbcRiverQueryRepository;
import com.fishfind.docapi.repo.CachingForecastQueryRepository;
import com.fishfind.docapi.repo.ForecastQueryRepository;
import com.fishfind.docapi.repo.CachingMapQueryRepository;
import com.fishfind.docapi.repo.JdbcMapQueryRepository;
import com.fishfind.docapi.repo.JdbcNewsNearRepository;
import com.fishfind.docapi.repo.NewsNearRepository;
import com.fishfind.docapi.repo.MapQueryRepository;
import com.fishfind.docapi.repo.JdbcRegulationCommandRepository;
import com.fishfind.docapi.repo.JdbcRegulationQueryRepository;
import com.fishfind.docapi.repo.RegulationCommandRepository;
import com.fishfind.docapi.repo.RegulationQueryRepository;
import com.fishfind.docapi.repo.RiverDescriptionCommandRepository;
import com.fishfind.docapi.repo.RiverFishCommandRepository;
import com.fishfind.docapi.repo.RiverLinkCommandRepository;
import com.fishfind.docapi.repo.RiverQueryRepository;
import com.fishfind.docapi.repo.NewsAdminCommandRepository;
import com.fishfind.docapi.repo.NewsCacheEvictor;
import com.fishfind.docapi.repo.NewsDocumentCache;
import com.fishfind.docapi.repo.CsNewsClient;
import com.fishfind.docapi.repo.EnvClient;
import com.fishfind.docapi.repo.EnvRiverQueryRepository;
import com.fishfind.docapi.repo.HttpForecastQueryRepository;
import com.fishfind.docapi.repo.HttpNewsAdminCommandRepository;
import com.fishfind.docapi.repo.HttpNewsDocumentRepository;
import com.fishfind.docapi.repo.HttpNewsQueryRepository;
import com.fishfind.docapi.repo.HttpNewsWriteRepository;
import com.fishfind.docapi.repo.NewsWriteRepository;
import com.fishfind.docapi.repo.NewsQueryCache;
import com.fishfind.docapi.repo.NewsQueryRepository;
import com.fishfind.docapi.repo.StationDocumentRepository;
import com.fishfind.docapi.repo.WaterbodyDocumentRepository;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.EnableScheduling;

import javax.sql.DataSource;
import java.time.Duration;

/**
 * SQL Server backing, active only under the {@code jdbc} Spring profile: one JDBC {@link DocumentStore}
 * per entity, each calling that entity's stored procedures / JSON function. News is the exception: since
 * 1.44.0 docapi has <strong>no MySQL access</strong>; every news bean calls csnews-env over HTTP
 * ({@link CsNewsClient}, {@code CSNEWS_URL}) and docapi keeps only the caches in front of it.
 *
 * <p>Bean names match {@link InMemoryStoreConfig} so services inject their store by the same qualifier
 * in either profile. Requires a configured datasource (see {@code application-jdbc.yml}) and the
 * per-entity DB objects; without the {@code jdbc} profile the service uses the in-memory backing and
 * never touches a database.
 */
@Configuration
@Profile("jdbc")
@EnableScheduling
@EnableConfigurationProperties(NewsCacheProperties.class)
public class JdbcStoreConfig {

    /**
     * The SQL Server {@link JdbcTemplate}, declared explicitly and {@code @Primary}. Until 1.44.0 a second
     * (MySQL news) {@code JdbcTemplate} bean made Spring Boot's auto-configured one back off entirely, and
     * T-SQL went to MySQL (2026-09-02 incident). That bean is gone, but the explicit declaration stays so a
     * future second template can never silently take over the by-type injections again.
     * {@code DocApiJdbcWiringTest} asserts the binding.
     */
    @Bean
    @Primary
    public JdbcTemplate jdbcTemplate(DataSource dataSource) {
        return new JdbcTemplate(dataSource);
    }

    /**
     * The news database's only door (1.44.0): csnews-env's internal news data API ({@code CSNEWS_URL}, e.g.
     * {@code http://<csnode-vpc>:8091}). Timeouts fit cproxy's 10 s read budget. Its breaker is
     * {@code csnewsBreaker} (application.yml) -- deliberately not {@code sqlBreaker}, so a news outage never
     * fails the SQL Server endpoints.
     */
    @Bean
    public CsNewsClient csNewsClient(
            @Value("${csnews.url}") String url,
            @Value("${csnews.connect-timeout:2s}") Duration connectTimeout,
            @Value("${csnews.request-timeout:8s}") Duration requestTimeout,
            ObjectMapper objectMapper,
            CircuitBreakerRegistry breakers) {
        return new CsNewsClient(url, connectTimeout, requestTimeout, objectMapper,
                breakers.circuitBreaker("csnewsBreaker"));
    }

    /**
     * {@code GET /api/v1/news/{guid}}: csnews-env {@code /doc/{id}}. Read-only: news writes go through
     * {@link #newsWriteRepository}. The bean name is kept so {@link #newsStore} and the tests are unchanged.
     */
    @Bean
    public DocumentStore jdbcNewsStore(CsNewsClient csNewsClient) {
        return new HttpNewsDocumentRepository(csNewsClient);
    }

    /**
     * {@code POST /api/v1/news}, {@code PUT /api/v1/news/{id}} and {@code POST /api/v1/news/import}: csnews-env
     * {@code POST /doc} / {@code PUT /doc/{id}}. Not cached (a write path -- {@code NewsDocumentService} clears
     * the read caches after each write).
     */
    @Bean
    public NewsWriteRepository newsWriteRepository(CsNewsClient csNewsClient) {
        return new HttpNewsWriteRepository(csNewsClient);
    }

    /**
     * The news store services actually inject: {@link NewsDocumentCache} in front of
     * {@link #jdbcNewsStore}, so {@code GET /api/v1/news/{guid}} is served from the last-25 LRU and a
     * miss reads through to csnews-env.
     */
    @Bean
    public DocumentStore newsStore(
            @Qualifier("jdbcNewsStore") DocumentStore jdbcNewsStore, NewsCacheProperties cacheProperties) {
        return new NewsDocumentCache(jdbcNewsStore, cacheProperties);
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
     * Resilience4j can proxy it — Resilience4j advises only Spring-managed beans. There is no cache in
     * front of it: species search terms are open-ended, so unlike {@code /news/list} there is nothing
     * fixed to cache.
     */
    @Bean
    public FishQueryRepository fishQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcFishQueryRepository(jdbc, objectMapper);
    }

    /**
     * The SQL-backed river query repository ({@code dbo.fn_river_unfished_json}), a bean in its own
     * right so Resilience4j can proxy it — Resilience4j advises only Spring-managed beans. Not cached
     * (the result changes as fish get assigned), so just the one proxied bean per profile.
     */
    @Bean
    public RiverQueryRepository jdbcRiverQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcRiverQueryRepository(jdbc, objectMapper);
    }

    /**
     * The water and weather data's only door (1.45.0, env_service plan step 6c): env_service's read API ({@code ENV_URL},
     * e.g. {@code http://<csnode-vpc-address>:8092}, no trailing path), behind its own {@code envBreaker} -- never
     * {@code sqlBreaker}, so an env_service outage does not fail the SQL Server endpoints.
     */
    @Bean
    public EnvClient envClient(
            @Value("${env.url}") String url,
            @Value("${env.connect-timeout:2s}") Duration connectTimeout,
            @Value("${env.request-timeout:8s}") Duration requestTimeout,
            ObjectMapper objectMapper, CircuitBreakerRegistry breakers) {
        return new EnvClient(url, connectTimeout, requestTimeout, objectMapper, breakers.circuitBreaker("envBreaker"));
    }

    /**
     * What {@code RiverController} injects (1.45.0): the Weather tab from env_service, every other river query from
     * {@link #jdbcRiverQueryRepository} (the proxied bean, so its retry and breaker still apply). {@code @Primary}
     * because two beans implement the interface.
     */
    @Bean
    @Primary
    public RiverQueryRepository riverQueryRepository(
            @Qualifier("jdbcRiverQueryRepository") RiverQueryRepository jdbcRiverQueryRepository,
            JdbcTemplate jdbc, EnvClient envClient, ObjectMapper objectMapper) {
        return new EnvRiverQueryRepository(jdbcRiverQueryRepository, jdbc, envClient, objectMapper);
    }

    /**
     * The forecast repository ({@code /api/v1/forecast/*}): env_service's documents since 1.45.0. Its SQL Server
     * predecessor (JdbcForecastQueryRepository, 1.31.0) was removed in 1.45.1.
     */
    @Bean
    public ForecastQueryRepository jdbcForecastQueryRepository(EnvClient envClient) {
        // 1.45.0: the forecast documents come from env_service (its bodies are ours); the bean keeps its name so the
        // caching bean below is unchanged.
        return new HttpForecastQueryRepository(envClient);
    }

    /**
     * What {@code ForecastController} injects: {@link CachingForecastQueryRepository} (5-minute LRU per endpoint)
     * in front of {@link #jdbcForecastQueryRepository}. {@code @Primary} because two beans implement the
     * interface and the controller injects by type.
     */
    @Bean
    @Primary
    public ForecastQueryRepository forecastQueryRepository(
            @Qualifier("jdbcForecastQueryRepository") ForecastQueryRepository jdbcForecastQueryRepository) {
        return new CachingForecastQueryRepository(jdbcForecastQueryRepository);
    }

    /**
     * The SQL-backed map repository (1.33.0, {@code /api/v1/map/shapes}), its own bean so Resilience4j can proxy it
     * (Resilience4j advises only Spring-managed beans).
     */
    @Bean
    public MapQueryRepository jdbcMapQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcMapQueryRepository(jdbc, objectMapper);
    }

    /**
     * {@code /news/near} (1.34.0): tagged stories from csnews-env, distances from SQL Server
     * ({@code fn_lakes_near_json}). Its own bean so Resilience4j can proxy the SQL Server read.
     */
    @Bean
    public NewsNearRepository newsNearRepository(JdbcTemplate jdbc, CsNewsClient csNewsClient,
                                                 ObjectMapper objectMapper) {
        return new JdbcNewsNearRepository(jdbc, csNewsClient, objectMapper);
    }

    /** What {@code MapController} injects: {@link CachingMapQueryRepository} (30-minute LRU) in front of the JDBC bean. */
    @Bean
    @Primary
    public MapQueryRepository mapQueryRepository(
            @Qualifier("jdbcMapQueryRepository") MapQueryRepository jdbcMapQueryRepository) {
        return new CachingMapQueryRepository(jdbcMapQueryRepository);
    }

    /**
     * The SQL-backed river-fish command repository ({@code dbo.sp_lake_fish_upsert_batch}), a bean in
     * its own right so Resilience4j can proxy it — Resilience4j advises only Spring-managed beans.
     * Separate from {@link #riverQueryRepository} because it writes, not reads.
     */
    @Bean
    public RiverFishCommandRepository riverFishCommandRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcRiverFishCommandRepository(jdbc, objectMapper);
    }

    /**
     * The SQL-backed catch-log command repository ({@code dbo.sp_add_catch_memo} / {@code sp_add_catch_memo_photo})
     * behind the MCP write tools, a bean in its own right so Resilience4j can proxy it.
     */
    @Bean
    public CatchLogCommandRepository catchLogCommandRepository(JdbcTemplate jdbc, ObjectMapper objectMapper, EnvClient envClient) {
        return new JdbcCatchLogCommandRepository(jdbc, objectMapper, envClient);
    }

    /** Saved spots (1.37.0, {@code dbo.user_spot}), a bean so Resilience4j can proxy it. */
    @Bean
    public SpotRepository spotRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcSpotRepository(jdbc, objectMapper);
    }

    /** Follows (1.39.0, {@code dbo.user_follow}), a bean so Resilience4j can proxy it. */
    @Bean
    public FollowRepository followRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcFollowRepository(jdbc, objectMapper);
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
     * Resilience4j advises only Spring-managed beans.
     */
    @Bean
    public RegulationQueryRepository regulationQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcRegulationQueryRepository(jdbc, objectMapper);
    }

    /**
     * The SQL-backed regulation command repository ({@code dbo.sp_regulation_upsert}), a bean in its
     * own right so Resilience4j can proxy it — Resilience4j advises only Spring-managed beans.
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
     * Every news query -- list, home page, photo, search, lake/fish panels and the interchange export --
     * from csnews-env. The bean name is kept; {@link #newsQueryRepository} caches in front of it.
     */
    @Bean
    public NewsQueryRepository jdbcNewsQueryRepository(CsNewsClient csNewsClient) {
        return new HttpNewsQueryRepository(csNewsClient);
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
            @Qualifier("jdbcNewsQueryRepository") NewsQueryRepository jdbcNewsQueryRepository,
            NewsCacheProperties cacheProperties) {
        return new NewsQueryCache(jdbcNewsQueryRepository, cacheProperties);
    }

    /**
     * News-admin writes (draft/publish/photo) for {@code Editor/AddNews.aspx}: csnews-env {@code /admin/*}.
     * Not cached (a write path).
     */
    @Bean
    public NewsAdminCommandRepository newsAdminCommandRepository(CsNewsClient csNewsClient) {
        return new HttpNewsAdminCommandRepository(csNewsClient);
    }

    /**
     * Drives the once-a-day cache clear, skipped while csnews-env (or its MySQL) is unreachable. Registered only
     * here, because the caches exist only under the {@code jdbc} profile.
     */
    @Bean
    public NewsCacheEvictor newsCacheEvictor(NewsQueryRepository newsQueryRepository,
                                             @Qualifier("newsStore") DocumentStore newsStore,
                                             CsNewsClient csNewsClient) {
        return new NewsCacheEvictor((NewsQueryCache) newsQueryRepository, (NewsDocumentCache) newsStore,
                csNewsClient::reachable);
    }
}
