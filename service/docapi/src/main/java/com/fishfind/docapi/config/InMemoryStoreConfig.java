package com.fishfind.docapi.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.DocumentStore;
import com.fishfind.docapi.repo.InMemoryDocumentStore;
import com.fishfind.docapi.repo.InMemoryNewsQueryRepository;
import com.fishfind.docapi.repo.NewsQueryRepository;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

/**
 * Default backing (active unless the {@code jdbc} profile is set): one in-memory {@link DocumentStore}
 * per entity, so the service runs end-to-end with <strong>no database connection</strong>.
 *
 * <p>The bean names ({@code newsStore}, {@code waterbodyStore}, {@code fishStore},
 * {@code stationStore}) match those produced under the {@code jdbc} profile, so each service injects
 * its store by the same qualifier regardless of which backing is active.
 */
@Configuration
@Profile("!jdbc")
public class InMemoryStoreConfig {

    @Bean
    public DocumentStore newsStore() {
        return new InMemoryDocumentStore(DocumentType.NEWS);
    }

    @Bean
    public DocumentStore waterbodyStore() {
        return new InMemoryDocumentStore(DocumentType.WATERBODY);
    }

    @Bean
    public DocumentStore fishStore() {
        return new InMemoryDocumentStore(DocumentType.FISH);
    }

    @Bean
    public DocumentStore stationStore() {
        return new InMemoryDocumentStore(DocumentType.STATION);
    }

    @Bean
    public NewsQueryRepository newsQueryRepository(ObjectMapper objectMapper) {
        return new InMemoryNewsQueryRepository(objectMapper);
    }
}
