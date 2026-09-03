package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.RowMapper;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Collections;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * SQL-Server-side news query repository. Covers the reference-name lookup that
 * {@link MySqlNewsQueryRepository} calls to put lake and fish names back on {@code /news/default}
 * (the MySQL database backing the news reads has only the {@code news} table).
 */
class JdbcNewsQueryRepositoryTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final JdbcNewsQueryRepository repository = new JdbcNewsQueryRepository(jdbc, objectMapper);

    @Test
    void resolveRefNamesCallsTheLookupFunctionWithJsonArrayArguments() throws Exception {
        stubScalar("{\"lakes\":[{\"id\":\"lake-1\",\"name\":\"Lake Manitou\"}],"
                + "\"fishes\":[{\"id\":\"fish-1\",\"name\":\"Muskellunge\",\"latin\":\"Esox masquinongy\"}]}");

        JsonNode result = repository.resolveRefNames(List.of("lake-1"), List.of("fish-1"));

        assertEquals("Lake Manitou", result.get("lakes").get(0).get("name").asText());
        assertEquals("Muskellunge", result.get("fishes").get(0).get("name").asText());

        ArgumentCaptor<PreparedStatementSetter> binder = ArgumentCaptor.forClass(PreparedStatementSetter.class);
        verify(jdbc).query(eq("SELECT dbo.fn_news_ref_names_json(?, ?)"), binder.capture(), any(RowMapper.class));

        // Both arguments must go over as JSON *arrays* -- that is what makes the function answer 1:1
        // in the order asked, and it is why an id carrying a quote cannot reshape the argument.
        PreparedStatement ps = mock(PreparedStatement.class);
        binder.getValue().setValues(ps);
        verify(ps).setString(1, "[\"lake-1\"]");
        verify(ps).setString(2, "[\"fish-1\"]");
    }

    @Test
    void resolveRefNamesSendsEmptyArraysForNullOrEmptyIdLists() throws Exception {
        stubScalar("{\"lakes\":[],\"fishes\":[]}");

        repository.resolveRefNames(null, List.of());

        ArgumentCaptor<PreparedStatementSetter> binder = ArgumentCaptor.forClass(PreparedStatementSetter.class);
        verify(jdbc).query(any(String.class), binder.capture(), any(RowMapper.class));

        PreparedStatement ps = mock(PreparedStatement.class);
        binder.getValue().setValues(ps);
        verify(ps).setString(1, "[]");
        verify(ps).setString(2, "[]");
    }

    /** A NULL/blank scalar must still parse into something a caller can read, not blow up. */
    @Test
    void resolveRefNamesReturnsAnEmptyObjectWhenTheFunctionYieldsNothing() {
        stubScalar(null);

        JsonNode result = repository.resolveRefNames(List.of("lake-1"), List.of());

        assertTrue(result.isObject());
        assertTrue(result.path("lakes").isMissingNode() || result.path("lakes").isEmpty());
    }

    /** Makes the next {@code jdbc.query(sql, binder, rowMapper)} yield the given single scalar. */
    private void stubScalar(String scalar) {
        when(jdbc.query(any(String.class), any(PreparedStatementSetter.class), any(RowMapper.class)))
                .thenAnswer(invocation -> {
                    @SuppressWarnings("unchecked")
                    RowMapper<String> mapper = invocation.getArgument(2);
                    ResultSet rs = mock(ResultSet.class);
                    when(rs.getString(1)).thenReturn(scalar);
                    // singletonList, not List.of -- the "function returned NULL" case needs a null element.
                    return Collections.singletonList(mapper.mapRow(rs, 0));
                });
    }
}
