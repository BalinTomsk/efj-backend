package com.fishfind.docapi.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.boot.context.properties.source.ConfigurationPropertySource;
import org.springframework.boot.context.properties.source.MapConfigurationPropertySource;
import org.springframework.core.env.StandardEnvironment;
import org.springframework.core.env.SystemEnvironmentPropertySource;

/**
 * The cache bounds moved from {@code static final} constants to {@code docapi.cache.*} on 2026-09-18.
 * A constant cannot be misspelled into silence; a property key can — bind the wrong name and the field
 * keeps its default while the service looks configured. These two tests are what makes that loud.
 */
class NewsCachePropertiesTest {

    @Test
    void defaultsReproduceTheConstantsTheyReplaced() {
        NewsCacheProperties properties = new NewsCacheProperties();

        assertThat(properties.getNews().getDocument()).as("was NewsDocumentCache.MAX_DOCUMENTS").isEqualTo(25);
        assertThat(properties.getNews().getMiss()).as("was NewsDocumentCache.MAX_MISSES").isEqualTo(500);
        assertThat(properties.getNews().getList()).as("was NewsQueryCache.OTHER_ENTRIES").isEqualTo(100);
        assertThat(properties.getNews().getExport()).as("was NewsQueryCache.LRU_ENTRIES").isEqualTo(25);
        assertThat(properties.getNews().getSearch()).as("was NewsQueryCache.LRU_ENTRIES").isEqualTo(25);
        assertThat(properties.getNews().getPhoto()).as("was NewsQueryCache.LRU_ENTRIES").isEqualTo(25);
        assertThat(properties.getFish()).as("was NewsQueryCache.LRU_ENTRIES").isEqualTo(25);
        assertThat(properties.getWaterBody()).as("was NewsQueryCache.LRU_ENTRIES").isEqualTo(25);
    }

    /**
     * Every key is given a distinct value, so a field bound to the wrong key fails rather than
     * coincidentally matching. {@code water-body} is the one genuinely at risk: it is the only kebab-cased
     * key here, and relaxed binding to {@code waterBody} is the thing that would quietly stop working.
     */
    @Test
    void everyKeyBindsToItsOwnFieldIncludingKebabCasedWaterBody() {
        Map<String, Object> yaml = new HashMap<>();
        yaml.put("docapi.cache.news.document", 1);
        yaml.put("docapi.cache.news.miss", 2);
        yaml.put("docapi.cache.news.list", 3);
        yaml.put("docapi.cache.news.export", 4);
        yaml.put("docapi.cache.news.search", 5);
        yaml.put("docapi.cache.news.photo", 6);
        yaml.put("docapi.cache.fish", 7);
        yaml.put("docapi.cache.water-body", 8);
        ConfigurationPropertySource source = new MapConfigurationPropertySource(yaml);

        NewsCacheProperties bound =
                new Binder(source).bind("docapi.cache", NewsCacheProperties.class).get();

        assertThat(bound.getNews().getDocument()).isEqualTo(1);
        assertThat(bound.getNews().getMiss()).isEqualTo(2);
        assertThat(bound.getNews().getList()).isEqualTo(3);
        assertThat(bound.getNews().getExport()).isEqualTo(4);
        assertThat(bound.getNews().getSearch()).isEqualTo(5);
        assertThat(bound.getNews().getPhoto()).isEqualTo(6);
        assertThat(bound.getFish()).isEqualTo(7);
        assertThat(bound.getWaterBody()).isEqualTo(8);
    }

    /**
     * {@code docs/do-update.md} Step 10z tells an operator to lower these with {@code docker run -e} when
     * docapi is pressuring heap, naming the variables below. That is a promise about relaxed binding —
     * in particular that {@code water-body} is reached as {@code DOCAPI_CACHE_WATERBODY}, hyphen removed
     * rather than turned into an underscore. Asserted here so the runbook cannot quietly become wrong.
     */
    @Test
    void theEnvironmentVariableNamesGivenInTheRunbookBind() {
        Map<String, Object> env = new HashMap<>();
        env.put("DOCAPI_CACHE_NEWS_EXPORT", "9");
        env.put("DOCAPI_CACHE_NEWS_PHOTO", "8");
        env.put("DOCAPI_CACHE_FISH", "7");
        env.put("DOCAPI_CACHE_WATERBODY", "6");
        // The source must carry the canonical name: Spring only applies env-var name mapping
        // (DOCAPI_CACHE_NEWS_EXPORT -> docapi.cache.news.export) to a source called "systemEnvironment".
        StandardEnvironment environment = new StandardEnvironment();
        environment.getPropertySources().replace(
                StandardEnvironment.SYSTEM_ENVIRONMENT_PROPERTY_SOURCE_NAME,
                new SystemEnvironmentPropertySource(
                        StandardEnvironment.SYSTEM_ENVIRONMENT_PROPERTY_SOURCE_NAME, env));

        NewsCacheProperties bound =
                Binder.get(environment).bind("docapi.cache", NewsCacheProperties.class).get();

        assertThat(bound.getNews().getExport()).isEqualTo(9);
        assertThat(bound.getNews().getPhoto()).isEqualTo(8);
        assertThat(bound.getFish()).isEqualTo(7);
        assertThat(bound.getWaterBody()).isEqualTo(6);
    }
}
