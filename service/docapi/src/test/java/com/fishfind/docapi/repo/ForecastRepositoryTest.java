package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.RowMapper;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Types;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** {@link CachingForecastQueryRepository}. */
class ForecastRepositoryTest {

    private static final String FISH = "2cffb500-3e59-4120-9460-055856e9ac5c";
    private final ObjectMapper om = new ObjectMapper();

    @Test
    void cacheServesRepeatsUntilTheTtlAndNeverStoresAMiss() throws Exception {
        AtomicInteger calls = new AtomicInteger();
        JsonNode doc = om.readTree("{\"today\":64}");
        ForecastQueryRepository delegate = new InMemoryForecastQueryRepository() {
            @Override
            public JsonNode reasoning(int sid, String fishId, int day) {
                calls.incrementAndGet();
                return sid == 1 ? null : doc;
            }
        };
        AtomicLong now = new AtomicLong(1_000_000L);
        Clock clock = new Clock() {
            @Override public ZoneOffset getZone() { return ZoneOffset.UTC; }
            @Override public Clock withZone(java.time.ZoneId zone) { return this; }
            @Override public Instant instant() { return Instant.ofEpochMilli(now.get()); }
        };
        CachingForecastQueryRepository cache = new CachingForecastQueryRepository(delegate, clock);

        cache.reasoning(2, FISH, 0);
        cache.reasoning(2, FISH, 0);
        assertThat(calls.get()).isEqualTo(1);

        cache.reasoning(2, FISH, 1);                       // the day is part of the key
        assertThat(calls.get()).isEqualTo(2);

        cache.reasoning(1, FISH, 0);
        cache.reasoning(1, FISH, 0);                       // a miss is asked again
        assertThat(calls.get()).isEqualTo(4);
        assertThat(cache.size()).isEqualTo(2);

        now.addAndGet(CachingForecastQueryRepository.TTL_MILLIS + 1);
        cache.reasoning(2, FISH, 0);                       // expired
        assertThat(calls.get()).isEqualTo(5);
    }

    @Test
    void cacheIsBounded() {
        ForecastQueryRepository delegate = new InMemoryForecastQueryRepository() {
            @Override
            public JsonNode plot(int sid, String fishId) {
                return om.createObjectNode().put("sid", sid);
            }
        };
        CachingForecastQueryRepository cache = new CachingForecastQueryRepository(delegate);
        for (int i = 0; i < CachingForecastQueryRepository.MAX_ENTRIES + 50; i++) {
            cache.plot(i + 1, FISH);
        }
        assertThat(cache.size()).isEqualTo(CachingForecastQueryRepository.MAX_ENTRIES);
    }
}
