package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.config.NewsCacheProperties;
import com.fishfind.docapi.web.NewsController.NewsFishPage;
import com.fishfind.docapi.web.NewsController.NewsLakePage;
import com.fishfind.docapi.web.NewsController.NewsListItem;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;
import com.fishfind.docapi.web.NewsController.NewsSearchQuery;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Supplier;

/**
 * Caching decorator for {@link NewsQueryRepository}: <strong>every</strong> news read endpoint is
 * served from memory, falling through to the wrapped repository (and refilling) on a miss.
 *
 * <h2>What is held</h2>
 * <ul>
 *   <li><strong>US</strong> — the latest {@value #BUCKET_ROWS} rows, fetched once;</li>
 *   <li><strong>CA</strong> — the latest {@value #BUCKET_ROWS} rows, fetched once;</li>
 *   <li><strong>everything else</strong> — a bounded LRU of whole responses
 *       ({@code docapi.cache.news.list}, default 100), keyed by {@code country|offset|limit}. This
 *       covers the unfiltered all-countries request ({@code country} absent) and any other specific
 *       country.</li>
 *   <li><strong>default</strong> — the single assembled home page;</li>
 *   <li><strong>export, search, lake, fish, photo</strong> — one bounded LRU each of whole responses,
 *       added 2026-09-17, default 25 apiece and each separately configurable under
 *       {@code docapi.cache}. See below.</li>
 * </ul>
 *
 * <p>US and CA are held as <em>rows</em> rather than per-request responses because
 * {@code dbo.fn_news_list} already works in units of 100 (it pads a non-CA country with CA news up to
 * 100), so one fetch answers every page size and offset within those rows.
 *
 * <h2>The five per-request LRUs (2026-09-17)</h2>
 * {@code /news/export/{id}}, {@code /news/search}, {@code /news/lake/{guid}},
 * {@code /news/fish/{guid}} and {@code /news/photo/{id}} read through to the database on
 * <em>every</em> request until this change; the class doc used to argue that for each of them, on the
 * grounds that their key spaces are large (tens of thousands of water bodies, free-form search terms)
 * or their payloads heavy (base64 photos), so a bounded LRU would mostly miss while costing heap.
 *
 * <p>That reasoning weighed the <em>miss</em> and ignored what a miss costs here. The database is a
 * remote Winhost MySQL reached over the public internet from the droplet, on a pool that holds
 * <strong>no idle connection</strong> ({@code minimumIdle=0}, {@code idleTimeout=15s} — see
 * {@code JdbcStoreConfig}), so a read arriving on a quiet minute pays a full TCP connect plus
 * authentication before the query even starts. Measured through the gateway, {@code /news/export/{id}}
 * took ~2 s per call. A repeat request answered from memory is worth having even at a modest hit
 * rate, and the alternative is not "one cheap query" — it is a cold connection to another continent.
 *
 * <p><strong>What 25 entries cost.</strong> Three of the five hold small values
 * (a search page and the lake/fish panels are a few KB each). Two do not, and their arithmetic is
 * worth doing rather than guessing:
 * <ul>
 *   <li>{@code photos} — raw lead-photo blobs. One measured live on 2026-09-12 was 525,222 bytes, so
 *       a full LRU is on the order of <strong>13 MB</strong>.</li>
 *   <li>{@code exportDocs} — the parsed interchange document, the largest response this service
 *       serves. One measured live on 2026-09-17 was 512,506 bytes <em>on the wire</em>; held here it
 *       is a {@link JsonNode} tree whose base64 photo strings cost two bytes per character, so
 *       roughly 1–1.5 MB of heap apiece and a full LRU on the order of <strong>25–35 MB</strong>.</li>
 * </ul>
 * The container sets no {@code -Xmx} ({@code JAVA_OPTS=""}), so the JVM takes its default quarter of
 * the container's memory. 25 is the agreed size, not a measured ceiling: it is the first number to
 * lower if docapi starts pressuring heap — and since 2026-09-18 it is configuration rather than a
 * constant ({@link com.fishfind.docapi.config.NewsCacheProperties}), so lowering it is an environment
 * variable rather than a rebuild and a redeploy.
 *
 * <p><strong>Misses are not remembered</strong>, unlike {@link NewsDocumentCache}, which caches
 * "unknown id" answers for a minute so a crawler walking guids cannot hammer MySQL. That does not
 * need repeating here: {@code /news/export} and {@code /news/photo} are both listed in cproxy's
 * {@code CPROXY_DAYKEY_PATHS}, so an id-guessing scanner never reaches them without a credential, and
 * search/lake/fish answer a cheap narrow-column read rather than a BLOB fetch. A {@code null} is
 * therefore passed straight back to the caller and nothing is stored.
 *
 * <h2>Serving a page from a bucket</h2>
 * A window {@code [offset, offset+limit)} is served from a bucket when it lies entirely inside the
 * rows held, or when the bucket already holds the whole result set ({@code rows >= total}) — in which
 * case a window past the end correctly yields an empty page. A window reaching past the cached rows
 * while more exist in the database falls through to the keyed LRU above, so a deep page is loaded
 * once and then served from memory like any other request (until 2026-09-02 it read through
 * <em>uncached</em> on every request, which meant a bot walking the pager hit the database on every
 * hit — the one hole in "read from cache, touch the database only when the cache is empty").
 *
 * <h2>Eviction</h2>
 * Nothing expires on its own. {@link #clear()} drops everything — all nine entries reported by
 * {@link #sizes()} — and is driven once a day by {@link NewsCacheEvictor}, which <strong>skips the
 * clear while SQL is unreachable</strong> so stale data keeps being served instead of leaving the
 * cache empty and unfillable.
 *
 * <h2>Thread safety and single-flight</h2>
 * Buckets are {@link AtomicReference}s and every LRU is a synchronized map. A cold entry is loaded
 * <strong>once</strong>: the loader runs under a striped lock with a double-check (see
 * {@link #cached}), so N concurrent requests for the same empty entry produce one database read and N
 * answers, not N reads. This deliberately holds a lock across the database call — for a remote MySQL
 * whose connection pool is 5 and whose socket timeout is generous, letting a stampede through would
 * exhaust the pool and make every caller wait anyway, only after doing the same work many times over.
 * Locks are striped ({@value #LOAD_STRIPES} of them) rather than one per key so the map cannot grow
 * without bound as offsets vary; two unrelated keys occasionally sharing a stripe just serialises two
 * cold loads.
 */
