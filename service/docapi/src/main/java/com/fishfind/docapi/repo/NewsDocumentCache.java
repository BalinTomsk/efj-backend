package com.fishfind.docapi.repo;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Caching decorator for the news {@link DocumentStore}, backing
 * {@code GET /api/v1/news/{guid}} (which reads {@code dbo.fn_news_doc}).
 *
 * <p>Keeps the <strong>last {@value #MAX_DOCUMENTS} documents requested</strong> in an access-ordered
 * LRU: a cache hit returns immediately, a miss reads through to the wrapped store and stores the
 * result. Documents can be large (the lead photo is embedded as base64), which is why the bound is
 * small.
 *
 * <h2>What is not cached</h2>
 * A {@code null} result — i.e. an unknown or unpublished id, which the controller turns into a 404 —
 * is deliberately <em>not</em> cached. Otherwise publishing an article would keep serving 404 for it
 * until the next daily clear.
 *
 * <h2>Writes</h2>
 * {@code add} never populates the cache (the document is reachable only once someone asks for it).
 * {@code update} evicts the affected id, so an edit is visible on the next read instead of waiting
 * for the daily clear.
 *
 * <h2>Eviction</h2>
 * Entries do not expire individually. {@link #clear()} empties the cache and is driven once a day by
 * {@link NewsCacheEvictor}, which skips the clear while SQL is unreachable.
 */
public class NewsDocumentCache implements DocumentStore {

    private static final Logger log = LoggerFactory.getLogger(NewsDocumentCache.class);

    /** How many recently-requested documents to keep. */
    static final int MAX_DOCUMENTS = 25;

    private final DocumentStore delegate;

    private final Map<String, String> documents = Collections.synchronizedMap(
            new LinkedHashMap<>(16, 0.75f, true) {
                @Override
                protected boolean removeEldestEntry(Map.Entry<String, String> eldest) {
                    return size() > MAX_DOCUMENTS;
                }
            });

    public NewsDocumentCache(DocumentStore delegate) {
        this.delegate = delegate;
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
        String loaded = delegate.getDocument(id);
        if (loaded != null) {
            documents.put(key, loaded);
        }
        return loaded;
    }

    @Override
    public String addDocument(String json) {
        return delegate.addDocument(json);
    }

    @Override
    public String updateDocument(String id, String json) {
        String affected = delegate.updateDocument(id, json);
        if (id != null) {
            documents.remove(normalize(id));
        }
        return affected;
    }

    /**
     * Drops every cached document. The next request for each reads through to the database again.
     */
    public void clear() {
        documents.clear();
        log.info("News document cache cleared");
    }

    /** Cached document count, for logging and tests. */
    int size() {
        return documents.size();
    }

    /** GUIDs are case-insensitive, so key on a single casing to avoid duplicate entries. */
    private static String normalize(String id) {
        return id.trim().toLowerCase(java.util.Locale.ROOT);
    }
}
