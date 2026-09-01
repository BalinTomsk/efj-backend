package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.ResultSetExtractor;
import org.springframework.jdbc.core.RowMapper;

import java.sql.ResultSet;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class MySqlNewsQueryRepositoryTest {

    private final JdbcTemplate mysqlJdbc = mock(JdbcTemplate.class);
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final NewsQueryRepository sqlServerDelegate = mock(NewsQueryRepository.class);
    private final MySqlNewsQueryRepository repository =
            new MySqlNewsQueryRepository(mysqlJdbc, objectMapper, sqlServerDelegate);

    @Test
    void listReadsFromMySqlAndUsesTheStoredProcedure() throws Exception {
        when(mysqlJdbc.query(any(String.class), any(PreparedStatementSetter.class), any(ResultSetExtractor.class)))
                .thenAnswer(invocation -> {
                    @SuppressWarnings("unchecked")
                    ResultSetExtractor<NewsListPage> extractor = invocation.getArgument(2);
                    ResultSet rs = mock(ResultSet.class);
                    when(rs.next()).thenReturn(true, false);
                    when(rs.getLong("total")).thenReturn(1L);
                    when(rs.getLong("rn")).thenReturn(1L);
                    when(rs.getString("news_id")).thenReturn("n1");
                    when(rs.getString("title")).thenReturn("Headline");
                    when(rs.getString("source")).thenReturn("Source");
                    when(rs.getString("stamp")).thenReturn("2026-08-31");
                    when(rs.getString("flag")).thenReturn("CA");
                    when(rs.getBoolean("has_photo")).thenReturn(true);
                    when(rs.getInt("block_ord")).thenReturn(0);
                    return extractor.extractData(rs);
                });

        NewsListPage page = repository.list("CA", 0, 25);

        assertEquals(1, page.items().size());
        assertEquals(1L, page.total());
        assertEquals("n1", page.items().get(0).newsId());
        verify(mysqlJdbc).query(
                eq("CALL sp_news_list_json(?, ?, ?)"),
                any(PreparedStatementSetter.class),
                any(ResultSetExtractor.class));
        verifyNoInteractions(sqlServerDelegate);
    }

    @Test
    void defaultNewsParsesEachRowAsAJsonDocumentInTheItemsArray() {
        when(mysqlJdbc.query(eq("CALL sp_news_default()"), any(RowMapper.class))).thenAnswer(invocation -> {
            @SuppressWarnings("unchecked")
            RowMapper<String> mapper = invocation.getArgument(1);
            ResultSet rs = mock(ResultSet.class);
            when(rs.getString(1)).thenReturn("{\"news_id\":\"n1\"}");
            return List.of(mapper.mapRow(rs, 0));
        });

        var result = repository.defaultNews();

        assertEquals(1, result.get("items").size());
        assertEquals("n1", result.get("items").get(0).get("news_id").asText());
        verifyNoInteractions(sqlServerDelegate);
    }

    @Test
    void exportNewsDelegatesToTheSqlServerRepository() {
        var node = objectMapper.createObjectNode();
        when(sqlServerDelegate.exportNews("7")).thenReturn(node);

        assertEquals(node, repository.exportNews("7"));
        verify(sqlServerDelegate).exportNews("7");
        verifyNoInteractions(mysqlJdbc);
    }

    @Test
    void importNewsDelegatesToTheSqlServerRepository() {
        when(sqlServerDelegate.importNews("{}")).thenReturn("new-id");

        assertEquals("new-id", repository.importNews("{}"));
        verify(sqlServerDelegate).importNews("{}");
        verifyNoInteractions(mysqlJdbc);
    }

    @Test
    void searchDelegatesToTheSqlServerRepository() {
        NewsSearchPage page = new NewsSearchPage(List.of(), 0, "walleye");
        when(sqlServerDelegate.search("walleye")).thenReturn(page);

        assertEquals(page, repository.search("walleye"));
        verify(sqlServerDelegate).search("walleye");
        verifyNoInteractions(mysqlJdbc);
    }
}
