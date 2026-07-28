package com.fishfind.docapi.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.DocumentStore;
import com.fishfind.docapi.repo.FishDocumentRepository;
import com.fishfind.docapi.repo.JdbcNewsQueryRepository;
import com.fishfind.docapi.repo.NewsCacheEvictor;
import com.fishfind.docapi.repo.NewsDocumentCache;
import com.fishfind.docapi.repo.NewsDocumentRepository;
import com.fishfind.docapi.repo.NewsQueryCache;
import com.fishfind.docapi.repo.NewsQueryRepository;
import com.fishfind.docapi.repo.StationDocumentRepository;
import com.fishfind.docapi.repo.WaterbodyDocumentRepository;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.EnableScheduling;

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
     * The SQL-backed news store, registered as its own bean <strong>on purpose</strong>: Resilience4j
     * applies {@code @Retry} / {@code @CircuitBreaker} by AOP, which Spring can only do to beans it
     * manages. Constructing this with {@code new} inside {@link #newsStore} would leave those
     * annotations silently inert — the SQL calls would lose their retry and breaker with no compile or
     * startup error. {@code DocApiJdbcWiringTest} asserts this bean really is an advised proxy.
     */
    @Bean
    public DocumentStore jdbcNewsStore(JdbcTemplate jdbc) {
        return new NewsDocumentRepository(jdbc);
    }

    /**
     * The news store services actually inject: {@link NewsDocumentCache} in front of
     * {@link #jdbcNewsStore}, so {@code GET /api/v1/news/{guid}} is served from the last-25 LRU and a
     * miss reads through to SQL (retry/breaker intact, because the delegate is the proxied bean).
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

    @Bean
    public DocumentStore stationStore(JdbcTemplate jdbc) {
        return new StationDocumentRepository(jdbc);
    }

    /**
     * The SQL-backed news query repository, a bean in its own right so Resilience4j can proxy it —
     * see {@link #jdbcNewsStore} for why this matters.
     */
    @Bean
    public NewsQueryRepository jdbcNewsQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        return new JdbcNewsQueryRepository(jdbc, objectMapper);
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
