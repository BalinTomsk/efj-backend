package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.config.NewsCacheProperties;
import com.fishfind.docapi.web.NewsController.NewsFishPage;
import com.fishfind.docapi.web.NewsController.NewsLakePage;
import com.fishfind.docapi.web.NewsController.NewsListItem;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;
import com.fishfind.docapi.web.NewsController.NewsSearchQuery;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Behaviour of the news caches: what is held, when the database is actually read, and — the point of
 * the design — that a clear is deferred while SQL is unreachable rather than emptying a cache that
 * cannot be refilled.
 */
class NewsCacheTest {

    /**
     * Unconfigured properties, i.e. the defaults — so the bounds asserted below are read from the same
     * place production reads them, not restated as literals that could drift from the yaml.
     */
    private static final NewsCacheProperties CACHE_PROPS = new NewsCacheProperties();

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

    /** A text-only search for {@code term}, all-countries, first page — the common shape. */
    private static NewsSearchQuery query(String term) {
        return new NewsSearchQuery(term, List.of(), null, 0, 25);
    }

    /** Counts how many times the delegate is actually consulted. */
    private static class CountingRepo implements NewsQueryRepository {
        final AtomicInteger listCalls = new AtomicInteger();
        final AtomicInteger defaultCalls = new AtomicInteger();
        final AtomicInteger exportCalls = new AtomicInteger();
        final AtomicInteger searchCalls = new AtomicInteger();
        final AtomicInteger photoCalls = new AtomicInteger();
        final AtomicInteger lakeCalls = new AtomicInteger();
        final AtomicInteger fishCalls = new AtomicInteger();
        /** The order each {@code list} call was made with, in call order. */
        final List<NewsListOrder> listOrders = java.util.Collections.synchronizedList(new ArrayList<>());
        private final long total;

        CountingRepo(long total) {
            this.total = total;
        }

        @Override
        public NewsListPage list(String country, int offset, int limit, NewsListOrder order) {
            listCalls.incrementAndGet();
            listOrders.add(order);
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
        public NewsSearchPage search(NewsSearchQuery request) {
            searchCalls.incrementAndGet();
            return new NewsSearchPage(List.of(), 0, request.query(), request.offset(), request.limit());
        }

        @Override
        public byte[] newsPhoto(String id) {
            photoCalls.incrementAndGet();
            return new byte[] {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 0x00};
        }

        @Override
        public NewsLakePage lakeNews(String lakeId, int limit) {
            lakeCalls.incrementAndGet();
            return new NewsLakePage(lakeId, limit, List.of());
        }

        @Override
        public NewsFishPage fishNews(String fishId, int limit) {
            fishCalls.incrementAndGet();
            return new NewsFishPage(fishId, limit, List.of());
        }
    }

    // ---- /news/list ----------------------------------------------------------------------------

    @Test
    void usAndCaAreFetchedOnceAsHundredRowBucketsAndPagesAreSlicedFromThem() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

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
    void anEditedOrderRequestIsNeverAnsweredFromTheDateBucketAndIsCachedUnderItsOwnKey() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        cache.list("US", 0, 5, NewsListOrder.DATE);      // loads the US date bucket
        cache.list("US", 0, 5, NewsListOrder.EDITED);    // must NOT be sliced from that bucket
        assertThat(repo.listCalls.get()).isEqualTo(2);
        assertThat(repo.listOrders).containsExactly(NewsListOrder.DATE, NewsListOrder.EDITED);

        cache.list("US", 0, 5, NewsListOrder.EDITED);    // repeat: served from the keyed cache
        cache.list("US", 5, 5, NewsListOrder.DATE);      // still inside the date bucket
        assertThat(repo.listCalls.get()).isEqualTo(2);

        cache.list(null, 0, 25, NewsListOrder.DATE);     // same country + offset + limit, other order
        cache.list(null, 0, 25, NewsListOrder.EDITED);   // -> two entries, not one shared
        assertThat(repo.listCalls.get()).isEqualTo(4);
        assertThat(repo.listOrders.subList(2, 4)).containsExactly(NewsListOrder.DATE, NewsListOrder.EDITED);
    }

    @Test
    void theThreeArgListDefaultsToTheDateOrder() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        cache.list("GB", 0, 5);

