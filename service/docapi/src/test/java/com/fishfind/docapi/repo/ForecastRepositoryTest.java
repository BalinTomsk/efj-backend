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

/** {@link JdbcForecastQueryRepository} statements and binding, and {@link CachingForecastQueryRepository}. */
class ForecastRepositoryTest {

    private static final String FISH = "2cffb500-3e59-4120-9460-055856e9ac5c";
    private final ObjectMapper om = new ObjectMapper();

    @SuppressWarnings("unchecked")
    private <T> void answer(JdbcTemplate jdbc, String sql, PreparedStatement ps, String... columns) throws Exception {
        ResultSet rs = mock(ResultSet.class);
        for (int i = 0; i < columns.length; i++) {
            when(rs.getString(i + 1)).thenReturn(columns[i]);
        }
        when(jdbc.query(eq(sql), any(PreparedStatementSetter.class), any(RowMapper.class))).thenAnswer(inv -> {
            ((PreparedStatementSetter) inv.getArgument(1)).setValues(ps);
            return List.of(((RowMapper<T>) inv.getArgument(2)).mapRow(rs, 0));
        });
    }

    @Test
    void stationsBindsSixArgumentsAndANullCountry() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        answer(jdbc, JdbcForecastQueryRepository.STATIONS_SQL, ps, "{\"total\":0,\"stations\":[]}");

        JsonNode doc = new JdbcForecastQueryRepository(jdbc, om).stations(FISH, 43.46, -80.49, 100, null, 50);

        assertThat(doc.get("total").asInt()).isZero();
        verify(ps).setString(1, FISH);
        verify(ps).setDouble(2, 43.46);
        verify(ps).setDouble(3, -80.49);
        verify(ps).setDouble(4, 100);
        verify(ps).setNull(5, Types.CHAR);
        verify(ps).setInt(6, 50);
    }

    @Test
    void plotNestsTheThreeColumnsAndBindsSidAndFishTwice() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        answer(jdbc, JdbcForecastQueryRepository.PLOT_SQL, ps,
                "{\"place\":\"X\",\"date\":[\"Fri 13\"]}", "[{\"dt\":\"2026-11-13\"}]", "[{\"probability\":64}]");

        JsonNode doc = new JdbcForecastQueryRepository(jdbc, om).plot(266353, FISH);

        assertThat(doc.get("sid").asInt()).isEqualTo(266353);
        assertThat(doc.at("/plot/place").asText()).isEqualTo("X");
        assertThat(doc.at("/calendar/0/dt").asText()).isEqualTo("2026-11-13");
        assertThat(doc.at("/week/0/probability").asInt()).isEqualTo(64);
        verify(ps).setInt(1, 266353);
        verify(ps).setString(2, FISH);
        verify(ps).setInt(3, 266353);
        verify(ps).setInt(4, 266353);
        verify(ps).setString(5, FISH);
    }

    @Test
    void plotWithoutAWeekIsNotFound() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        answer(jdbc, JdbcForecastQueryRepository.PLOT_SQL, mock(PreparedStatement.class),
                "{\"place\":\"unknown\"}", "[]", null);

        assertThat(new JdbcForecastQueryRepository(jdbc, om).plot(1, FISH)).isNull();
    }

    @Test
    void reasoningBindsTheDayOffset() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        answer(jdbc, JdbcForecastQueryRepository.REASONING_SQL, ps, "{\"today\":64}");

        JsonNode doc = new JdbcForecastQueryRepository(jdbc, om).reasoning(266353, FISH, 3);

        assertThat(doc.get("today").asInt()).isEqualTo(64);
        verify(ps).setInt(3, 3);
        assertThat(JdbcForecastQueryRepository.REASONING_SQL).contains("DATEADD(DAY, ?, SYSUTCDATETIME())");
    }

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
