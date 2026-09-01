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
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class MySqlNewsDocumentRepositoryTest {

    private final JdbcTemplate mysqlJdbc = mock(JdbcTemplate.class);
    private final DocumentStore sqlServerDelegate = mock(DocumentStore.class);
    private final MySqlNewsDocumentRepository repository =
            new MySqlNewsDocumentRepository(mysqlJdbc, sqlServerDelegate);

    @Test
    void getDocumentReadsFromMySqlAndUsesTheStoredProcedure() throws Exception {
        when(mysqlJdbc.query(any(String.class), any(PreparedStatementSetter.class), any(RowMapper.class)))
                .thenAnswer(invocation -> {
                    @SuppressWarnings("unchecked")
                    RowMapper<String> mapper = invocation.getArgument(2);
                    ResultSet rs = mock(ResultSet.class);
                    when(rs.getString(1)).thenReturn("{\"news_id\":\"7\"}");
                    return List.of(mapper.mapRow(rs, 0));
                });

        String json = repository.getDocument("7");

        assertEquals("{\"news_id\":\"7\"}", json);
        verify(mysqlJdbc).query(
                eq("CALL sp_news_doc_get(?)"),
                any(PreparedStatementSetter.class),
                any(RowMapper.class));
        verifyNoInteractions(sqlServerDelegate);
    }

    @Test
    void getDocumentReturnsNullWhenNoRow() {
        when(mysqlJdbc.query(any(String.class), any(PreparedStatementSetter.class), any(RowMapper.class)))
                .thenReturn(List.of());

        assertNull(repository.getDocument("missing"));
    }

    @Test
    void addDocumentDelegatesToTheSqlServerStore() {
        when(sqlServerDelegate.addDocument("{\"title\":\"x\"}")).thenReturn("new-id");

        assertEquals("new-id", repository.addDocument("{\"title\":\"x\"}"));
        verify(sqlServerDelegate).addDocument("{\"title\":\"x\"}");
        verifyNoInteractions(mysqlJdbc);
    }

    @Test
    void updateDocumentDelegatesToTheSqlServerStore() {
        when(sqlServerDelegate.updateDocument("7", "{\"title\":\"x\"}")).thenReturn("7");

        assertEquals("7", repository.updateDocument("7", "{\"title\":\"x\"}"));
        verify(sqlServerDelegate).updateDocument("7", "{\"title\":\"x\"}");
        verifyNoInteractions(mysqlJdbc);
    }
}
