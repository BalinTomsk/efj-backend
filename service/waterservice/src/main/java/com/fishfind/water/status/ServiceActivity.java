package com.fishfind.water.status;

import org.springframework.stereotype.Component;

import java.time.Instant;

/**
 * The newest station this worker processed, for the admin status page. {@code StationWorker} records each one;
 * the reporter sends only the latest with its next heartbeat.
 */
@Component
public class ServiceActivity {

    /** One immutable snapshot, swapped atomically. */
    public record Last(Instant at, String action) {
    }

    private volatile Last last;
    private final java.util.concurrent.atomic.AtomicLong requests = new java.util.concurrent.atomic.AtomicLong();

    /** Records the item as the latest one and counts it as a request (the page's per hour / day / month columns). */
    public void record(String action) {
        requests.incrementAndGet();
        last = new Last(Instant.now(), action);
    }

    /** @return requests recorded since the process started; sent as {@code requests} with every status message */
    public long requests() {
        return requests.get();
    }

    /** @return the latest action, or {@code null} before the first one */
    public Last last() {
        return last;
    }
}
