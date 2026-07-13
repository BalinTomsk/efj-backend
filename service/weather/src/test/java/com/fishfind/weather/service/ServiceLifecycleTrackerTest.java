package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

class ServiceLifecycleTrackerTest {

    @TempDir
    Path tempDir;

    @Test
    void firstEverStartupRecordsNoIncident(@TempDir Path stateDir) {
        ServiceLifecycleTracker tracker = tracker(stateDir, tempDir.resolve("missing.log"));

        tracker.init();

        assertThat(tracker.recentIncidents()).isEmpty();
    }

    @Test
    void cleanShutdownThenRestartRecordsNoIncident(@TempDir Path stateDir) throws IOException {
        Path logFile = tempDir.resolve("weather.log");
        Files.writeString(logFile, "");

        ServiceLifecycleTracker first = tracker(stateDir, logFile);
        first.init();
        first.onShutdown(); // graceful stop -- writes CLEAN

        ServiceLifecycleTracker second = tracker(stateDir, logFile);
        second.init();

        assertThat(second.recentIncidents()).isEmpty();
    }

    @Test
    void uncleanShutdownRecordsIncidentWithLastErrorFromLog(@TempDir Path stateDir) throws IOException {
        Path logFile = tempDir.resolve("weather.log");
        Files.writeString(logFile, String.join("\n",
                "{\"timestamp\":\"2026-07-07T23:00:00.000Z\",\"level\":\"INFO\",\"message\":\"Processed station.\"}",
                "{\"timestamp\":\"2026-07-07T23:45:00.000Z\",\"level\":\"ERROR\",\"message\":\"Weather worker loop failed.\"}",
                ""));

        ServiceLifecycleTracker first = tracker(stateDir, logFile);
        first.init(); // no @PreDestroy -- simulates a crash: marker stays RUNNING

        ServiceLifecycleTracker second = tracker(stateDir, logFile);
        second.init();

        List<IncidentEntry> incidents = second.recentIncidents();
        assertThat(incidents).hasSize(1);
        IncidentEntry incident = incidents.get(0);
        assertThat(incident.description()).contains("ERROR").contains("Weather worker loop failed");
        assertThat(incident.downtimeStart()).isEqualTo(LocalDateTime.of(2026, 7, 7, 23, 45, 0)
                .atZone(java.time.ZoneOffset.UTC).withZoneSameInstant(java.time.ZoneId.systemDefault())
                .toLocalDateTime());
    }

    @Test
    void crashWithNoLogDataStillRecordsIncidentWithFallbackDescription(@TempDir Path stateDir) {
        Path missingLog = tempDir.resolve("does-not-exist.log");

        ServiceLifecycleTracker first = tracker(stateDir, missingLog);
        first.init(); // crash simulation: no onShutdown()

        ServiceLifecycleTracker second = tracker(stateDir, missingLog);
        second.init();

        List<IncidentEntry> incidents = second.recentIncidents();
        assertThat(incidents).hasSize(1);
        assertThat(incidents.get(0).description()).isEqualTo("no log data available");
    }

    @Test
    void incidentsOlderThanSevenDaysAreExcluded(@TempDir Path stateDir) throws IOException {
        Path incidentsFile = stateDir.resolve("incidents.log");
        String oldIncident = String.join("|",
                LocalDateTime.now().minusDays(10).toString(),
                LocalDateTime.now().minusDays(10).toString(),
                LocalDateTime.now().minusDays(10).toString(),
                "stale incident") + System.lineSeparator();
        String recentIncident = String.join("|",
                LocalDateTime.now().minusDays(1).toString(),
                LocalDateTime.now().minusDays(1).toString(),
                LocalDateTime.now().minusDays(1).toString(),
                "recent incident") + System.lineSeparator();
        Files.writeString(incidentsFile, oldIncident + recentIncident, StandardCharsets.UTF_8);

        ServiceLifecycleTracker tracker = tracker(stateDir, tempDir.resolve("missing.log"));

        List<IncidentEntry> incidents = tracker.recentIncidents();

        assertThat(incidents).hasSize(1);
        assertThat(incidents.get(0).description()).isEqualTo("recent incident");
    }

    @Test
    void unwritableStateDirDoesNotThrow() {
        ServiceLifecycleTracker tracker = new ServiceLifecycleTracker();
        // Point the state dir at a path whose parent is a FILE, not a directory --
        // Files.createDirectories must fail, and init() must swallow it.
        Path parentIsAFile = tempDir.resolve("not-a-directory");
        try {
            Files.writeString(parentIsAFile, "x");
        } catch (IOException ex) {
            throw new java.io.UncheckedIOException(ex);
        }
        ReflectionTestUtils.setField(tracker, "stateDir", parentIsAFile.resolve("state").toString());
        ReflectionTestUtils.setField(tracker, "logFilePath", tempDir.resolve("missing.log").toString());

        tracker.init(); // must not throw

        assertThat(tracker.recentIncidents()).isEmpty();
    }

    private ServiceLifecycleTracker tracker(Path stateDir, Path logFile) {
        ServiceLifecycleTracker tracker = new ServiceLifecycleTracker();
        ReflectionTestUtils.setField(tracker, "stateDir", stateDir.toString());
        ReflectionTestUtils.setField(tracker, "logFilePath", logFile.toString());
        return tracker;
    }
}