        assertThat(repo.listOrders).containsExactly(NewsListOrder.DATE);
    }

    @Test
    void slicedPageCarriesTheCorrectRowsAndEchoesPaging() {
        NewsQueryCache cache = new NewsQueryCache(new CountingRepo(500), CACHE_PROPS);

        NewsListPage p = cache.list("US", 10, 3);

        assertThat(p.offset()).isEqualTo(10);
        assertThat(p.limit()).isEqualTo(3);
        assertThat(p.total()).isEqualTo(500);
        assertThat(p.items()).extracting(NewsListItem::newsId).containsExactly("id-11", "id-12", "id-13");
    }

    @Test
    void deepPagingBeyondTheCachedRowsReadsThroughInsteadOfTruncating() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        cache.list("US", 0, 10);                       // loads the bucket
        assertThat(repo.listCalls.get()).isEqualTo(1);

        NewsListPage deep = cache.list("US", 150, 10); // past the cached 100 rows
        assertThat(repo.listCalls.get()).isEqualTo(2); // cold -> one read through
        assertThat(deep.items()).hasSize(10);
        assertThat(deep.offset()).isEqualTo(150);

        // ...and then it is cached like any other request, rather than re-querying every time.
        NewsListPage again = cache.list("US", 150, 10);
        assertThat(repo.listCalls.get()).isEqualTo(2);
        assertThat(again.items()).isEqualTo(deep.items());
        assertThat(cache.sizes()[2]).isEqualTo(1);
    }

    @Test
    void whenTheBucketHoldsEveryRowAnOffsetPastTheEndYieldsAnEmptyPageWithoutReadingThrough() {
        CountingRepo repo = new CountingRepo(12);      // fewer rows than the bucket size
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

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
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        cache.list(null, 0, 25);   // all countries
        cache.list(null, 0, 25);   // repeat -> cached
        cache.list("GB", 0, 25);
        cache.list("GB", 0, 25);   // repeat -> cached
        assertThat(repo.listCalls.get()).isEqualTo(2);
        assertThat(cache.sizes()[2]).isEqualTo(2);
    }

    @Test
    void theOtherRequestCacheIsCappedAtOneHundredEntries() {
        NewsQueryCache cache = new NewsQueryCache(new CountingRepo(5000), CACHE_PROPS);

        for (int i = 0; i < CACHE_PROPS.getNews().getList() + 40; i++) {
            cache.list("GB", i, 1);
        }

        assertThat(cache.sizes()[2]).isEqualTo(CACHE_PROPS.getNews().getList());
    }

    /**
     * The contract is "serve from cache, touch the database only when the cache is empty" — which has
     * to hold under concurrency too, or a burst on a cold cache becomes a burst on the database.
     */
    @Test
    void aColdEntryIsLoadedOnceEvenWhenManyRequestsArriveTogether() throws Exception {
        SlowRepo repo = new SlowRepo();
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        runConcurrently(16, () -> cache.list("GB", 0, 25));
        assertThat(repo.listCalls.get()).isEqualTo(1);

        runConcurrently(16, cache::defaultNews);
        assertThat(repo.defaultCalls.get()).isEqualTo(1);
    }

    /** Delegate that dawdles on every load, so a stampede has time to form if nothing prevents it. */
    private static final class SlowRepo extends CountingRepo {
        SlowRepo() {
            super(500);
        }

        @Override
        public NewsListPage list(String country, int offset, int limit, NewsListOrder order) {
            sleep();
            return super.list(country, offset, limit, order);
        }

        @Override
        public JsonNode defaultNews() {
            sleep();
            return super.defaultNews();
        }

        @Override
        public JsonNode exportNews(String id) {
            sleep();
            return super.exportNews(id);
        }

        @Override
        public NewsSearchPage search(NewsSearchQuery request) {
            sleep();
            return super.search(request);
        }

        @Override
        public byte[] newsPhoto(String id) {
            sleep();
            return super.newsPhoto(id);
        }

        private static void sleep() {
            try {
                Thread.sleep(60);
            } catch (InterruptedException ex) {
                Thread.currentThread().interrupt();
            }
        }
    }

    /** Fires {@code threads} copies of {@code action} at the same instant and waits for all of them. */
    private static void runConcurrently(int threads, Runnable action) throws Exception {
        CountDownLatch start = new CountDownLatch(1);
        CountDownLatch done = new CountDownLatch(threads);
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        try {
            for (int i = 0; i < threads; i++) {
                pool.execute(() -> {
                    try {
                        start.await();
                        action.run();
                    } catch (InterruptedException ex) {
                        Thread.currentThread().interrupt();
                    } finally {
                        done.countDown();
                    }
                });
            }
            start.countDown();
            assertThat(done.await(30, TimeUnit.SECONDS)).isTrue();
        } finally {
            pool.shutdownNow();
        }
    }

    @Test
    void countryMatchingIsCaseInsensitiveSoLowercaseStillHitsTheUsBucket() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        cache.list("US", 0, 5);
        cache.list("us", 0, 5);

        assertThat(repo.listCalls.get()).isEqualTo(1);
    }

    // ---- /news/default -------------------------------------------------------------------------

    @Test
    void defaultPageIsLoadedOnceAndServedFromCacheUntilCleared() {
        CountingRepo repo = new CountingRepo(10);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

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
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);
        cache.list("US", 0, 5);
        cache.list("CA", 0, 5);
        cache.list("GB", 0, 5);
        cache.defaultNews();
        assertThat(cache.sizes()).containsExactly(100, 100, 1, 1, 0, 0, 0, 0, 0);

        cache.clear();

        assertThat(cache.sizes()).containsExactly(0, 0, 0, 0, 0, 0, 0, 0, 0);
        int before = repo.listCalls.get();
        cache.list("US", 0, 5);
        assertThat(repo.listCalls.get()).isEqualTo(before + 1);
    }

    // ---- interchange export / import -----------------------------------------------------------

    @Test
    void exportIsReadOnceThenServedFromItsLruCache() {
        CountingRepo repo = new CountingRepo(0);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        // ~2s per call through the gateway (base64 of three LONGBLOBs over a cold remote connection),
        // so the repeat an admin round trip makes must not pay it again.
        JsonNode first = cache.exportNews("id-1");
        JsonNode second = cache.exportNews("id-1");

        assertThat(repo.exportCalls.get()).isEqualTo(1);
        assertThat(second).isSameAs(first);
        assertThat(cache.sizes()[4]).isEqualTo(1);
    }

    @Test
    void exportKeysAreCaseInsensitiveSoOneArticleIsOneEntry() {
        CountingRepo repo = new CountingRepo(0);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        // news_id's collation is case-insensitive, so both spellings resolve to the same row.
        cache.exportNews("598B47D2-B253-11F1-9659-00155D23D30D");
        cache.exportNews("598b47d2-b253-11f1-9659-00155d23d30d");

        assertThat(repo.exportCalls.get()).isEqualTo(1);
        assertThat(cache.sizes()[4]).isEqualTo(1);
    }

    @Test
    void exportCacheKeepsOnlyTheLastTwentyFive() {
        CountingRepo repo = new CountingRepo(0);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        for (int i = 0; i < CACHE_PROPS.getNews().getExport() + 10; i++) {
            cache.exportNews("id-" + i);
        }

        assertThat(cache.sizes()[4]).isEqualTo(CACHE_PROPS.getNews().getExport());
    }

    /**
     * The bounds are configuration as of 2026-09-18, and every other test here runs on the defaults —
     * which would still pass if the properties were ignored and the old constants left in place. This
     * is the one that fails if the wiring from {@link NewsCacheProperties} to the maps is lost, and it
     * uses three DIFFERENT values so a cache reading the wrong property is caught too.
     */
    @Test
    void eachConfiguredBoundReachesItsOwnCacheAndNotAnother() {
        NewsCacheProperties tight = new NewsCacheProperties();
        tight.getNews().setExport(3);
        tight.setWaterBody(2);
        tight.setFish(1);

        CountingRepo repo = new CountingRepo(0);
        NewsQueryCache cache = new NewsQueryCache(repo, tight);

        for (int i = 0; i < 12; i++) {
            cache.exportNews("export-" + i);
            cache.lakeNews("lake-" + i, 12);
            cache.fishNews("fish-" + i, 10);
        }

        assertThat(cache.sizes()[4]).as("export").isEqualTo(3);
        assertThat(cache.sizes()[6]).as("water body").isEqualTo(2);
        assertThat(cache.sizes()[7]).as("fish").isEqualTo(1);
    }

    /**
     * An unknown id is passed back but not stored, so a later publish of that id is visible at once.
     * The crawler hazard {@link NewsDocumentCache} remembers misses for does not apply here: cproxy
     * day-key-gates {@code /news/export} and {@code /news/photo}, so nothing reaches them unauthenticated.
     */
    @Test
    void anUnknownIdIsNotCachedSoItIsRetriedRatherThanRememberedAsMissing() {
        NullRepo repo = new NullRepo();
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        assertThat(cache.exportNews("ghost")).isNull();
        assertThat(cache.exportNews("ghost")).isNull();
        assertThat(cache.newsPhoto("ghost")).isNull();
        assertThat(cache.newsPhoto("ghost")).isNull();

        assertThat(repo.exportCalls.get()).isEqualTo(2);
        assertThat(repo.photoCalls.get()).isEqualTo(2);
        assertThat(cache.sizes()[4]).isZero();
        assertThat(cache.sizes()[8]).isZero();
    }

    /** Delegate whose per-id reads all answer "no such article". */
    private static final class NullRepo extends CountingRepo {
        NullRepo() {
            super(0);
        }

        @Override
        public JsonNode exportNews(String id) {
            exportCalls.incrementAndGet();
            return null;
        }

        @Override
        public byte[] newsPhoto(String id) {
            photoCalls.incrementAndGet();
            return null;
        }
    }

    @Test
    void clearEmptiesThePerRequestLrusTooSoTheNextRequestRefills() {
        CountingRepo repo = new CountingRepo(0);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);
        cache.exportNews("id-1");
        cache.search(query("walleye"));
        cache.lakeNews("fc0d917b-d053-11d8-92e2-080020a0f4c9", 12);
        cache.fishNews("a85ebf22-4ab9-4a91-a14a-cef6c8e64d97", 10);
        cache.newsPhoto("id-1");
        assertThat(cache.sizes()).containsExactly(0, 0, 0, 0, 1, 1, 1, 1, 1);

        cache.clear();

        assertThat(cache.sizes()).containsExactly(0, 0, 0, 0, 0, 0, 0, 0, 0);
        cache.exportNews("id-1");
        assertThat(repo.exportCalls.get()).isEqualTo(2);
    }

    // ---- /news/{guid} --------------------------------------------------------------------------

    @Test
    void documentIsReadOnceThenServedFromTheLruCache() {
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument("g1")).thenReturn("{\"title\":\"one\"}");
        NewsDocumentCache cache = new NewsDocumentCache(delegate, CACHE_PROPS);

        assertThat(cache.getDocument("g1")).contains("one");
        assertThat(cache.getDocument("g1")).contains("one");

        org.mockito.Mockito.verify(delegate, org.mockito.Mockito.times(1)).getDocument("g1");
        assertThat(cache.size()).isEqualTo(1);
    }

    @Test
    void documentCacheKeepsOnlyTheLastTwentyFive() {
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument(anyString())).thenAnswer(inv -> "{\"id\":\"" + inv.getArgument(0) + "\"}");
        NewsDocumentCache cache = new NewsDocumentCache(delegate, CACHE_PROPS);

        for (int i = 0; i < CACHE_PROPS.getNews().getDocument() + 10; i++) {
            cache.getDocument("guid-" + i);
        }

        assertThat(cache.size()).isEqualTo(CACHE_PROPS.getNews().getDocument());
    }

    /**
     * An unknown id used to reach the database on every single request, so a scanner walking guids
     * could hammer the remote MySQL forever. It is now remembered — but only for MISS_TTL_MS.
     */
    @Test
    void anUnknownIdIsRememberedSoRepeatedLookupsDoNotReachTheDatabase() {
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument("nope")).thenReturn(null);
        NewsDocumentCache cache = new NewsDocumentCache(delegate, CACHE_PROPS);

        for (int i = 0; i < 20; i++) {
            assertThat(cache.getDocument("nope")).isNull();
        }

        verify(delegate, times(1)).getDocument("nope");
        assertThat(cache.missCount()).isEqualTo(1);
        assertThat(cache.size()).isZero();
    }

    /**
     * The TTL is the price of remembering misses: an article published straight into the database by
     * the portal (AddNews.aspx, which never notifies docapi) must not 404 until the next daily clear.
     */
    @Test
    void aRememberedMissExpiresSoPublishingLaterBecomesVisible() {
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument("later")).thenReturn(null, "{\"title\":\"published\"}");
        AtomicLong now = new AtomicLong(0L);
        NewsDocumentCache cache = new NewsDocumentCache(delegate, CACHE_PROPS, now::get);

        assertThat(cache.getDocument("later")).isNull();

        // Inside the TTL the remembered miss still answers, without touching the delegate.
        now.set(NewsDocumentCache.MISS_TTL_MS - 1);
        assertThat(cache.getDocument("later")).isNull();
        verify(delegate, times(1)).getDocument("later");

        // Past it, the database is asked again and now has the article.
        now.set(NewsDocumentCache.MISS_TTL_MS);
        assertThat(cache.getDocument("later")).contains("published");
        assertThat(cache.size()).isEqualTo(1);
        assertThat(cache.missCount()).isZero();
    }

    /** Remembered misses are bounded, so a scan of endless guids cannot grow the heap. */
    @Test
    void rememberedMissesAreCappedAtTheirBound() {
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument(anyString())).thenReturn(null);
        NewsDocumentCache cache = new NewsDocumentCache(delegate, CACHE_PROPS);

        for (int i = 0; i < CACHE_PROPS.getNews().getMiss() + 50; i++) {
            cache.getDocument("guid-" + i);
        }

        assertThat(cache.missCount()).isEqualTo(CACHE_PROPS.getNews().getMiss());
    }

    /** A publish through docapi drops the remembered miss immediately, without waiting out the TTL. */
    @Test
    void updatingClearsARememberedMissSoTheArticleIsVisibleAtOnce() {
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument("g9")).thenReturn(null, "{\"v\":1}");
        when(delegate.updateDocument(anyString(), anyString())).thenReturn("g9");
        NewsDocumentCache cache = new NewsDocumentCache(delegate, CACHE_PROPS);

        assertThat(cache.getDocument("g9")).isNull();
        cache.updateDocument("g9", "{\"v\":1}");

        assertThat(cache.getDocument("g9")).contains("\"v\":1");
        assertThat(cache.missCount()).isZero();
    }

    /** Concurrent requests for the same uncached id must produce one database read, not one each. */
    @Test
    void aColdDocumentIsLoadedOnceEvenWhenManyRequestsArriveTogether() throws Exception {
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument("hot")).thenAnswer(invocation -> {
            Thread.sleep(60);
            return "{\"title\":\"hot\"}";
        });
        NewsDocumentCache cache = new NewsDocumentCache(delegate, CACHE_PROPS);

        runConcurrently(16, () -> cache.getDocument("hot"));

        verify(delegate, times(1)).getDocument("hot");
    }

    @Test
    void updatingADocumentEvictsItSoTheEditIsVisibleImmediately() {
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument("g1")).thenReturn("{\"v\":1}", "{\"v\":2}");
        when(delegate.updateDocument(anyString(), anyString())).thenReturn("g1");
        NewsDocumentCache cache = new NewsDocumentCache(delegate, CACHE_PROPS);

        assertThat(cache.getDocument("g1")).contains("\"v\":1");
        cache.updateDocument("g1", "{\"v\":2}");

        assertThat(cache.getDocument("g1")).contains("\"v\":2");
    }

    @Test
    void documentIdsAreMatchedCaseInsensitivelyBecauseGuidsAre() {
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument(anyString())).thenReturn("{\"title\":\"one\"}");
        NewsDocumentCache cache = new NewsDocumentCache(delegate, CACHE_PROPS);

        cache.getDocument("AABBCCDD-0000-1111-2222-333344445555");
        cache.getDocument("aabbccdd-0000-1111-2222-333344445555");

        assertThat(cache.size()).isEqualTo(1);
        org.mockito.Mockito.verify(delegate, org.mockito.Mockito.times(1)).getDocument(anyString());
    }

    // ---- daily eviction, and the SQL-outage rule -----------------------------------------------

    @Test
    void dailyEvictionClearsBothCachesWhenTheDatabaseIsReachable() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache queryCache = new NewsQueryCache(repo, CACHE_PROPS);
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument(anyString())).thenReturn("{\"a\":1}");
        NewsDocumentCache docCache = new NewsDocumentCache(delegate, CACHE_PROPS);
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(anyString(), any(Class.class))).thenReturn(1);

        queryCache.list("US", 0, 5);
        docCache.getDocument("g1");

        new NewsCacheEvictor(queryCache, docCache, jdbc).dailyEviction();

        assertThat(queryCache.sizes()).containsExactly(0, 0, 0, 0, 0, 0, 0, 0, 0);
        assertThat(docCache.size()).isZero();
    }

    @Test
    void evictionIsDeferredWhileSqlIsUnreachableSoStaleEntriesKeepServing() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache queryCache = new NewsQueryCache(repo, CACHE_PROPS);
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument(anyString())).thenReturn("{\"a\":1}");
        NewsDocumentCache docCache = new NewsDocumentCache(delegate, CACHE_PROPS);
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
        NewsQueryCache queryCache = new NewsQueryCache(repo, CACHE_PROPS);
        DocumentStore delegate = mock(DocumentStore.class);
        when(delegate.getDocument(anyString())).thenReturn("{\"a\":1}");
        NewsDocumentCache docCache = new NewsDocumentCache(delegate, CACHE_PROPS);
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
        assertThat(queryCache.sizes()).containsExactly(0, 0, 0, 0, 0, 0, 0, 0, 0);
        assertThat(docCache.size()).isZero();
    }

    @Test
    void theRetryTickDoesNothingWhenNoEvictionIsOwed() {
        CountingRepo repo = new CountingRepo(500);
        NewsQueryCache queryCache = new NewsQueryCache(repo, CACHE_PROPS);
        NewsDocumentCache docCache = new NewsDocumentCache(mock(DocumentStore.class), CACHE_PROPS);
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        queryCache.list("US", 0, 5);

        new NewsCacheEvictor(queryCache, docCache, jdbc).retryPendingEviction();

        // No probe, no clear — the cache is untouched on a healthy day.
        org.mockito.Mockito.verifyNoInteractions(jdbc);
        assertThat(queryCache.sizes()[0]).isEqualTo(NewsQueryCache.BUCKET_ROWS);
    }

    // ---- /news/photo ---------------------------------------------------------------------------

    @Test
    void photoIsReadOnceThenServedFromItsLruCache() {
        CountingRepo repo = new CountingRepo(0);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        cache.newsPhoto("abc");
        cache.newsPhoto("abc");
        cache.newsPhoto("ABC");   // same article, either spelling

        assertThat(repo.photoCalls.get()).isEqualTo(1);
        assertThat(cache.sizes()[8]).isEqualTo(1);
    }

    @Test
    void photoCacheKeepsOnlyTheLastTwentyFive() {
        NewsQueryCache cache = new NewsQueryCache(new CountingRepo(0), CACHE_PROPS);

        // The heaviest entries held here (~0.5 MB apiece live), so the bound is what keeps this
        // cache's heap cost knowable. Pin it.
        for (int i = 0; i < CACHE_PROPS.getNews().getPhoto() + 10; i++) {
            cache.newsPhoto("id-" + i);
        }

        assertThat(cache.sizes()[8]).isEqualTo(CACHE_PROPS.getNews().getPhoto());
    }

    // ---- /news/search --------------------------------------------------------------------------

    @Test
    void searchIsReadOnceThenServedFromItsLruCache() {
        CountingRepo repo = new CountingRepo(0);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        cache.search(query("walleye"));
        cache.search(query("walleye"));

        assertThat(repo.searchCalls.get()).isEqualTo(1);
        assertThat(cache.sizes()[5]).isEqualTo(1);
    }

    @Test
    void eachPageOfOneSearchIsItsOwnEntryAndTheTermIsNotCaseFolded() {
        CountingRepo repo = new CountingRepo(0);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        cache.search(new NewsSearchQuery("walleye", List.of(), null, 0, 25));
        cache.search(new NewsSearchQuery("walleye", List.of(), null, 25, 25));  // page 2
        cache.search(new NewsSearchQuery("walleye", List.of(), "CA", 0, 25));   // country filter
        // NOT folded to the entry above: NewsSearchPage echoes `query` back verbatim, so serving
        // "Walleye" from the "walleye" entry would change the response body.
        cache.search(new NewsSearchQuery("Walleye", List.of(), null, 0, 25));

        assertThat(repo.searchCalls.get()).isEqualTo(4);
        assertThat(cache.sizes()[5]).isEqualTo(4);
    }

    @Test
    void speciesIdOrderDoesNotSplitOneSearchAcrossTwoEntries() {
        CountingRepo repo = new CountingRepo(0);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        // The SQL ORs the three species slots and nothing echoes the ids back, so the two orderings
        // are the same result and must share one entry.
        cache.search(new NewsSearchQuery("pike", List.of("id-a", "id-b"), null, 0, 25));
        cache.search(new NewsSearchQuery("pike", List.of("id-b", "id-a"), null, 0, 25));

        assertThat(repo.searchCalls.get()).isEqualTo(1);
        assertThat(cache.sizes()[5]).isEqualTo(1);
    }

    @Test
    void searchCacheKeepsOnlyTheLastTwentyFive() {
        NewsQueryCache cache = new NewsQueryCache(new CountingRepo(0), CACHE_PROPS);

        for (int i = 0; i < CACHE_PROPS.getNews().getSearch() + 10; i++) {
            cache.search(query("term-" + i));
        }

        assertThat(cache.sizes()[5]).isEqualTo(CACHE_PROPS.getNews().getSearch());
    }

    // ---- /news/lake/{guid} ---------------------------------------------------------------------

    @Test
    void lakeNewsIsReadOnceThenServedFromItsLruCache() {
        CountingRepo repo = new CountingRepo(0);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        cache.lakeNews("fc0d917b-d053-11d8-92e2-080020a0f4c9", 12);
        cache.lakeNews("fc0d917b-d053-11d8-92e2-080020a0f4c9", 12);

        assertThat(repo.lakeCalls.get()).isEqualTo(1);
        assertThat(cache.sizes()[6]).isEqualTo(1);
    }

    @Test
    void aDifferentLimitIsADifferentLakeEntryRatherThanATruncatedHit() {
        CountingRepo repo = new CountingRepo(0);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        cache.lakeNews("fc0d917b-d053-11d8-92e2-080020a0f4c9", 12);
        cache.lakeNews("fc0d917b-d053-11d8-92e2-080020a0f4c9", 5);

        assertThat(repo.lakeCalls.get()).isEqualTo(2);
        assertThat(cache.sizes()[6]).isEqualTo(2);
    }

    @Test
    void lakeCacheKeepsOnlyTheLastTwentyFive() {
        NewsQueryCache cache = new NewsQueryCache(new CountingRepo(0), CACHE_PROPS);

        // Tens of thousands of water bodies exist; the bound is what stops this holding the catalogue.
        for (int i = 0; i < CACHE_PROPS.getWaterBody() + 10; i++) {
            cache.lakeNews("lake-" + i, 12);
        }

        assertThat(cache.sizes()[6]).isEqualTo(CACHE_PROPS.getWaterBody());
    }

    // ---- /news/fish/{guid} -----------------------------------------------------------------------

    @Test
    void fishNewsIsReadOnceThenServedFromItsLruCache() {
        CountingRepo repo = new CountingRepo(0);
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        cache.fishNews("a85ebf22-4ab9-4a91-a14a-cef6c8e64d97", 10);
        cache.fishNews("a85ebf22-4ab9-4a91-a14a-cef6c8e64d97", 10);

        assertThat(repo.fishCalls.get()).isEqualTo(1);
        assertThat(cache.sizes()[7]).isEqualTo(1);
    }

    @Test
    void fishCacheKeepsOnlyTheLastTwentyFive() {
        NewsQueryCache cache = new NewsQueryCache(new CountingRepo(0), CACHE_PROPS);

        for (int i = 0; i < CACHE_PROPS.getFish() + 10; i++) {
            cache.fishNews("fish-" + i, 10);
        }

        assertThat(cache.sizes()[7]).isEqualTo(CACHE_PROPS.getFish());
    }

    /**
     * The single-flight rule the list and home-page caches already keep has to hold for the five new
     * LRUs too — a burst on a cold export entry is precisely the ~2s read that must not be made five
     * times over.
     */
    @Test
    void aColdPerRequestEntryIsAlsoLoadedOnlyOnceUnderAStampede() throws Exception {
        SlowRepo repo = new SlowRepo();
        NewsQueryCache cache = new NewsQueryCache(repo, CACHE_PROPS);

        runConcurrently(16, () -> cache.exportNews("id-1"));
        assertThat(repo.exportCalls.get()).isEqualTo(1);

        runConcurrently(16, () -> cache.search(query("walleye")));
        assertThat(repo.searchCalls.get()).isEqualTo(1);

        runConcurrently(16, () -> cache.newsPhoto("id-1"));
        assertThat(repo.photoCalls.get()).isEqualTo(1);
    }
}