public class NewsQueryCache implements NewsQueryRepository {

    private static final Logger log = LoggerFactory.getLogger(NewsQueryCache.class);

    /** Rows held for each dedicated country bucket (US, CA) — matches fn_news_list's own unit of 100. */
    static final int BUCKET_ROWS = 100;
    /** Number of striped load locks — bounded, unlike a lock-per-key map keyed on arbitrary offsets. */
    static final int LOAD_STRIPES = 16;

    private static final String US = "US";
    private static final String CA = "CA";

    /** Cache key for the single assembled home page. */
    private static final String DEFAULT_KEY = "default";

    private final NewsQueryRepository delegate;

    /** Guards cold loads so each empty entry is filled by exactly one request. */
    private final Object[] loadLocks = new Object[LOAD_STRIPES];

    private final AtomicReference<CachedRows> usBucket = new AtomicReference<>();
    private final AtomicReference<CachedRows> caBucket = new AtomicReference<>();
    private final AtomicReference<JsonNode> defaultPage = new AtomicReference<>();

    private final Map<String, NewsListPage> otherPages;
    private final Map<String, JsonNode> exportDocs;
    private final Map<String, NewsSearchPage> searches;
    private final Map<String, NewsLakePage> lakePages;
    private final Map<String, NewsFishPage> fishPages;
    private final Map<String, byte[]> photos;

    public NewsQueryCache(NewsQueryRepository delegate, NewsCacheProperties properties) {
        this.delegate = delegate;
        NewsCacheProperties.News newsBounds = properties.getNews();
        this.otherPages = boundedLru(newsBounds.getList());
        this.exportDocs = boundedLru(newsBounds.getExport());
        this.searches = boundedLru(newsBounds.getSearch());
        this.photos = boundedLru(newsBounds.getPhoto());
        this.lakePages = boundedLru(properties.getWaterBody());
        this.fishPages = boundedLru(properties.getFish());
        for (int i = 0; i < LOAD_STRIPES; i++) {
            loadLocks[i] = new Object();
        }
    }

    @Override
    public NewsListPage list(String country, int offset, int limit) {
        String key = country == null ? null : country.toUpperCase(Locale.ROOT);

        if (US.equals(key) || CA.equals(key)) {
            NewsListPage sliced = sliceFromBucket(key, offset, limit);
            if (sliced != null) {
                return sliced;
            }
            // Window reaches past the cached rows while more exist in the database — deep paging.
            // Fall through to the keyed cache so the second request for that page is a cache hit.
        }
        return cachedPage(key, offset, limit);
    }

    @Override
    public JsonNode defaultNews() {
        JsonNode cached = defaultPage.get();
        if (cached != null) {
            return cached;
        }
        synchronized (lockFor(DEFAULT_KEY)) {
            // Re-check: another request may have filled it while this one waited for the lock.
            JsonNode filled = defaultPage.get();
            if (filled != null) {
                return filled;
            }
            JsonNode loaded = delegate.defaultNews();
            defaultPage.set(loaded);
            return loaded;
        }
    }

