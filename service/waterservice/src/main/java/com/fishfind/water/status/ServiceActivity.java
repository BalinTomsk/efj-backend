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

    public void record(String action) {
        last = new Last(Instant.now(), action);
    }

    /** @return the latest action, or {@code null} before the first one */
    public Last last() {
        return last;
    }
}
