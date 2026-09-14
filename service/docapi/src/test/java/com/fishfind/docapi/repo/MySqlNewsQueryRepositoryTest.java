package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.web.NewsController.NewsRefItem;
import com.fishfind.docapi.web.NewsController.NewsFishPage;
import com.fishfind.docapi.web.NewsController.NewsLakePage;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchItem;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;
import com.fishfind.docapi.web.NewsController.NewsSearchQuery;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.ResultSetExtractor;
import org.springframework.jdbc.core.RowMapper;

import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
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
        // Not "CALL sp_news_default()": 1.8.3 inlined the procedure's body because the view it reads
        // (v_news_default_doc) does not exist in the live Winhost database. Stubbing the old literal
        // matched nothing and quietly asserted an empty page.
        when(mysqlJdbc.query(eq(MySqlNewsQueryRepository.DEFAULT_SQL), any(RowMapper.class))).thenAnswer(invocation -> {
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

    // ---- one water body's news (wfRiverViewer.aspx) ---------------------------------------------

    /**
     * Stubs the single lake-news statement and returns the SQL it was given, so a test can assert the
     * statement as well as the mapping.
     */
    private String[] stubLakeNews(List<String[]> rows) {
        String[] captured = new String[1];
        when(mysqlJdbc.query(any(String.class), any(PreparedStatementSetter.class), any(RowMapper.class)))
                .thenAnswer(invocation -> {
                    captured[0] = invocation.getArgument(0);
                    @SuppressWarnings("unchecked")
                    RowMapper<NewsRefItem> mapper = invocation.getArgument(2);
                    List<NewsRefItem> out = new java.util.ArrayList<>();
                    for (String[] row : rows) {
                        ResultSet rs = mock(ResultSet.class);
                        when(rs.getString("news_id")).thenReturn(row[0]);
                        when(rs.getString("title")).thenReturn(row[1]);
                        when(rs.getString("source")).thenReturn(row[2]);
                        when(rs.getString("stamp")).thenReturn(row[3]);
                        when(rs.getString("country")).thenReturn(row[4]);
                        out.add(mapper.mapRow(rs, 0));
                    }
                    return out;
                });
        return captured;
    }

    @Test
    void lakeNewsReadsFromMySqlAndNeverFromTheSqlServerDelegate() {
        stubLakeNews(List.<String[]>of(
                new String[]{"n1", "Ice out on the Grand", "Outdoor Canada", "2026-05-14", "CA"},
                new String[]{"n2", "Walleye opener", null, "2026-05-01", "CA"}));

        NewsLakePage page = repository.lakeNews("fc0d917b-d053-11d8-92e2-080020a0f4c9", 12);

        assertEquals(2, page.items().size());
        assertEquals("fc0d917b-d053-11d8-92e2-080020a0f4c9", page.lakeId());
        assertEquals(12, page.limit());
        assertEquals("n1", page.items().get(0).newsId());
        assertEquals("Ice out on the Grand", page.items().get(0).title());
        assertEquals("2026-05-14", page.items().get(0).stamp());
        assertNull(page.items().get(1).source());
        verifyNoInteractions(sqlServerDelegate);
    }

    /**
     * The same rule the search statements live under: this runs on a public page view, so the plan
     * must never reference a photo column while buffering rows. It must also stay published-only and
     * totally ordered -- the caller deals these rows alternately into two columns, so a tie broken
     * differently between requests would move a headline from one column to the other on a refresh.
     */
    @Test
    void lakeNewsSelectsNarrowColumnsOnlyAndIsPublishedOnlyAndTotallyOrdered() {
        String[] sql = stubLakeNews(List.of());

        repository.lakeNews("fc0d917b-d053-11d8-92e2-080020a0f4c9", 12);

        assertFalse(sql[0].contains("news_photo"), sql[0]);
        assertFalse(sql[0].contains("has_photo0"), sql[0]);
        assertFalse(sql[0].contains("news_paragraph"), sql[0]);
        assertFalse(sql[0].contains("OVER ("), sql[0]);
        assertTrue(sql[0].contains("news_publish = 1"), sql[0]);
        assertTrue(sql[0].contains("lake_id = ?"), sql[0]);
        assertTrue(sql[0].contains("ORDER BY news_stamp DESC, news_id DESC"), sql[0]);
        assertTrue(sql[0].contains("LIMIT ?"), sql[0]);
    }

    /** The lake id binds before the limit; swapping them silently returns the wrong article set. */
    @Test
    void lakeNewsBindsTheLakeIdThenTheLimit() throws Exception {
        stubLakeNews(List.of());
        ArgumentCaptor<PreparedStatementSetter> binder = ArgumentCaptor.forClass(PreparedStatementSetter.class);

        repository.lakeNews("fc0d917b-d053-11d8-92e2-080020a0f4c9", 12);

        verify(mysqlJdbc).query(any(String.class), binder.capture(), any(RowMapper.class));
        PreparedStatement ps = mock(PreparedStatement.class);
        binder.getValue().setValues(ps);

        InOrder order = inOrder(ps);
        order.verify(ps).setString(1, "fc0d917b-d053-11d8-92e2-080020a0f4c9");
        order.verify(ps).setInt(2, 12);
    }

    // ---- one species' news (wfFishViewer.aspx) -----------------------------------------------------

    /**
     * Stubs the single fish-news statement and returns the SQL it was given, so a test can assert the
     * statement as well as the mapping. Same row shape as {@link #stubLakeNews}, since both share
     * {@code MySqlNewsQueryRepository.REF_ROW_MAPPER}.
     */
    private String[] stubFishNews(List<String[]> rows) {
        String[] captured = new String[1];
        when(mysqlJdbc.query(any(String.class), any(PreparedStatementSetter.class), any(RowMapper.class)))
                .thenAnswer(invocation -> {
                    captured[0] = invocation.getArgument(0);
                    @SuppressWarnings("unchecked")
                    RowMapper<NewsRefItem> mapper = invocation.getArgument(2);
                    List<NewsRefItem> out = new java.util.ArrayList<>();
                    for (String[] row : rows) {
                        ResultSet rs = mock(ResultSet.class);
                        when(rs.getString("news_id")).thenReturn(row[0]);
                        when(rs.getString("title")).thenReturn(row[1]);
                        when(rs.getString("source")).thenReturn(row[2]);
                        when(rs.getString("stamp")).thenReturn(row[3]);
                        when(rs.getString("country")).thenReturn(row[4]);
                        out.add(mapper.mapRow(rs, 0));
                    }
                    return out;
                });
        return captured;
    }

    @Test
    void fishNewsReadsFromMySqlAndNeverFromTheSqlServerDelegate() {
        stubFishNews(List.<String[]>of(
                new String[]{"n1", "Walleye run peaks", "Outdoor Canada", "2026-05-14", "CA"},
                new String[]{"n2", "Ice fishing guide", null, "2026-05-01", "CA"}));

        NewsFishPage page = repository.fishNews("a85ebf22-4ab9-4a91-a14a-cef6c8e64d97", 10);

        assertEquals(2, page.items().size());
        assertEquals("a85ebf22-4ab9-4a91-a14a-cef6c8e64d97", page.fishId());
        assertEquals(10, page.limit());
        assertEquals("n1", page.items().get(0).newsId());
        assertEquals("Walleye run peaks", page.items().get(0).title());
        assertEquals("2026-05-14", page.items().get(0).stamp());
        assertNull(page.items().get(1).source());
        verifyNoInteractions(sqlServerDelegate);
    }

    /**
     * Same rule as {@link #lakeNewsSelectsNarrowColumnsOnlyAndIsPublishedOnlyAndTotallyOrdered}: no
     * photo column, no window function, published-only, totally ordered. This statement additionally
     * must match ANY of the three species slots, not just one column.
     */
    @Test
    void fishNewsSelectsNarrowColumnsOnlyAndIsPublishedOnlyAndTotallyOrdered() {
        String[] sql = stubFishNews(List.of());

        repository.fishNews("a85ebf22-4ab9-4a91-a14a-cef6c8e64d97", 10);

        assertFalse(sql[0].contains("news_photo"), sql[0]);
        assertFalse(sql[0].contains("has_photo0"), sql[0]);
        assertFalse(sql[0].contains("news_paragraph"), sql[0]);
        assertFalse(sql[0].contains("OVER ("), sql[0]);
        assertTrue(sql[0].contains("news_publish = 1"), sql[0]);
        assertTrue(sql[0].contains("fish1_id = ?"), sql[0]);
        assertTrue(sql[0].contains("fish2_id = ?"), sql[0]);
        assertTrue(sql[0].contains("fish3_id = ?"), sql[0]);
        assertTrue(sql[0].contains("ORDER BY news_stamp DESC, news_id DESC"), sql[0]);
        assertTrue(sql[0].contains("LIMIT ?"), sql[0]);
    }

    /** All three slots bind the same fish id, then the limit -- a fourth or reordered bind silently changes which rows match. */
    @Test
    void fishNewsBindsTheFishIdToAllThreeSlotsThenTheLimit() throws Exception {
        stubFishNews(List.of());
        ArgumentCaptor<PreparedStatementSetter> binder = ArgumentCaptor.forClass(PreparedStatementSetter.class);

        repository.fishNews("a85ebf22-4ab9-4a91-a14a-cef6c8e64d97", 10);

        verify(mysqlJdbc).query(any(String.class), binder.capture(), any(RowMapper.class));
        PreparedStatement ps = mock(PreparedStatement.class);
        binder.getValue().setValues(ps);

        InOrder order = inOrder(ps);
        order.verify(ps).setString(1, "a85ebf22-4ab9-4a91-a14a-cef6c8e64d97");
        order.verify(ps).setString(2, "a85ebf22-4ab9-4a91-a14a-cef6c8e64d97");
        order.verify(ps).setString(3, "a85ebf22-4ab9-4a91-a14a-cef6c8e64d97");
        order.verify(ps).setInt(4, 10);
    }

    // ---- news search (MySQL as of 1.10.0; was delegated to SQL Server) --------------------------

    /**
     * Stubs the count statement (a {@link ResultSetExtractor}) and the row statement (a
     * {@link RowMapper}) separately, so a test can assert what each of the two search statements was
     * given. Returns the captured SQL of each, in that order.
     */
    private String[] stubSearch(int total, List<String[]> rows) {
        String[] captured = new String[2];
        when(mysqlJdbc.query(any(String.class), any(PreparedStatementSetter.class), any(ResultSetExtractor.class)))
                .thenAnswer(invocation -> {
                    captured[0] = invocation.getArgument(0);
                    @SuppressWarnings("unchecked")
                    ResultSetExtractor<Integer> extractor = invocation.getArgument(2);
                    ResultSet rs = mock(ResultSet.class);
                    when(rs.next()).thenReturn(true, false);
                    when(rs.getInt(1)).thenReturn(total);
                    return extractor.extractData(rs);
                });
        when(mysqlJdbc.query(any(String.class), any(PreparedStatementSetter.class), any(RowMapper.class)))
                .thenAnswer(invocation -> {
                    captured[1] = invocation.getArgument(0);
                    @SuppressWarnings("unchecked")
                    RowMapper<NewsSearchItem> mapper = invocation.getArgument(2);
                    List<NewsSearchItem> out = new java.util.ArrayList<>();
                    for (String[] row : rows) {
                        ResultSet rs = mock(ResultSet.class);
                        when(rs.getString("news_id")).thenReturn(row[0]);
                        when(rs.getString("title")).thenReturn(row[1]);
                        when(rs.getString("source")).thenReturn(row[2]);
                        when(rs.getString("stamp")).thenReturn(row[3]);
                        when(rs.getString("country")).thenReturn(row[4]);
                        when(rs.getString("fish1_id")).thenReturn(row[5]);
                        when(rs.getString("fish2_id")).thenReturn(row[6]);
                        when(rs.getString("fish3_id")).thenReturn(row[7]);
                        out.add(mapper.mapRow(rs, 0));
                    }
                    return out;
                });
        return captured;
    }

    @Test
    void searchReadsFromMySqlAndNeverFromTheSqlServerDelegate() {
        String[] sql = stubSearch(1, List.<String[]>of(
                new String[]{"n1", "Walleye run peaks", "Outdoor Canada", "2026-05-14", "CA", "f1", null, "f1"}));

        NewsSearchPage page = repository.search(
                new NewsSearchQuery("walleye", List.of(), null, 0, 25));

        assertEquals(1, page.items().size());
        assertEquals(1, page.total());
        assertEquals("walleye", page.query());
        assertEquals("n1", page.items().get(0).newsId());
        // fishes (names) need a fish table this database does not have; the ids come back instead,
        // de-duplicated and blank-free.
        assertTrue(page.items().get(0).fishes().isEmpty());
        assertEquals(List.of("f1"), page.items().get(0).fishIds());
        verifyNoInteractions(sqlServerDelegate);

        assertTrue(sql[0].startsWith("SELECT COUNT(*) "), sql[0]);
        assertTrue(sql[1].contains("ORDER BY news_stamp DESC, news_id DESC LIMIT ?, ?"), sql[1]);
    }

    /**
     * The whole reason the two statements are not one windowed query: on the live Winhost host a plan
     * that buffers multiple rows while referencing an off-page column hangs indefinitely. The
     * paragraphs may be filtered on but must never be selected or ranked over.
     */
    @Test
    void searchFiltersOnParagraphsButNeitherSelectsThemNorUsesAWindowFunction() {
        String[] sql = stubSearch(0, List.of());

        repository.search(new NewsSearchQuery("pike", List.of(), null, 0, 25));

        for (String statement : sql) {
            assertTrue(statement.contains("news_paragraph0 LIKE ?"), statement);
            assertTrue(statement.contains("news_photo_alt2 LIKE ?"), statement);
            assertFalse(statement.contains("OVER ("), statement);
            assertFalse(statement.contains("news_photo0"), statement);
        }
        // Selected columns are the narrow ones only -- no paragraph reaches a sort buffer.
        assertFalse(sql[1].contains("news_paragraph0 AS"), sql[1]);
        assertTrue(sql[1].contains("fish1_id, fish2_id, fish3_id"), sql[1]);
    }

    /**
     * The escape character in the SQL TEXT must be a DOUBLED backslash. MySQL parses a string literal
     * before it parses the {@code ESCAPE} clause, so {@code ESCAPE '\'} in the emitted SQL is an
     * escaped quote followed by an unterminated string -- a syntax error, not a backslash. A Java text
     * block halves every pair, so the source needs four to emit two. Caught against a real MySQL 8
     * before this ever shipped; this test is what stops it coming back.
     */
    @Test
    void searchEmitsADoubledBackslashAsTheLikeEscapeCharacter() {
        String[] sql = stubSearch(0, List.of());

        repository.search(new NewsSearchQuery("walleye", List.of(), null, 0, 25));

        for (String statement : sql) {
            // A single backslash here would make the statement contain ESCAPE '\' and NOT this, so
            // this one assertion is the whole guard.
            assertTrue(statement.contains("ESCAPE '\\\\'"),
                    "escape must be a doubled backslash in the SQL text: " + statement);
        }
    }

    @Test
    void searchAddsACountryClauseOnlyWhenACountryIsAsked() {
        String[] filtered = stubSearch(0, List.of());
        repository.search(new NewsSearchQuery("pike", List.of(), "CA", 0, 25));
        assertTrue(filtered[0].contains("AND country = ?"), filtered[0]);

        String[] unfiltered = stubSearch(0, List.of());
        repository.search(new NewsSearchQuery("pike", List.of(), null, 0, 25));
        assertFalse(unfiltered[0].contains("AND country = ?"), unfiltered[0]);
    }

    @Test
    void searchMatchesSuppliedSpeciesIdsInAllThreeSlots() {
        String[] sql = stubSearch(0, List.of());

        repository.search(new NewsSearchQuery("walleye", List.of("f1", "f2"), null, 0, 25));

        for (String slot : new String[]{"fish1_id IN (?, ?)", "fish2_id IN (?, ?)", "fish3_id IN (?, ?)"}) {
            assertTrue(sql[0].contains(slot), slot + " missing from " + sql[0]);
        }
    }

    /** An empty id list must remove the clause entirely -- {@code IN ()} is a MySQL syntax error. */
    @Test
    void searchWithNoSpeciesIdsEmitsNoInClause() {
        String[] sql = stubSearch(0, List.of());

        repository.search(new NewsSearchQuery("walleye", List.of(), null, 0, 25));

        assertFalse(sql[0].contains("IN ("), sql[0]);
        assertFalse(sql[0].contains("fish1_id"), sql[0]);
    }

    @Test
    void searchCapsTheReportedTotalAndRefusesAWindowPastTheCap() {
        String[] sql = stubSearch(4824, List.of());

        NewsSearchPage capped = repository.search(new NewsSearchQuery("fish", List.of(), null, 0, 25));
        assertEquals(NewsQueryRepository.SEARCH_CAP, capped.total());
        assertTrue(sql[1] != null, "the row statement should still run for a window inside the cap");

        // A page starting at or past the cap answers empty WITHOUT a second statement.
        String[] beyond = stubSearch(4824, List.of());
        NewsSearchPage empty = repository.search(new NewsSearchQuery("fish", List.of(), null, 100, 25));
        assertTrue(empty.items().isEmpty());
        assertEquals(NewsQueryRepository.SEARCH_CAP, empty.total());
        assertNull(beyond[1], "no row statement should be issued past the cap");
    }

    @Test
    void searchBindsTheEscapedPatternToEveryTextColumnThenTheCountryThenTheWindow() throws Exception {
        stubSearch(0, List.<String[]>of(new String[]{"n1", "t", "s", "2026-01-01", "CA", null, null, null}));

        repository.search(new NewsSearchQuery("50%_off", List.of("f1"), "CA", 5, 10));

        org.mockito.ArgumentCaptor<PreparedStatementSetter> binder =
                org.mockito.ArgumentCaptor.forClass(PreparedStatementSetter.class);
        verify(mysqlJdbc).query(any(String.class), binder.capture(), any(RowMapper.class));

        java.sql.PreparedStatement ps = mock(java.sql.PreparedStatement.class);
        binder.getValue().setValues(ps);

        // 1 country + 8 text columns + 1 id x 3 slots = 12 placeholders, then the LIMIT pair.
        verify(ps).setString(1, "CA");
        verify(ps).setString(eq(2), eq("%50\\%\\_off%"));
        verify(ps).setString(eq(9), eq("%50\\%\\_off%"));
        verify(ps).setString(10, "f1");
        verify(ps).setString(12, "f1");
        verify(ps).setInt(13, 5);
        verify(ps).setInt(14, 10);
    }

    @Test
    void exportAndImportStillDelegateToTheSqlServerRepository() {
        when(sqlServerDelegate.importNews("{}")).thenReturn("new-id");
        assertEquals("new-id", repository.importNews("{}"));
        verifyNoInteractions(mysqlJdbc);
    }

    // ---- news photo ----------------------------------------------------------------------------

    @Test
    void photoReadsTheBlobFromMySqlByPrimaryKey() {
        byte[] bytes = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 7};
        when(mysqlJdbc.query(eq(MySqlNewsQueryRepository.PHOTO_SQL), any(PreparedStatementSetter.class), any(RowMapper.class)))
                .thenReturn(List.of(bytes));

        assertArrayEquals(bytes, repository.newsPhoto("n1"));
        verifyNoInteractions(sqlServerDelegate);
    }

    @Test
    void photoOfAnUnknownOrUnpublishedArticleIsNull() {
        when(mysqlJdbc.query(eq(MySqlNewsQueryRepository.PHOTO_SQL), any(PreparedStatementSetter.class), any(RowMapper.class)))
                .thenReturn(List.of());

        assertNull(repository.newsPhoto("nope"));
    }

    /**
     * The live Winhost host hangs indefinitely on any query that touches {@code news_photo0} while
     * materializing more than one row, and a draft's photo must be as unreachable as its text. Both
     * guarantees live in this one statement, so pin its shape rather than only its behaviour.
     */
    @Test
    void photoQueryIsASingleRowPrimaryKeyLookupOverPublishedRowsOnly() {
        String sql = MySqlNewsQueryRepository.PHOTO_SQL;

        assertTrue(sql.contains("WHERE news_id = ?"), sql);
        assertTrue(sql.contains("news_publish = 1"), sql);
        assertTrue(sql.contains("LIMIT 1"), sql);
        assertTrue(sql.contains("SELECT news_photo0"), sql);
        // No join and no IN-list: either would make this a multi-row read of the blob column.
        assertTrue(!sql.toUpperCase(java.util.Locale.ROOT).contains(" JOIN "), sql);
        assertTrue(!sql.toUpperCase(java.util.Locale.ROOT).contains(" IN ("), sql);
    }
}
