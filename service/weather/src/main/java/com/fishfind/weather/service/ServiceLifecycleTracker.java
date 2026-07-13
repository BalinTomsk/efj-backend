package com.fishfind.weather.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.io.BufferedReader;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Detects whether the previous run of this service shut down cleanly or crashed, and keeps a
 * short rolling history of crash incidents for the weekly report email.
 *
 * <p><b>How detection works:</b> a two-line marker file is written {@code RUNNING|<startedAt>}
 * on every startup ({@link #init()}) and rewritten {@code CLEAN|<shutdownAt>} on graceful
 * shutdown ({@link #onShutdown()}, a {@code @PreDestroy} hook fired when Spring receives SIGTERM
 * and has time to run its shutdown phase). If the NEXT startup finds the marker still says
 * {@code RUNNING}, the previous process never got that chance — it crashed (OOM-killed,
 * uncaught JVM error, {@code kill -9}, host reboot, or a forceful container removal that skips
 * SIGTERM). The incident's description is taken from the last ERROR/WARN line in the previous
 * run's log file, and its downtime start from that line's timestamp.
 *
 * <p><b>This only works if the deploy tooling stops the container gracefully</b> (SIGTERM, e.g.
 * {@code docker stop}) instead of force-killing it ({@code docker rm -f} / {@code docker kill}
 * sends SIGKILL immediately) — a force-killed deploy looks identical to a crash to this class,
 * since {@code @PreDestroy} never runs either way. See {@code docs/do-update.md} Step 8.
 *
 * <p>State is a plain file under {@code weather.lifecycle.state-dir}, not a database table.
 * Nothing here fails startup: unwritable/missing state is logged and skipped.
 */
@Component
public class ServiceLifecycleTracker {
    private static final Logger log = LoggerFactory.getLogger(ServiceLifecycleTracker.class);
    private static final String MARKER_FILE = "lifecycle.marker";
    private static final String INCIDENTS_FILE = "incidents.log";
    private static final String RUNNING = "RUNNING";
    private static final String CLEAN = "CLEAN";
    private static final int LOG_TAIL_LINES = 500;
    private static final int RETENTION_DAYS = 7;
    private static final int MAX_DESCRIPTION_LENGTH = 200;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Value("${weather.lifecycle.state-dir:/app/logs/.lifecycle}")
    private String stateDir;

    @Value("${weather.lifecycle.log-file:logs/weather.log}")
    private String logFilePath;

    @PostConstruct
    void init() {
        try {
            Files.createDirectories(Path.of(stateDir));
        } catch (IOException ex) {
            log.warn("Could not create lifecycle state dir; crash tracking disabled this run. dir={}",
                    stateDir, ex);
            return;
        }

        detectPreviousCrash();
        writeMarker(RUNNING, LocalDateTime.now());
    }

    @PreDestroy
    void onShutdown() {
        writeMarker(CLEAN, LocalDateTime.now());
    }

    /** Incidents detected within the last {@value #RETENTION_DAYS} days, oldest first. */
    public synchronized List<IncidentEntry> recentIncidents() {
        Path path = markerDir().resolve(INCIDENTS_FILE);
        if (!Files.isReadable(path)) {
            return List.of();
        }

        LocalDateTime cutoff = LocalDateTime.now().minusDays(RETENTION_DAYS);
        List<IncidentEntry> kept = new ArrayList<>();
        try {
            for (String line : Files.readAllLines(path, StandardCharsets.UTF_8)) {
                IncidentEntry entry = parseIncidentLine(line);
                if (entry != null && entry.detectedAt().isAfter(cutoff)) {
                    kept.add(entry);
                }
            }
            writeIncidents(kept);
        } catch (IOException ex) {
            log.warn("Failed reading incidents log. file={}", path, ex);
            return List.of();
        }
        return kept;
    }

    private void detectPreviousCrash() {
        List<String> marker = readMarker();
        if (marker.isEmpty() || !RUNNING.equals(marker.get(0))) {
            return; // first-ever startup, or the previous run shut down cleanly
        }

        Path logFile = Path.of(logFilePath);
        String description = extractIncidentDescription(logFile);
        LocalDateTime downtimeStart = extractLastLogTimestamp(logFile)
                .or(() -> parseMarkerTimestamp(marker))
                .orElseGet(LocalDateTime::now);
        LocalDateTime now = LocalDateTime.now();

        appendIncident(new IncidentEntry(now, downtimeStart, now, description));
        log.warn("Detected an unclean shutdown of the previous run (crash). downtimeStart={} description={}",
                downtimeStart, description);
    }

    private String extractIncidentDescription(Path logFile) {
        if (!Files.isReadable(logFile)) {
            return "no log data available";
        }
        try {
            String lastIssue = null;
            for (String line : tailLines(logFile, LOG_TAIL_LINES)) {
                JsonNode node = parseJsonQuietly(line);
                if (node == null) {
                    continue;
                }
                String level = node.path("level").asText("");
                String message = node.path("message").asText("");
                if (("ERROR".equals(level) || "WARN".equals(level)) && !message.isBlank()) {
                    lastIssue = level + ": " + truncate(message, MAX_DESCRIPTION_LENGTH);
                }
            }
            return lastIssue != null ? lastIssue : "no errors or warnings recorded before the restart";
        } catch (IOException ex) {
            log.warn("Failed reading previous log file for crash description. file={}", logFile, ex);
            return "no log data available";
        }
    }

    private Optional<LocalDateTime> extractLastLogTimestamp(Path logFile) {
        if (!Files.isReadable(logFile)) {
            return Optional.empty();
        }
        try {
            List<String> lines = tailLines(logFile, LOG_TAIL_LINES);
            for (int i = lines.size() - 1; i >= 0; i--) {
                JsonNode node = parseJsonQuietly(lines.get(i));
                if (node == null) {
                    continue;
                }
                Optional<LocalDateTime> ts = parseTimestampQuietly(node.path("timestamp").asText(null));
                if (ts.isPresent()) {
                    return ts;
                }
            }
        } catch (IOException ex) {
            log.warn("Failed reading previous log file for downtime timestamp. file={}", logFile, ex);
        }
        return Optional.empty();
    }

    private List<String> tailLines(Path file, int maxLines) throws IOException {
        Deque<String> tail = new ArrayDeque<>(maxLines);
        try (BufferedReader reader = Files.newBufferedReader(file, StandardCharsets.UTF_8)) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (tail.size() == maxLines) {
                    tail.removeFirst();
                }
                tail.addLast(line);
            }
        }
        return new ArrayList<>(tail);
    }

    private JsonNode parseJsonQuietly(String line) {
        try {
            return objectMapper.readTree(line);
        } catch (IOException malformed) {
            return null;
        }
    }

    private Optional<LocalDateTime> parseTimestampQuietly(String text) {
        if (text == null || text.isBlank()) {
            return Optional.empty();
        }
        try {
            return Optional.of(
                    Instant.parse(text).atZone(ZoneId.systemDefault()).toLocalDateTime());
        } catch (DateTimeParseException ex) {
            return Optional.empty();
        }
    }

    private Optional<LocalDateTime> parseMarkerTimestamp(List<String> marker) {
        if (marker.size() < 2) {
            return Optional.empty();
        }
        try {
            return Optional.of(LocalDateTime.parse(marker.get(1)));
        } catch (DateTimeParseException ex) {
            return Optional.empty();
        }
    }

    private List<String> readMarker() {
        Path path = markerDir().resolve(MARKER_FILE);
        if (!Files.isReadable(path)) {
            return List.of();
        }
        try {
            return Files.readAllLines(path, StandardCharsets.UTF_8);
        } catch (IOException ex) {
            log.warn("Failed reading lifecycle marker. file={}", path, ex);
            return List.of();
        }
    }

    private void writeMarker(String state, LocalDateTime at) {
        Path path = markerDir().resolve(MARKER_FILE);
        try {
            Files.write(path, List.of(state, at.toString()), StandardCharsets.UTF_8);
        } catch (IOException ex) {
            log.warn("Failed writing lifecycle marker. file={} state={}", path, state, ex);
        }
    }

    private void appendIncident(IncidentEntry entry) {
        Path path = markerDir().resolve(INCIDENTS_FILE);
        String line = String.join("|",
                entry.detectedAt().toString(),
                entry.downtimeStart().toString(),
                entry.downtimeEnd().toString(),
                sanitize(entry.description()));
        try {
            Files.writeString(path, line + System.lineSeparator(), StandardCharsets.UTF_8,
                    StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        } catch (IOException ex) {
            log.warn("Failed appending to incidents log. file={}", path, ex);
        }
    }

    private void writeIncidents(List<IncidentEntry> entries) throws IOException {
        Path path = markerDir().resolve(INCIDENTS_FILE);
        List<String> lines = entries.stream()
                .map(e -> String.join("|",
                        e.detectedAt().toString(),
                        e.downtimeStart().toString(),
                        e.downtimeEnd().toString(),
                        sanitize(e.description())))
                .toList();
        Files.write(path, lines, StandardCharsets.UTF_8);
    }

    private IncidentEntry parseIncidentLine(String line) {
        String[] parts = line.split("\\|", 4);
        if (parts.length != 4) {
            return null;
        }
        try {
            return new IncidentEntry(
                    LocalDateTime.parse(parts[0]),
                    LocalDateTime.parse(parts[1]),
                    LocalDateTime.parse(parts[2]),
                    parts[3]);
        } catch (DateTimeParseException ex) {
            return null;
        }
    }

    private static String sanitize(String text) {
        return text.replace('|', '/').replace('\n', ' ').replace('\r', ' ');
    }

    private static String truncate(String text, int maxLength) {
        return text.length() <= maxLength ? text : text.substring(0, maxLength) + "...";
    }

    private Path markerDir() {
        return Path.of(stateDir);
    }
}