    /**
     * Serves a window from the US or CA row bucket, loading that bucket once if it is cold.
     *
     * @return the page, or {@code null} when the window reaches past the cached rows while more exist
     *         in the database — the caller then falls back to the keyed cache
     */
    private NewsListPage sliceFromBucket(String key, int offset, int limit) {
        AtomicReference<CachedRows> bucket = US.equals(key) ? usBucket : caBucket;
        CachedRows rows = bucket.get();
        if (rows == null) {
            synchronized (lockFor(key)) {
                rows = bucket.get();
                if (rows == null) {
                    NewsListPage loaded = delegate.list(key, 0, BUCKET_ROWS);
                    rows = new CachedRows(List.copyOf(loaded.items()), loaded.total());
                    bucket.set(rows);
                }
            }
        }
        return rows.slice(offset, limit);
    }

    /**
     * Serves one whole response from the bounded keyed cache, loading it once if it is cold. Covers
     * the unfiltered all-countries request, any country without its own bucket, and US/CA pages that
     * reach past their bucket.
     */
    private NewsListPage cachedPage(String key, int offset, int limit) {
        String cacheKey = (key == null ? "*" : key) + "|" + offset + "|" + limit;
        return cached(otherPages, cacheKey, () -> delegate.list(key, offset, limit));
    }

    /**
     * The lead photo, held for the last {@code docapi.cache.news.photo} ids asked for (default 25).
     *
     * <p>These are the heaviest raw values in this class (~0.5 MB apiece measured live). They are
     * cached anyway because the read behind them is a single-row BLOB fetch across the public
     * internet, on a pool that keeps no idle connection — and because a caller only reaches this
     * endpoint after its own cache has missed, which is precisely when the slow path hurts most. The
     * response the controller builds carries a 7-day {@code max-age} and an ETag, so a browser that
     * already holds the bytes never gets this far.
     */
    @Override
    public byte[] newsPhoto(String id) {
        return cached(photos, idKey(id), () -> delegate.newsPhoto(id));
    }

    /**
     * The interchange document, held for the last {@code docapi.cache.news.export} ids asked for (default 25).
     *
     * <p>The single most expensive read this service makes — {@code sp_news_doc_export} base64-encodes
     * three LONGBLOB photo columns into one JSON value — and, measured through the gateway on
     * 2026-09-17, ~2 s per call. The admin round trip that uses it (export here, re-import in
     * {@code Editor/AddNews.aspx}) repeats the same id often enough for a small LRU to pay, and a
     * repeat is exactly the case that used to cost another two seconds.
     */
    @Override
    public JsonNode exportNews(String id) {
        return cached(exportDocs, idKey(id), () -> delegate.exportNews(id));
    }

    /**
     * One search page, held for the last {@code docapi.cache.news.search} distinct queries (default 25).
     *
     * <p>The key space is open-ended, which is why this used to read through. What makes a bounded
     * LRU worth it anyway is that real traffic is not uniform over that space: {@code News.aspx}'s
     * search box produces the same handful of terms repeatedly, and a numbered pager re-issues the
     * <em>identical</em> query for every page the reader steps through.
     */
    @Override
    public NewsSearchPage search(NewsSearchQuery request) {
        return cached(searches, searchKey(request), () -> delegate.search(request));
    }

    /**
     * One water body's news panel, held for the last {@code docapi.cache.water-body} {@code guid|limit}
     * pairs (default 25).
     *
     * <p>There are tens of thousands of water bodies, so most of that key space will never be in
     * memory — but page views are not spread evenly across it either, and this is a public page whose
     * repeat and refresh traffic lands on the same few ids. The read it fronts stays deliberately
     * cheap (a dozen short rows, no photo column — see {@code MySqlNewsQueryRepository.LAKE_SQL}), so
     * a miss is no worse than it ever was.
     */
    @Override
    public NewsLakePage lakeNews(String lakeId, int limit) {
        return cached(lakePages, lakeId + "|" + limit, () -> delegate.lakeNews(lakeId, limit));
    }

    /**
     * One species' news panel — {@link #lakeNews}'s counterpart, and a better fit for a bounded LRU
     * than it is: the species key space is about a thousand entries rather than tens of thousands.
     */
    @Override
    public NewsFishPage fishNews(String fishId, int limit) {
        return cached(fishPages, fishId + "|" + limit, () -> delegate.fishNews(fishId, limit));
    }

