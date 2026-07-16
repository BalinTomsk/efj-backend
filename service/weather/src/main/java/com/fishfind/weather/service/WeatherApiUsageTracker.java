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
 * Persists conservative per-provider daily API reservations so restarts cannot reset usage.
 */
@Component
public class WeatherApiUsageTracker {
    private static final Logger log = LoggerFactory.getLogger(WeatherApiUsageTracker.class);
    private static final String USAGE_FILE = "api-usage.log";
    private static final int RETENTION_DAYS = 8;

    @Value("${weather.lifecycle.state-dir:/app/logs/.lifecycle}")
    private String stateDir;

    public synchronized UsageReservation reserve(String provider, LocalDate date, int requested, int dailyLimit) {
        int safeRequested = Math.max(0, requested);
        int safeDailyLimit = Math.max(0, dailyLimit);
        if (safeRequested == 0 || safeDailyLimit == 0) {
            return new UsageReservation(usedToday(provider, date), safeDailyLimit, 0, safeRequested, true);
        }

        try {
            Files.createDirectories(usageDir());
            List<UsageEntry> entries = readRetainedEntries(date);
            int usedBefore = entries.stream()
                    .filter(entry -> entry.date().equals(date) && entry.provider().equals(provider))
                    .mapToInt(UsageEntry::reserved)
                    .sum();
            int remaining = Math.max(0, safeDailyLimit - usedBefore);
            int reserved = Math.min(safeRequested, remaining);
            if (reserved > 0) {
                entries.add(new UsageEntry(date, provider, reserved));
            }
            writeEntries(entries);
            return new UsageReservation(usedBefore, safeDailyLimit, reserved, safeRequested, true);
        } catch (IOException ex) {
            log.error("Could not persist weather API usage reservation; skipping provider to avoid "
                    + "exceeding daily limit after restart. provider={} requested={} dailyLimit={} stateDir={}",
                    provider, safeRequested, safeDailyLimit, stateDir, ex);
            return new UsageReservation(0, safeDailyLimit, 0, safeRequested, false);
        }
    }

    private int usedToday(String provider, LocalDate date) {
        try {
            return readRetainedEntries(date).stream()
                    .filter(entry -> entry.date().equals(date) && entry.provider().equals(provider))
                    .mapToInt(UsageEntry::reserved)
                    .sum();
        } catch (IOException ex) {
            return 0;
        }
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

    public record UsageReservation(
            int usedBefore,
            int dailyLimit,
            int reserved,
            int requested,
            boolean persisted) {
    }

    private record UsageEntry(LocalDate date, String provider, int reserved) {
    }
}
