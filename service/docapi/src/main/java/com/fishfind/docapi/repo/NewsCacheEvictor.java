package com.fishfind.docapi.repo;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;

import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.BooleanSupplier;

/**
 * Clears the news caches once a day, at <strong>00:00 UTC</strong>.
 *
 * <h2>Why this is not just a TTL</h2>
 * The clear is <strong>skipped while the news database is unreachable</strong> (since 1.44.0: csnews-env and its
 * MySQL, probed by {@code GET /api/v1/csnews/ping}; before, SQL Server). Clearing during an outage
 * would be the worst possible moment: every subsequent request would miss, fail to reload, and return
 * 500 — turning a database outage into a total content outage. Keeping the stale entries means the
 * service keeps answering from memory until the database comes back.
 *
 * <p>A skipped clear is not lost. {@link #dailyEviction()} raises a pending flag, and
 * {@link #retryPendingEviction()} re-attempts every {@value #RETRY_INTERVAL_MS} ms until a probe
 * succeeds — so the caches are refreshed as soon as the connection is restored, rather than waiting
 * for the next day's tick.
 *
 * <p>Reachability is decided by a real round trip ({@link CsNewsClient#reachable()}: csnews-env runs
 * {@code SELECT 1} on MySQL) rather than by inspecting a circuit breaker, so the probe reflects the database
 * itself. It bypasses the breaker on purpose: a failure here is an expected, handled outcome.
 */
public class NewsCacheEvictor {

    private static final Logger log = LoggerFactory.getLogger(NewsCacheEvictor.class);

    /** How often a deferred clear is retried while the database is down. */
    static final long RETRY_INTERVAL_MS = 5 * 60 * 1000L;

    private final NewsQueryCache queryCache;
    private final NewsDocumentCache documentCache;
    private final BooleanSupplier newsReachable;

    /** True when a daily clear was due but deferred because the database was unreachable. */
    private final AtomicBoolean evictionPending = new AtomicBoolean(false);

    /** @param newsReachable true when the news database answers (production: {@link CsNewsClient#reachable()}) */
    public NewsCacheEvictor(NewsQueryCache queryCache, NewsDocumentCache documentCache, BooleanSupplier newsReachable) {
        this.queryCache = queryCache;
        this.documentCache = documentCache;
        this.newsReachable = newsReachable;
    }

    /**
     * The daily clear, at midnight UTC. If the database is unreachable the clear is deferred rather
     * than performed, and {@link #retryPendingEviction()} takes over.
     */
    @Scheduled(cron = "0 0 0 * * *", zone = "UTC")
    public void dailyEviction() {
        evictionPending.set(true);
        attemptEviction("daily");
    }

    /**
     * Re-attempts a deferred clear. Does nothing unless a clear is actually pending, so this is a
     * no-op tick on a healthy day.
     */
    @Scheduled(fixedDelay = RETRY_INTERVAL_MS)
    public void retryPendingEviction() {
        if (evictionPending.get()) {
            attemptEviction("deferred");
        }
    }

    private void attemptEviction(String reason) {
        if (!databaseReachable()) {
            log.warn("News cache {} eviction deferred — news database unreachable; serving stale entries "
                    + "and retrying every {} ms until the connection is restored", reason, RETRY_INTERVAL_MS);
            return;
        }
        queryCache.clear();
        documentCache.clear();
        evictionPending.set(false);
        log.info("News caches cleared ({} eviction); next request repopulates them from the database", reason);
    }

    private boolean databaseReachable() {
        try {
            return newsReachable.getAsBoolean();
        } catch (RuntimeException ex) {
            log.debug("News reachability probe failed: {}", ex.toString());
            return false;
        }
    }

    /** Whether a clear is currently deferred, for logging and tests. */
    boolean isEvictionPending() {
        return evictionPending.get();
    }
}
