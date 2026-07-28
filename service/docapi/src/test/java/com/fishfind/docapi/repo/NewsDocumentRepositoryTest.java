package com.fishfind.docapi.repo;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.RowMapper;

import java.sql.ResultSet;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class NewsDocumentRepositoryTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final NewsDocumentRepository repository = new NewsDocumentRepository(jdbc);

    @Test
    void getDocumentReturnsTheScalarJsonAndUsesTheEntityFunction() throws Exception {
        when(jdbc.query(any(String.class), any(PreparedStatementSetter.class), any(RowMapper.class))).thenAnswer(invocation -> {
            @SuppressWarnings("unchecked")
            RowMapper<String> mapper = invocation.getArgument(2);
            ResultSet rs = mock(ResultSet.class);
            when(rs.getString(1)).thenReturn("{\"id\":7}");
            return List.of(mapper.mapRow(rs, 0));
        });

        String json = repository.getDocument("7");

        assertEquals("{\"id\":7}", json);
        verify(jdbc).query(
                eq("SELECT dbo.fn_news_doc(?)"),
                any(PreparedStatementSetter.class),
                any(RowMapper.class));
    }

    @Test
    void getDocumentReturnsNullWhenNoRow() {
        when(jdbc.query(any(String.class), any(PreparedStatementSetter.class), any(RowMapper.class)))
                .thenReturn(List.of());

        assertNull(repository.getDocument("missing"));
    }
}