    /**
     * A write: create the article via the delegate, then drop every cached entry so the new article
     * shows up on the next read — it can appear in a list, the home page, a search, and both panels.
     */
    @Override
    public String importNews(String json) {
        String newId = delegate.importNews(json);
        clear();
        return newId;
    }

    /**
     * Drops every cached entry. The next request for each repopulates it from the database.
     */
    public void clear() {
        usBucket.set(null);
        caBucket.set(null);
        defaultPage.set(null);
        otherPages.clear();
        exportDocs.clear();
        searches.clear();
        lakePages.clear();
        fishPages.clear();
        photos.clear();
        log.info("News query cache cleared (list buckets, other-request entries, default page, "
                + "export/search/lake/fish/photo entries)");
    }

    /**
     * Cached entry counts, for logging and tests:
     * {@code [us, ca, other, default, export, search, lake, fish, photo]}.
     */
    int[] sizes() {
        return new int[]{
                usBucket.get() == null ? 0 : usBucket.get().rows().size(),
                caBucket.get() == null ? 0 : caBucket.get().rows().size(),
                otherPages.size(),
                defaultPage.get() == null ? 0 : 1,
                exportDocs.size(),
                searches.size(),
                lakePages.size(),
                fishPages.size(),
                photos.size()
        };
    }

    /**
     * Serves {@code key} from {@code cache}, loading it exactly once when it is cold: the loader runs
     * under a striped lock with a double-check, so a burst on an empty entry produces one database
     * read and N answers rather than N reads.
     *
     * <p>A {@code null} load — an unknown id — is returned but <strong>not</strong> stored; see the
     * class doc on why misses are not remembered here.
     */
    private <V> V cached(Map<String, V> cache, String key, Supplier<V> loader) {
        V hit = cache.get(key);
        if (hit != null) {
            return hit;
        }
        synchronized (lockFor(key)) {
            // Re-check: another request may have filled it while this one waited for the lock.
            V filled = cache.get(key);
            if (filled != null) {
                return filled;
            }
            V loaded = loader.get();
            if (loaded != null) {
                cache.put(key, loaded);
            }
            return loaded;
        }
    }

    /** An access-ordered LRU, synchronized, that evicts its eldest entry past {@code maxEntries}. */
    private static <V> Map<String, V> boundedLru(int maxEntries) {
        return Collections.synchronizedMap(new LinkedHashMap<String, V>(16, 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<String, V> eldest) {
                return size() > maxEntries;
            }
        });
    }

    /**
     * The cache key for a per-article id. Lower-cased so one article is one entry whatever case the
     * caller sent — the {@code news_id} column's collation is case-insensitive, so the two spellings
     * genuinely resolve to the same row. The delegate still receives the id exactly as it arrived.
     */
    private static String idKey(String id) {
        return id == null ? "" : id.toLowerCase(Locale.ROOT);
    }

    /**
     * The cache key for one search.
     *
     * <p>The term is <strong>not</strong> case-folded, even though the {@code LIKE} behind it is
     * case-insensitive and folding would merge more requests onto one entry: {@link NewsSearchPage}
     * echoes {@code query} back verbatim, so serving a search for {@code "Walleye"} out of the entry
     * loaded for {@code "walleye"} would change the response body. The species ids <em>are</em>
     * sorted, because nothing echoes them and the SQL ORs the three slots, so two orderings of the
     * same ids are the same result.
     */
    private static String searchKey(NewsSearchQuery request) {
        List<String> fishIds = new ArrayList<>(request.fishIds());
        Collections.sort(fishIds);
        return request.query()
                + "|" + String.join(",", fishIds)
                + "|" + (request.country() == null ? "*" : request.country())
                + "|" + request.offset()
                + "|" + request.limit();
    }

    /** The striped lock guarding cold loads for {@code key}. */
    private Object lockFor(String key) {
        return loadLocks[Math.floorMod(key.hashCode(), LOAD_STRIPES)];
    }

    /**
     * The leading rows of one country's ordered list plus the grand total the database reported, so a
     * page sliced out of it still carries an accurate {@code total} for the pager.
     */
    private record CachedRows(List<NewsListItem> rows, long total) {

        /**
         * @return the requested page, or {@code null} when this bucket cannot answer it and the
         *         caller must read through to the database
         */
        NewsListPage slice(int offset, int limit) {
            boolean holdsEverything = rows.size() >= total;
            boolean windowInsideRows = (long) offset + limit <= rows.size();
            if (!windowInsideRows && !holdsEverything) {
                return null;
            }
            if (offset >= rows.size()) {
                return new NewsListPage(List.of(), total, offset, limit);
            }
            int end = (int) Math.min((long) offset + limit, rows.size());
            return new NewsListPage(new ArrayList<>(rows.subList(offset, end)), total, offset, limit);
        }
    }
}
