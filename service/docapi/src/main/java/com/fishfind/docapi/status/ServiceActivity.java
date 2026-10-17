package com.fishfind.docapi.status;

import org.springframework.stereotype.Component;

import java.time.Instant;

/**
 * The newest item docapi worked on, for the admin status page. {@link ServiceActivityFilter} records each API
 * request as {@code "GET /api/v1/river/{guid}"} (the route pattern, never the ids or query); the reporter sends
 * only the latest one with its next heartbeat.
 */
@Component
public class ServiceActivity {

    /** One immutable snapshot, swapped atomically. */
    public record Last(Instant at, String action) {
    }

    private volatile Last last;

    public void record(String action) {
        last = new Last(Instant.now(), action);
    }

    /** @return the latest action, or {@code null} before the first one */
    public Last last() {
        return last;
    }
}
