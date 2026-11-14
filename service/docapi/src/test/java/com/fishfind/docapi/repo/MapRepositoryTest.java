package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.RowMapper;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** {@link JdbcMapQueryRepository} binding, {@link CachingMapQueryRepository}, {@link InMemoryMapQueryRepository}. */
class MapRepositoryTest {

    private final ObjectMapper om = new ObjectMapper();

    @SuppressWarnings("unchecked")
    private void answer(JdbcTemplate jdbc, PreparedStatement ps, String column) throws Exception {
        ResultSet rs = mock(ResultSet.class);
        when(rs.getString(1)).thenReturn(column);
        when(jdbc.query(eq(JdbcMapQueryRepository.SHAPES_SQL), any(PreparedStatementSetter.class), any(RowMapper.class)))
                .thenAnswer(inv -> {
                    ((PreparedStatementSetter) inv.getArgument(1)).setValues(ps);
                    return java.util.Collections.singletonList(((RowMapper<String>) inv.getArgument(2)).mapRow(rs, 0));
                });
    }

    @Test
    void shapesBindsTheBoxZoomAndLimitInOrder() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        answer(jdbc, ps, "{\"type\":\"FeatureCollection\",\"truncated\":false,\"features\":[]}");

        JsonNode doc = new JdbcMapQueryRepository(jdbc, om).shapes(-114.6, 61.0, -113.8, 61.4, 10, 500);

        assertThat(doc.get("type").asText()).isEqualTo("FeatureCollection");
        verify(ps).setDouble(1, -114.6);
        verify(ps).setDouble(2, 61.0);
        verify(ps).setDouble(3, -113.8);
        verify(ps).setDouble(4, 61.4);
        verify(ps).setInt(5, 10);
        verify(ps).setInt(6, 500);
    }

    @Test
    void aNullDocumentForAValidatedBoxIsAnError() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        answer(jdbc, mock(PreparedStatement.class), null);

        assertThatThrownBy(() -> new JdbcMapQueryRepository(jdbc, om).shapes(-1, 1, 0, 2, 10, 500))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void cacheServesTheSameTileUntilItExpires() {
        AtomicInteger calls = new AtomicInteger();
        MapQueryRepository delegate = (w, s, e, n, z, l) -> {
            calls.incrementAndGet();
            return om.createObjectNode().put("zoom", z);
        };
        AtomicLong now = new AtomicLong(1_000_000L);
        Clock clock = new Clock() {
            @Override public ZoneId getZone() { return ZoneOffset.UTC; }
            @Override public Clock withZone(ZoneId zone) { return this; }
            @Override public Instant instant() { return Instant.ofEpochMilli(now.get()); }
        };
        CachingMapQueryRepository cache = new CachingMapQueryRepository(delegate, clock);

        cache.shapes(-1, 1, 0, 2, 10, 500);
        cache.shapes(-1, 1, 0, 2, 10, 500);
        cache.shapes(-1, 1, 0, 2, 11, 500);
        assertThat(calls.get()).isEqualTo(2);
        assertThat(cache.size()).isEqualTo(2);

        now.addAndGet(CachingMapQueryRepository.TTL_MILLIS + 1);
        cache.shapes(-1, 1, 0, 2, 10, 500);
        assertThat(calls.get()).isEqualTo(3);
    }

    @Test
    void withoutADatabaseEveryBoxIsEmpty() {
        JsonNode doc = new InMemoryMapQueryRepository(om).shapes(-1, 1, 0, 2, 10, 500);
        assertThat(doc.get("type").asText()).isEqualTo("FeatureCollection");
        assertThat(doc.get("bbox").size()).isEqualTo(4);
        assertThat(doc.get("features").isEmpty()).isTrue();
        assertThat(doc.get("truncated").asBoolean()).isFalse();
    }
}
