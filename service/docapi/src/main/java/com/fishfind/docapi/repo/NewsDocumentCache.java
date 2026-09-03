package com.fishfind.docapi.repo;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.LongSupplier;

/**
 * Caching decorator for the news {@link DocumentStore}, backing
 * {@code GET /api/v1/news/{guid}} (which reads {@code dbo.fn_news_doc}).
 *
 * <p>Keeps the <strong>last {@value #MAX_DOCUMENTS} documents requested</strong> in an access-ordered
 * LRU: a cache hit returns immediately, a miss reads through to the wrapped store and stores the
 * result. Documents can be large (the lead photo is embedded as base64), which is why the bound is
 * small.
 *
 * <h2>Misses are remembered too, but only briefly</h2>
 * A {@code null} result — an unknown or unpublished id, which the controller turns into a 404 — is
 * remembered for {@value #MISS_TTL_MS} ms in a separate bounded map. Without that, every request for
 * an id that does not exist reached the database: a crawler or scanner walking guids could hammer the
 * remote MySQL indefinitely, and no amount of caching of real articles would stop it. The short TTL
 * is the whole point of keeping misses separate from documents: an article published <em>outside</em>
 * docapi (the portal's {@code AddNews.aspx} writes straight to the database, so no eviction reaches
 * us) becomes visible within a minute rather than at the next daily clear. This is the only entry in
 * either news cache that expires on its own.
 *
 * <h2>Writes</h2>
 * {@code add} never populates the cache (the document is reachable only once someone asks for it).
 * {@code update} evicts the affected id from both maps, so an edit — or a first publish that goes
 * through docapi — is visible on the next read instead of waiting out the TTL or the daily clear.
 *
 * <h2>Eviction and single-flight</h2>
 * Documents do not expire individually; {@link #clear()} empties both maps and is driven once a day
 * by {@link NewsCacheEvictor}, which skips the clear while SQL is unreachable. A cold id is loaded
 * <strong>once</strong>: the read runs under a striped lock with a double-check, so concurrent
 * requests for the same uncached id produce one database read rather than one each.
 */
public class NewsDocumentCache implements DocumentStore {

    private static final Logger log = LoggerFactory.getLogger(NewsDocumentCache.class);

    /** How many recently-requested documents to keep. */
    static final int MAX_DOCUMENTS = 25;
    /** How many recently-requested unknown ids to remember. Small entries, so a larger bound. */
    static final int MAX_MISSES = 500;
    /** How long an "unknown id" answer is trusted before the database is asked again. */
    static final long MISS_TTL_MS = 60_000L;
    /** Number of striped load locks, bounded so arbitrary ids cannot grow a lock map. */
    static final int LOAD_STRIPES = 16;

    private final DocumentStore delegate;
    /** Current time in millis — a seam so the TTL is testable without sleeping. */
    private final LongSupplier clock;

    /** Guards cold reads so each uncached id is loaded by exactly one request. */
    private final Object[] loadLocks = new Object[LOAD_STRIPES];

    private final Map<String, String> documents = Collections.synchronizedMap(
            new LinkedHashMap<>(16, 0.75f, true) {
                @Override
                protected boolean removeEldestEntry(Map.Entry<String, String> eldest) {
                    return size() > MAX_DOCUMENTS;
                }
            });

    /** Ids known not to resolve, with the timestamp at which that was established. */
    private final Map<String, Long> misses = Collections.synchronizedMap(
            new LinkedHashMap<>(16, 0.75f, true) {
                @Override
                protected boolean removeEldestEntry(Map.Entry<String, Long> eldest) {
                    return size() > MAX_MISSES;
                }
            });

    public NewsDocumentCache(DocumentStore delegate) {
        this(delegate, System::currentTimeMillis);
    }

    NewsDocumentCache(DocumentStore delegate, LongSupplier clock) {
        this.delegate = delegate;
        this.clock = clock;
        for (int i = 0; i < LOAD_STRIPES; i++) {
            loadLocks[i] = new Object();
        }
    }

    @Override
    public String getDocument(String id) {
        if (id == null) {
            return delegate.getDocument(null);
        }
        String key = normalize(id);
        String cached = documents.get(key);
        if (cached != null) {
            return cached;
        }
        if (missIsFresh(key)) {
            return null;
        }
        synchronized (lockFor(key)) {
            // Re-check both maps: another request may have resolved this id while this one waited.
            String filled = documents.get(key);
            if (filled != null) {
                return filled;
            }
            if (missIsFresh(key)) {
                return null;
            }
            String loaded = delegate.getDocument(id);
            if (loaded != null) {
                documents.put(key, loaded);
                misses.remove(key);
            } else {
                misses.put(key, clock.getAsLong());
            }
            return loaded;
        }
    }

    /** Whether this id is known not to resolve and that answer is still inside its TTL. */
    private boolean missIsFresh(String key) {
        Long missedAt = misses.get(key);
        if (missedAt == null) {
            return false;
        }
        if (clock.getAsLong() - missedAt < MISS_TTL_MS) {
            return true;
        }
        misses.remove(key);
        return false;
    }

    /** The striped lock guarding cold reads for {@code key}. */
    private Object lockFor(String key) {
        return loadLocks[Math.floorMod(key.hashCode(), LOAD_STRIPES)];
    }

    @Override
    public String addDocument(String json) {
        return delegate.addDocument(json);
    }

    @Override
    public String updateDocument(String id, String json) {
        String affected = delegate.updateDocument(id, json);
        if (id != null) {
            String key = normalize(id);
            documents.remove(key);
            // Also drop any "unknown id" answer: a first publish through docapi must be visible at
            // once rather than 404-ing for the rest of the TTL.
            misses.remove(key);
        }
        return affected;
    }

    /**
     * Drops every cached document and every remembered miss. The next request for each reads through
     * to the database again.
     */
    public void clear() {
        documents.clear();
        misses.clear();
        log.info("News document cache cleared");
    }

    /** Cached document count, for logging and tests. */
    int size() {
        return documents.size();
    }

    /** Remembered-miss count, for tests. */
    int missCount() {
        return misses.size();
    }

    /** GUIDs are case-insensitive, so key on a single casing to avoid duplicate entries. */
    private static String normalize(String id) {
        return id.trim().toLowerCase(java.util.Locale.ROOT);
    }
}
