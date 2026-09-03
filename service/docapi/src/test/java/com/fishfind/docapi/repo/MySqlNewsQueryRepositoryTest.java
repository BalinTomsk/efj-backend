package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.ResultSetExtractor;
import org.springframework.jdbc.core.RowMapper;

import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
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

    /**
     * The home page's article tag row needs names, not ids, and the MySQL database has no
     * {@code lake}/{@code fish} tables — so every id on the page is collected and resolved in ONE
     * SQL Server round trip, and the names are merged back onto the items.
     */
    @Test
    void defaultNewsFillsLakeAndFishNamesFromSqlServer() {
        stubDefaultRows("{\"news_id\":\"n1\",\"lake_id\":\"lake-1\","
                + "\"fish1_id\":\"fish-1\",\"fish2_id\":\"fish-2\",\"fish3_id\":null}");
        when(sqlServerDelegate.resolveRefNames(anyList(), anyList())).thenReturn(refNames("""
                {"lakes":[{"id":"lake-1","name":"Lake Manitou"}],
                 "fishes":[{"id":"fish-1","name":"Muskellunge","latin":"Esox masquinongy"},
                           {"id":"fish-2","name":"Walleye","latin":null}]}"""));

        var item = repository.defaultNews().get("items").get(0);

        assertEquals("Lake Manitou", item.get("lake_name").asText());
        assertEquals(2, item.get("fishes").size());
        assertEquals("fish-1", item.get("fishes").get(0).get("id").asText());
        assertEquals("Muskellunge", item.get("fishes").get(0).get("name").asText());
        assertEquals("Esox masquinongy", item.get("fishes").get(0).get("latin").asText());
        assertEquals("Walleye", item.get("fishes").get(1).get("name").asText());
        assertTrue(item.get("fishes").get(1).get("latin").isNull());

        // The empty third slot must not become a tag, and the whole page is one lookup.
        verify(sqlServerDelegate).resolveRefNames(List.of("lake-1"), List.of("fish-1", "fish-2"));
    }

    /**
     * Moving news to MySQL was about surviving a SQL Server outage; a failed name lookup must not
     * undo that by 500-ing the home page. The items keep their ids and simply carry no names.
     */
    @Test
    void defaultNewsServesIdsOnlyWhenTheNameLookupFails() {
        stubDefaultRows("{\"news_id\":\"n1\",\"lake_id\":\"lake-1\",\"fish1_id\":\"fish-1\"}");
        when(sqlServerDelegate.resolveRefNames(anyList(), anyList()))
                .thenThrow(new RuntimeException("SQL Server unreachable"));

        var item = repository.defaultNews().get("items").get(0);

        assertEquals("lake-1", item.get("lake_id").asText());
        assertTrue(item.get("lake_name").isNull());
        assertEquals(0, item.get("fishes").size());
    }

    /** An article that mentions nothing must not trigger a SQL Server round trip at all. */
    @Test
    void defaultNewsSkipsTheLookupWhenNoArticleMentionsALakeOrFish() {
        stubDefaultRows("{\"news_id\":\"n1\",\"lake_id\":null,\"fish1_id\":\"\"}");

        var item = repository.defaultNews().get("items").get(0);

        assertTrue(item.get("lake_name").isNull());
        assertEquals(0, item.get("fishes").size());
        verifyNoInteractions(sqlServerDelegate);
    }

    @Test
    void resolveRefNamesDelegatesToTheSqlServerRepository() {
        var node = objectMapper.createObjectNode();
        when(sqlServerDelegate.resolveRefNames(List.of("l"), List.of("f"))).thenReturn(node);

        assertEquals(node, repository.resolveRefNames(List.of("l"), List.of("f")));
        verifyNoInteractions(mysqlJdbc);
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

    /** Makes {@code CALL sp_news_default()} return the given JSON documents, one per row. */
    private void stubDefaultRows(String... docs) {
        when(mysqlJdbc.query(eq("CALL sp_news_default()"), any(RowMapper.class))).thenAnswer(invocation -> {
            @SuppressWarnings("unchecked")
            RowMapper<String> mapper = invocation.getArgument(1);
            List<String> rows = new ArrayList<>();
            for (String doc : docs) {
                ResultSet rs = mock(ResultSet.class);
                when(rs.getString(1)).thenReturn(doc);
                rows.add(mapper.mapRow(rs, rows.size()));
            }
            return rows;
        });
    }

    private JsonNode refNames(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (Exception ex) {
            throw new IllegalStateException(ex);
        }
    }
}
