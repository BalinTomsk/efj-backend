package com.fishfind.weather.service;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.List;
import org.springframework.stereotype.Component;

/**
 * Keeps the most recently completed-cycle summaries in memory so the weekly report email
 * can list one entry per day. Not persisted: a JVM restart (e.g. a mid-week deploy) clears
 * this, so a report generated after a restart only covers cycles completed since then.
 */
@Component
public class CycleReportRecorder {
    static final int MAX_ENTRIES_PER_WORKER = 7;
    /** Derived from {@link StationWorker#WORKER_COUNT} rather than a hand-maintained constant, which
     * previously went stale as providers were added (fixed at 2 while the worker count grew to 6) and
     * silently shrank the report's effective window well below a week. */
    static final int MAX_ENTRIES = MAX_ENTRIES_PER_WORKER * StationWorker.WORKER_COUNT;

    private final Deque<CycleReportEntry> entries = new ArrayDeque<>();

    public synchronized void record(CycleReportEntry entry) {
        entries.addLast(entry);
        while (entries.size() > MAX_ENTRIES) {
            entries.removeFirst();
        }
    }

    public synchronized List<CycleReportEntry> recentEntries() {
        return List.copyOf(entries);
    }
}
