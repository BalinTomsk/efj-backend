package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * Covers the ledger that stops a restart loop from re-spending a provider's paid daily quota.
 * Budget is charged per station, so an interrupted cycle costs only what it actually used.
 */
class WeatherApiUsageTrackerTest {

    private static final LocalDate DAY = LocalDate.of(2026, 7, 15);

    @TempDir
    private Path tempDir;

    @Test
    void chargesOneStationAtATime() {
        WeatherApiUsageTracker tracker = tracker(tempDir);

        assertThat(tracker.tryConsume("weather-gov", DAY, 3)).isTrue();
        assertThat(tracker.tryConsume("weather-gov", DAY, 3)).isTrue();

        WeatherApiUsageTracker.UsageSnapshot snapshot = tracker.snapshot("weather-gov", DAY, 3);
        assertThat(snapshot.usedToday()).isEqualTo(2);
        assertThat(snapshot.remaining()).isEqualTo(1);
    }

    @Test
    void stopsAtTheDailyLimit() {
        WeatherApiUsageTracker tracker = tracker(tempDir);
        for (int i = 0; i < 3; i++) {
            tracker.tryConsume("google-weather", DAY, 3);
        }

        assertThat(tracker.tryConsume("google-weather", DAY, 3)).isFalse();
        assertThat(tracker.snapshot("google-weather", DAY, 3).usedToday()).isEqualTo(3);
    }

    @Test
    void anInterruptedCycleOnlyCostsWhatItUsed() {
        // The whole point of charging per station: the old up-front reservation booked the entire
        // daily limit at cycle start, so a restart 5 stations in forfeited the other 895.
        WeatherApiUsageTracker before = tracker(tempDir);
        for (int i = 0; i < 5; i++) {
            before.tryConsume("weather-gov", DAY, 900);
        }

        WeatherApiUsageTracker afterRestart = tracker(tempDir);
        WeatherApiUsageTracker.UsageSnapshot snapshot = afterRestart.snapshot("weather-gov", DAY, 900);

        assertThat(snapshot.usedToday()).isEqualTo(5);
        assertThat(snapshot.remaining()).isEqualTo(895);
        assertThat(afterRestart.tryConsume("weather-gov", DAY, 900)).isTrue();
    }

    @Test
    void keepsProviderBudgetsSeparate() {
        WeatherApiUsageTracker tracker = tracker(tempDir);
        tracker.tryConsume("visual-crossing", DAY, 1);

        assertThat(tracker.tryConsume("visual-crossing", DAY, 1)).isFalse();
        assertThat(tracker.tryConsume("weather-gov", DAY, 1)).isTrue();
    }

    @Test
    void yesterdaysUsageDoesNotCountAgainstToday() {
        WeatherApiUsageTracker tracker = tracker(tempDir);
        tracker.tryConsume("open", DAY.minusDays(1), 1);

        assertThat(tracker.snapshot("open", DAY, 1).usedToday()).isZero();
        assertThat(tracker.tryConsume("open", DAY, 1)).isTrue();
    }

    @Test
    void zeroDailyLimitDisablesTheProvider() {
        assertThat(tracker(tempDir).tryConsume("weather-canada", DAY, 0)).isFalse();
    }

    @Test
    void unwritableStateDirSkipsTheProviderInsteadOfRunningUnmetered() throws Exception {
        // Without a durable ledger there is no way to know what today already cost, so spend nothing.
        Path notDirectory = tempDir.resolve("not-directory");
        Files.writeString(notDirectory, "x");
        WeatherApiUsageTracker tracker = tracker(notDirectory.resolve("state"));

        assertThat(tracker.tryConsume("visual-crossing", DAY, 1000)).isFalse();
        assertThat(tracker.snapshot("visual-crossing", DAY, 1000).persisted()).isFalse();
    }

    private WeatherApiUsageTracker tracker(Path stateDir) {
        WeatherApiUsageTracker tracker = new WeatherApiUsageTracker();
        ReflectionTestUtils.setField(tracker, "stateDir", stateDir.toString());
        return tracker;
    }
}
