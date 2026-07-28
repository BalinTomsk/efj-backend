package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.web.NewsController.NewsListItem;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Caching decorator for {@link NewsQueryRepository}: serves {@code /api/v1/news/list} and
 * {@code /api/v1/news/default} from memory, falling through to the wrapped repository (and refilling)
 * on a miss.
 *
 * <h2>What is held</h2>
 * <ul>
 *   <li><strong>US</strong> — the latest {@value #BUCKET_ROWS} rows, fetched once;</li>
 *   <li><strong>CA</strong> — the latest {@value #BUCKET_ROWS} rows, fetched once;</li>
 *   <li><strong>everything else</strong> — a bounded LRU of {@value #OTHER_ENTRIES} whole responses,
 *       keyed by {@code country|offset|limit}. This covers the unfiltered all-countries request
 *       ({@code country} absent) and any other specific country.</li>
 *   <li><strong>default</strong> — the single assembled home page.</li>
 * </ul>
 *
 * <p>US and CA are held as <em>rows</em> rather than per-request responses because
 * {@code dbo.fn_news_list} already works in units of 100 (it pads a non-CA country with CA news up to
 * 100), so one fetch answers every page size and offset within those rows.
 *
 * <h2>Serving a page from a bucket</h2>
 * A window {@code [offset, offset+limit)} is served from a bucket when it lies entirely inside the
 * rows held, or when the bucket already holds the whole result set ({@code rows >= total}) — in which
 * case a window past the end correctly yields an empty page. A window reaching past the cached rows
 * while more exist in the database falls through to the delegate <em>uncached</em>, so deep paging
 * stays correct rather than silently truncated.
 *
 * <h2>Eviction</h2>
 * Nothing expires on its own. {@link #clear()} drops everything and is driven once a day by
 * {@link NewsCacheEvictor}, which <strong>skips the clear while SQL is unreachable</strong> so stale
 * data keeps being served instead of leaving the cache empty and unfillable.
 *
 * <p>Thread-safe: buckets are {@link AtomicReference}s and the LRU is a synchronized map. A miss may
 * be loaded concurrently by two requests; the loads are idempotent reads, so the last writer wins and
 * no locking is held across a database call.
 */
public class NewsQueryCache implements NewsQueryRepository {

    private static final Logger log = LoggerFactory.getLogger(NewsQueryCache.class);

    /** Rows held for each dedicated country bucket (US, CA) — matches fn_news_list's own unit of 100. */
    static final int BUCKET_ROWS = 100;
    /** Upper bound on cached responses for every other request. */
    static final int OTHER_ENTRIES = 100;

    private static final String US = "US";
    private static final String CA = "CA";

    private final NewsQueryRepository delegate;

    private final AtomicReference<CachedRows> usBucket = new AtomicReference<>();
    private final AtomicReference<CachedRows> caBucket = new AtomicReference<>();
    private final AtomicReference<JsonNode> defaultPage = new AtomicReference<>();

    private final Map<String, NewsListPage> otherPages = Collections.synchronizedMap(
            new LinkedHashMap<>(16, 0.75f, true) {
                @Override
                protected boolean removeEldestEntry(Map.Entry<String, NewsListPage> eldest) {
                    return size() > OTHER_ENTRIES;
                }
            });

    public NewsQueryCache(NewsQueryRepository delegate) {
        this.delegate = delegate;
    }

    @Override
    public NewsListPage list(String country, int offset, int limit) {
        String key = country == null ? null : country.toUpperCase(Locale.ROOT);

        if (US.equals(key) || CA.equals(key)) {
            AtomicReference<CachedRows> bucket = US.equals(key) ? usBucket : caBucket;
            CachedRows rows = bucket.get();
            if (rows == null) {
                NewsListPage loaded = delegate.list(key, 0, BUCKET_ROWS);
                rows = new CachedRows(List.copyOf(loaded.items()), loaded.total());
                bucket.set(rows);
            }
            NewsListPage sliced = rows.slice(offset, limit);
            if (sliced != null) {
                return sliced;
            }
            // Window reaches past the cached rows while more exist in the DB — deep paging, read through.
            return delegate.list(key, offset, limit);
        }

        String otherKey = (key == null ? "*" : key) + "|" + offset + "|" + limit;
        NewsListPage cached = otherPages.get(otherKey);
        if (cached != null) {
            return cached;
        }
        NewsListPage loaded = delegate.list(key, offset, limit);
        otherPages.put(otherKey, loaded);
        return loaded;
    }

    @Override
    public JsonNode defaultNews() {
        JsonNode cached = defaultPage.get();
        if (cached != null) {
            return cached;
        }
        JsonNode loaded = delegate.defaultNews();
        defaultPage.set(loaded);
        return loaded;
    }

    /**
     * Drops every cached entry. The next request for each repopulates it from the database.
     */
    public void clear() {
        usBucket.set(null);
        caBucket.set(null);
        defaultPage.set(null);
        otherPages.clear();
        log.info("News query cache cleared (list buckets, other-request entries, default page)");
    }

    /** Cached entry counts, for logging and tests: {@code [us, ca, other, default]}. */
    int[] sizes() {
        return new int[]{
                usBucket.get() == null ? 0 : usBucket.get().rows().size(),
                caBucket.get() == null ? 0 : caBucket.get().rows().size(),
                otherPages.size(),
                defaultPage.get() == null ? 0 : 1
        };
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
