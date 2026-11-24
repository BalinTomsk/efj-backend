package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.RowMapper;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Collections;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** {@link JdbcNewsNearRepository}: the csnews-env read, and the SQL Server statement's binding and mapping. */
class NewsNearRepositoryTest {

    private final ObjectMapper om = new ObjectMapper();

    @SuppressWarnings("unchecked")
    private <T> void answer(JdbcTemplate jdbc, String sql, PreparedStatement ps, ResultSet rs) {
        when(jdbc.query(eq(sql), any(PreparedStatementSetter.class), any(RowMapper.class))).thenAnswer(inv -> {
            ((PreparedStatementSetter) inv.getArgument(1)).setValues(ps);
            return Collections.singletonList(((RowMapper<T>) inv.getArgument(2)).mapRow(rs, 0));
        });
    }

    @Test
    void taggedNewsComesFromCsNews() {
        CsNewsClient csnews = mock(CsNewsClient.class);
        when(csnews.get("/tagged?limit=2000")).thenReturn(om.createArrayNode().add(om.createObjectNode()
                .put("newsId", "n1").put("title", "A story").put("source", "src").put("stamp", "2026-11-14")
                .put("country", "CA").put("lakeId", "0c44dfc7-849c-20c3-9db6-f2c06fc97a1f")));

        List<NewsNearRepository.TaggedNews> rows =
                new JdbcNewsNearRepository(mock(JdbcTemplate.class), csnews, om).taggedNews(2000);

        assertThat(rows).containsExactly(new NewsNearRepository.TaggedNews(
                "n1", "A story", "src", "2026-11-14", "CA", "0c44dfc7-849c-20c3-9db6-f2c06fc97a1f"));
    }

    @Test
    void aMissingTaggedListIsUnavailableNotEmpty() {
        CsNewsClient csnews = mock(CsNewsClient.class);
        assertThatThrownBy(() -> new JdbcNewsNearRepository(mock(JdbcTemplate.class), csnews, om).taggedNews(10))
                .isInstanceOf(CsNewsUnavailableException.class);
    }

    @Test
    void lakesNearBindsTheListPointAndRadius() throws Exception {
        JdbcTemplate sqlServer = mock(JdbcTemplate.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);
        when(rs.getString(1)).thenReturn("[{\"lakeId\":\"A\",\"distanceKm\":3.1}]");
        answer(sqlServer, JdbcNewsNearRepository.NEAR_SQL, ps, rs);

        JsonNode near = new JdbcNewsNearRepository(sqlServer, mock(CsNewsClient.class), om)
                .lakesNear("[\"a\"]", 43.45, -80.49, 100);

        assertThat(near.get(0).get("distanceKm").asDouble()).isEqualTo(3.1);
        verify(ps).setString(1, "[\"a\"]");
        verify(ps).setDouble(2, 43.45);
        verify(ps).setDouble(3, -80.49);
        verify(ps).setDouble(4, 100);
    }

    @Test
    void aNullAnswerForAValidPointIsAnError() throws Exception {
        JdbcTemplate sqlServer = mock(JdbcTemplate.class);
        ResultSet rs = mock(ResultSet.class);
        answer(sqlServer, JdbcNewsNearRepository.NEAR_SQL, mock(PreparedStatement.class), rs);

        assertThatThrownBy(() -> new JdbcNewsNearRepository(sqlServer, mock(CsNewsClient.class), om)
                .lakesNear("[]", 1, 1, 10)).isInstanceOf(IllegalStateException.class);
    }
}
