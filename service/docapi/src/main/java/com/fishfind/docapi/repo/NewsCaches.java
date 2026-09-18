package com.fishfind.docapi.repo;

/**
 * Drops docapi's in-process news caches after a write, so the next read goes back to the database.
 *
 * <p>Both caches are needed: {@link NewsQueryCache} holds the list pages, the home page, searches,
 * exports and the lake/fish panels, any of which a write can change; {@link NewsDocumentCache} holds
 * single documents and remembered 404s, and a remembered 404 for an id that was just created would
 * otherwise hide it for the rest of its TTL. Neither can be targeted per id from the write side, and
 * writes are rare, so both are cleared whole.
 *
 * <p>Takes the beans by interface and checks the type, because under the default (no database)
 * profile they are plain uncached implementations and there is nothing to clear -- then this is a
 * no-op. Shared by every news write path: {@code NewsDocumentService} ({@code POST}/{@code PUT}
 * {@code /api/v1/news}, {@code /import}) and {@code NewsAdminController}.
 */
public final class NewsCaches {

    private NewsCaches() {
    }

    /** Clears whichever of the two news caches are actually present. */
    public static void evictAll(NewsQueryRepository queryRepository, DocumentStore newsStore) {
        if (queryRepository instanceof NewsQueryCache cache) {
            cache.clear();
        }
        if (newsStore instanceof NewsDocumentCache cache) {
            cache.clear();
        }
    }
}
