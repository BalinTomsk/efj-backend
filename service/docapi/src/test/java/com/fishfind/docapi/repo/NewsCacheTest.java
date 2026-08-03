package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.web.NewsController.NewsListItem;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * Behaviour of the news caches: what is held, when the database is actually read, and — the point of
 * the design — that a clear is deferred while SQL is unreachable rather than emptying a cache that
 * cannot be refilled.
 */
class NewsCacheTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    // ---- helpers -------------------------------------------------------------------------------

    private static NewsListItem item(int n) {
        return new NewsListItem(n, "id-" + n, "Title " + n, "src", "2026-07-01", "CA", false, 0);
    }

    private static NewsListPage page(int fromInclusive, int count, long total, int offset, int limit) {
        List<NewsListItem> items = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            items.add(item(fromInclusive + i));
        }
        return new NewsListPage(items, total, offset, limit);
    }

    /** Counts how many times the delegate is actually consulted. */
    private static final class CountingRepo implements NewsQueryRepository {
        final AtomicInteger listCalls = new AtomicInteger();
        final AtomicInteger defaultCalls = new AtomicInteger();
        final AtomicInteger exportCalls = new AtomicInteger();
        final AtomicInteger importCalls = new AtomicInteger();
        final AtomicInteger searchCalls = new AtomicInteger();
        private final long total;

        CountingRepo(long total) {
            this.total = total;
        }

        @Override
        public NewsListPage list(String country, int offset, int limit) {
            listCalls.incrementAndGet();
            int available = (int) Math.max(0, Math.min(limit, total - offset));
            return page(offset + 1, available, total, offset, limit);
        }

        @Override
        public JsonNode defaultNews() {
            defaultCalls.incrementAndGet();
            return new ObjectMapper().createObjectNode().put("call", defaultCalls.get());
        }

        @Override
        public JsonNode exportNews(String id) {
            exportCalls.incrementAndGet();
            return new ObjectMapper().createObjectNode().put("id", id);
        }

        @Override
        public String importNews(String json) {
            importCalls.incrementAndGet();
            return "new-" + importCalls.get();
        }

        @Override
        public NewsSearchPage search(String query) {
            searchCalls.incrementAndGet();
            return new NewsSearchPage(List.of(), 0, query);
        }
    }

    // ---- /news/list ----------------------------------------------------------------------------

    @Test
    void usAndCaAreFetchedOnceAsHundredRowBucketsAndPagesAreSlicedFromThem() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache cache = new NewsQueryCache(repo);

        NewsListPage first = cache.list("US", 0, 5);
        assertThat(first.items()).hasSize(5);
        assertThat(first.total()).isEqualTo(500);
        assertThat(repo.listCalls.get()).isEqualTo(1);

        // Further pages inside the cached 100 rows must not touch the database again.
        cache.list("US", 5, 5);
        cache.list("US", 90, 10);
        assertThat(repo.listCalls.get()).isEqualTo(1);

        // CA is a separate bucket -> exactly one more load.
        cache.list("CA", 0, 25);
        assertThat(repo.listCalls.get()).isEqualTo(2);

        int[] sizes = cache.sizes();
        assertThat(sizes[0]).isEqualTo(NewsQueryCache.BUCKET_ROWS); // us rows
        assertThat(sizes[1]).isEqualTo(NewsQueryCache.BUCKET_ROWS); // ca rows
    }

    @Test
    void slicedPageCarriesTheCorrectRowsAndEchoesPaging() {
        NewsQueryCache cache = new NewsQueryCache(new CountingRepo(500));

        NewsListPage p = cache.list("US", 10, 3);

        assertThat(p.offset()).isEqualTo(10);
        assertThat(p.limit()).isEqualTo(3);
        assertThat(p.total()).isEqualTo(500);
        assertThat(p.items()).extracting(NewsListItem::newsId).containsExactly("id-11", "id-12", "id-13");
    }

    @Test
    void deepPagingBeyondTheCachedRowsReadsThroughInsteadOfTruncating() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache cache = new NewsQueryCache(repo);

        cache.list("US", 0, 10);                       // loads the bucket
        assertThat(repo.listCalls.get()).isEqualTo(1);

        NewsListPage deep = cache.list("US", 150, 10); // past the cached 100 rows
        assertThat(repo.listCalls.get()).isEqualTo(2); // read through
        assertThat(deep.items()).hasSize(10);
        assertThat(deep.offset()).isEqualTo(150);
    }

    @Test
    void whenTheBucketHoldsEveryRowAnOffsetPastTheEndYieldsAnEmptyPageWithoutReadingThrough() {
        CountingRepo repo = new CountingRepo(12);      // fewer rows than the bucket size
        NewsQueryCache cache = new NewsQueryCache(repo);

        cache.list("CA", 0, 25);
        assertThat(repo.listCalls.get()).isEqualTo(1);

        NewsListPage past = cache.list("CA", 50, 10);
        assertThat(past.items()).isEmpty();
        assertThat(past.total()).isEqualTo(12);
        assertThat(repo.listCalls.get()).isEqualTo(1); // still no extra database read
    }

    @Test
    void otherCountriesAndTheUnfilteredRequestShareABoundedCache() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache cache = new NewsQueryCache(repo);

        cache.list(null, 0, 25);   // all countries
        cache.list(null, 0, 25);   // repeat -> cached
        cache.list("GB", 0, 25);
        cache.list("GB", 0, 25);   // repeat -> cached
        assertThat(repo.listCalls.get()).isEqualTo(2);
        assertThat(cache.sizes()[2]).isEqualTo(2);
    }

    @Test
    void theOtherRequestCacheIsCappedAtOneHundredEntries() {
        NewsQueryCache cache = new NewsQueryCache(new CountingRepo(5000));

        for (int i = 0; i < NewsQueryCache.OTHER_ENTRIES + 40; i++) {
            cache.list("GB", i, 1);
        }

        assertThat(cache.sizes()[2]).isEqualTo(NewsQueryCache.OTHER_ENTRIES);
    }

    @Test
    void countryMatchingIsCaseInsensitiveSoLowercaseStillHitsTheUsBucket() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache cache = new NewsQueryCache(repo);

        cache.list("US", 0, 5);
        cache.list("us", 0, 5);

        assertThat(repo.listCalls.get()).isEqualTo(1);
    }

    // ---- /news/default -------------------------------------------------------------------------

    @Test
    void defaultPageIsLoadedOnceAndServedFromCacheUntilCleared() {
        CountingRepo repo = new CountingRepo(10);
        NewsQueryCache cache = new NewsQueryCache(repo);

        JsonNode a = cache.defaultNews();
        JsonNode b = cache.defaultNews();
        assertThat(repo.defaultCalls.get()).isEqualTo(1);
        assertThat(b).isEqualTo(a);

        cache.clear();
        cache.defaultNews();
        assertThat(repo.defaultCalls.get()).isEqualTo(2);
    }

    @Test
    void clearEmptiesEveryListCacheSoTheNextRequestRefills() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache cache = new NewsQueryCache(repo);
        cache.list("US", 0, 5);
        cache.list("CA", 0, 5);
        cache.list("GB", 0, 5);
        cache.defaultNews();
        assertThat(cache.sizes()).containsExactly(100, 100, 1, 1);

        cache.clear();

        assertThat(cache.sizes()).containsExactly(0, 0, 0, 0);
        int before = repo.listCalls.get();
        cache.list("US", 0, 5);
        assertThat(repo.listCalls.get()).isEqualTo(before + 1);
    }

    // ---- interchange export / import -----------------------------------------------------------

    @Test
    void exportAlwaysReadsThroughAndIsNotCached() {
        CountingRepo repo = new CountingRepo(0);
        NewsQueryCache cache = new NewsQueryCache(repo);

        cache.exportNews("id-1");
        cache.exportNews("id-1");

        assertThat(repo.exportCalls.get()).isEqualTo(2);
    }

    @Test
    void importCreatesViaDelegateAndEvictsTheCache() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache cache = new NewsQueryCache(repo);
        cache.list("US", 0, 5);
        cache.list("CA", 0, 5);
        cache.defaultNews();
        assertThat(cache.sizes()).containsExactly(100, 100, 0, 1);

        String id = cache.importNews("{\"title\":\"Imported\"}");

        assertThat(id).isEqualTo("new-1");
        assertThat(repo.importCalls.get()).isEqualTo(1);
        // a new published article invalidates the cached lists + home page
        assertThat(cache.sizes()).containsExactly(0, 0, 0, 0);
    }

    // ---- /news/{guid} --------------------------------------------------------------------------

    @Test
    void documentIsReadOnceThenServedFromTheLruCache() {
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument("g1")).thenReturn("{\"title\":\"one\"}");
        NewsDocumentCache cache = new NewsDocumentCache(delegate);

        assertThat(cache.getDocument("g1")).contains("one");
        assertThat(cache.getDocument("g1")).contains("one");

        org.mockito.Mockito.verify(delegate, org.mockito.Mockito.times(1)).getDocument("g1");
        assertThat(cache.size()).isEqualTo(1);
    }

    @Test
    void documentCacheKeepsOnlyTheLastTwentyFive() {
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument(anyString())).thenAnswer(inv -> "{\"id\":\"" + inv.getArgument(0) + "\"}");
        NewsDocumentCache cache = new NewsDocumentCache(delegate);

        for (int i = 0; i < NewsDocumentCache.MAX_DOCUMENTS + 10; i++) {
            cache.getDocument("guid-" + i);
        }

        assertThat(cache.size()).isEqualTo(NewsDocumentCache.MAX_DOCUMENTS);
    }

    @Test
    void aMissingDocumentIsNotCachedSoPublishingLaterBecomesVisible() {
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument("later")).thenReturn(null, "{\"title\":\"published\"}");
        NewsDocumentCache cache = new NewsDocumentCache(delegate);

        assertThat(cache.getDocument("later")).isNull();
        assertThat(cache.getDocument("later")).contains("published");
        assertThat(cache.size()).isEqualTo(1);
    }

    @Test
    void updatingADocumentEvictsItSoTheEditIsVisibleImmediately() {
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument("g1")).thenReturn("{\"v\":1}", "{\"v\":2}");
        when(delegate.updateDocument(anyString(), anyString())).thenReturn("g1");
        NewsDocumentCache cache = new NewsDocumentCache(delegate);

        assertThat(cache.getDocument("g1")).contains("\"v\":1");
        cache.updateDocument("g1", "{\"v\":2}");

        assertThat(cache.getDocument("g1")).contains("\"v\":2");
    }

    @Test
    void documentIdsAreMatchedCaseInsensitivelyBecauseGuidsAre() {
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument(anyString())).thenReturn("{\"title\":\"one\"}");
        NewsDocumentCache cache = new NewsDocumentCache(delegate);

        cache.getDocument("AABBCCDD-0000-1111-2222-333344445555");
        cache.getDocument("aabbccdd-0000-1111-2222-333344445555");

        assertThat(cache.size()).isEqualTo(1);
        org.mockito.Mockito.verify(delegate, org.mockito.Mockito.times(1)).getDocument(anyString());
    }

    // ---- daily eviction, and the SQL-outage rule -----------------------------------------------

    @Test
    void dailyEvictionClearsBothCachesWhenTheDatabaseIsReachable() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache queryCache = new NewsQueryCache(repo);
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument(anyString())).thenReturn("{\"a\":1}");
        NewsDocumentCache docCache = new NewsDocumentCache(delegate);
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(anyString(), any(Class.class))).thenReturn(1);

        queryCache.list("US", 0, 5);
        docCache.getDocument("g1");

        new NewsCacheEvictor(queryCache, docCache, jdbc).dailyEviction();

        assertThat(queryCache.sizes()).containsExactly(0, 0, 0, 0);
        assertThat(docCache.size()).isZero();
    }

    @Test
    void evictionIsDeferredWhileSqlIsUnreachableSoStaleEntriesKeepServing() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache queryCache = new NewsQueryCache(repo);
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument(anyString())).thenReturn("{\"a\":1}");
        NewsDocumentCache docCache = new NewsDocumentCache(delegate);
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(anyString(), any(Class.class)))
                .thenThrow(new DataAccessResourceFailureException("connection refused"));

        queryCache.list("US", 0, 5);
        docCache.getDocument("g1");
        NewsCacheEvictor evictor = new NewsCacheEvictor(queryCache, docCache, jdbc);

        evictor.dailyEviction();

        // Nothing was dropped, and the clear is remembered as still owed.
        assertThat(queryCache.sizes()[0]).isEqualTo(NewsQueryCache.BUCKET_ROWS);
        assertThat(docCache.size()).isEqualTo(1);
        assertThat(evictor.isEvictionPending()).isTrue();

        // Serving continues from cache without touching the database.
        int before = repo.listCalls.get();
        assertThat(queryCache.list("US", 0, 5).items()).hasSize(5);
        assertThat(repo.listCalls.get()).isEqualTo(before);
    }

    @Test
    void aDeferredEvictionIsAppliedAsSoonAsTheConnectionIsRestored() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache queryCache = new NewsQueryCache(repo);
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument(anyString())).thenReturn("{\"a\":1}");
        NewsDocumentCache docCache = new NewsDocumentCache(delegate);
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(anyString(), any(Class.class)))
                .thenThrow(new DataAccessResourceFailureException("down"))
                .thenReturn(1);

        queryCache.list("US", 0, 5);
        docCache.getDocument("g1");
        NewsCacheEvictor evictor = new NewsCacheEvictor(queryCache, docCache, jdbc);

        evictor.dailyEviction();               // deferred
        assertThat(evictor.isEvictionPending()).isTrue();

        evictor.retryPendingEviction();        // database is back

        assertThat(evictor.isEvictionPending()).isFalse();
        assertThat(queryCache.sizes()).containsExactly(0, 0, 0, 0);
        assertThat(docCache.size()).isZero();
    }

    @Test
    void theRetryTickDoesNothingWhenNoEvictionIsOwed() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache queryCache = new NewsQueryCache(repo);
        NewsDocumentCache docCache = new NewsDocumentCache(mock(DocumentStore.class));
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        queryCache.list("US", 0, 5);

        new NewsCacheEvictor(queryCache, docCache, jdbc).retryPendingEviction();

        // No probe, no clear — the cache is untouched on a healthy day.
        org.mockito.Mockito.verifyNoInteractions(jdbc);
        assertThat(queryCache.sizes()[0]).isEqualTo(NewsQueryCache.BUCKET_ROWS);
    }
}
