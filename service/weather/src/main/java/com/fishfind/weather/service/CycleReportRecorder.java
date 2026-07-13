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
    static final int MAX_ENTRIES = 7;

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
