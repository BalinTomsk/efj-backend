package com.fishfind.weather.service;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Tracks how much of each provider's daily API allowance has actually been spent, in a file that
 * survives restarts so a crash-loop cannot re-spend a paid quota.
 *
 * <p><strong>Budget is consumed one station at a time, immediately before that station is
 * fetched</strong> — never booked up front for a whole cycle. The up-front version charged the entire
 * daily limit at cycle start, so any restart forfeited whatever the interrupted cycle had not yet
 * used: measured on the C# port on 2026-08-08, three restarts burned 3,200 station-slots to do ~154
 * stations of real work, and the service then sat idle until the next UTC day. Charging per station
 * means an interrupted cycle costs exactly what it used, and that stays true after a hard kill, where
 * nothing gets the chance to credit anything back.
 *
 * <p>If the ledger cannot be written the provider is skipped rather than run unmetered — an
 * unwritable state directory is precisely the condition under which a restart loop would otherwise
 * re-spend the budget over and over.
 */
@Component
public class WeatherApiUsageTracker {
    private static final Logger log = LoggerFactory.getLogger(WeatherApiUsageTracker.class);
    private static final String USAGE_FILE = "api-usage.log";
    private static final int RETENTION_DAYS = 8;

    @Value("${weather.lifecycle.state-dir:/app/logs/.lifecycle}")
    private String stateDir;

    /**
     * How much of a provider's day is left, for sizing the cycle and for logging.
     *
     * @param usedToday  stations already charged to this provider today
     * @param dailyLimit the configured ceiling
     * @param remaining  what this cycle may still spend
     * @param persisted  whether the ledger is readable/writable; {@code false} forces a skip
     */
    public record UsageSnapshot(int usedToday, int dailyLimit, int remaining, boolean persisted) {
    }

    /** Reads today's usage without charging anything. */
    public synchronized UsageSnapshot snapshot(String provider, LocalDate date, int dailyLimit) {
        int safeLimit = Math.max(0, dailyLimit);
        try {
            Files.createDirectories(usageDir());
            int used = usedOn(readRetainedEntries(date), provider, date);
            return new UsageSnapshot(used, safeLimit, Math.max(0, safeLimit - used), true);
        } catch (IOException ex) {
            logLedgerFailure(ex, provider, safeLimit);
            return new UsageSnapshot(0, safeLimit, 0, false);
        }
    }

    /**
     * Charges one station against the provider's daily allowance.
     *
     * @return {@code true} when the station may be fetched. {@code false} means the allowance is spent
     *         (or the ledger is unwritable) and the caller must stop — nothing was charged.
     */
    public synchronized boolean tryConsume(String provider, LocalDate date, int dailyLimit) {
        int safeLimit = Math.max(0, dailyLimit);
        if (safeLimit == 0) {
            return false;
        }

        try {
            Files.createDirectories(usageDir());
            List<UsageEntry> entries = readRetainedEntries(date);
            if (usedOn(entries, provider, date) >= safeLimit) {
                return false;
            }

            // One aggregated row per (date, provider): incremented in place, so the file stays a few
            // lines long however many stations a day runs.
            int index = -1;
            for (int i = 0; i < entries.size(); i++) {
                UsageEntry entry = entries.get(i);
                if (entry.date().equals(date) && entry.provider().equals(provider)) {
                    index = i;
                    break;
                }
            }
            if (index >= 0) {
                UsageEntry existing = entries.get(index);
                entries.set(index, new UsageEntry(existing.date(), existing.provider(), existing.reserved() + 1));
            } else {
                entries.add(new UsageEntry(date, provider, 1));
            }

            // Written before the fetch, so a crash mid-station costs that station's slot rather than
            // letting the restart re-spend it.
            writeEntries(entries);
            return true;
        } catch (IOException ex) {
            logLedgerFailure(ex, provider, safeLimit);
            return false;
        }
    }

    private void logLedgerFailure(IOException ex, String provider, int dailyLimit) {
        log.error("Could not read/write the weather API usage ledger; skipping provider to avoid "
                        + "exceeding the daily limit after restart. provider={} dailyLimit={} stateDir={}",
                provider, dailyLimit, stateDir, ex);
    }

    private static int usedOn(List<UsageEntry> entries, String provider, LocalDate date) {
        return entries.stream()
                .filter(entry -> entry.date().equals(date) && entry.provider().equals(provider))
                .mapToInt(UsageEntry::reserved)
                .sum();
    }

    private List<UsageEntry> readRetainedEntries(LocalDate today) throws IOException {
        Path path = usagePath();
        if (!Files.isReadable(path)) {
            return new ArrayList<>();
        }

        LocalDate cutoff = today.minusDays(RETENTION_DAYS);
        List<UsageEntry> entries = new ArrayList<>();
        for (String line : Files.readAllLines(path, StandardCharsets.UTF_8)) {
            UsageEntry entry = parseLine(line);
            if (entry != null && entry.date().isAfter(cutoff)) {
                entries.add(entry);
            }
        }
        return entries;
    }

    private void writeEntries(List<UsageEntry> entries) throws IOException {
        List<String> lines = entries.stream()
                .map(entry -> String.join("|",
                        entry.date().toString(),
                        sanitize(entry.provider()),
                        Integer.toString(entry.reserved())))
                .toList();
        Files.write(usagePath(), lines, StandardCharsets.UTF_8);
    }

    private UsageEntry parseLine(String line) {
        String[] parts = line.split("\\|", 3);
        if (parts.length != 3) {
            return null;
        }
        try {
            return new UsageEntry(LocalDate.parse(parts[0]), parts[1], Integer.parseInt(parts[2]));
        } catch (DateTimeParseException | NumberFormatException ex) {
            return null;
        }
    }

    private static String sanitize(String text) {
        return text.replace('|', '/').replace('\n', ' ').replace('\r', ' ');
    }

    private Path usageDir() {
        return Path.of(stateDir);
    }

    private Path usagePath() {
        return usageDir().resolve(USAGE_FILE);
    }

    private record UsageEntry(LocalDate date, String provider, int reserved) {
    }
}
