package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

class WeatherApiUsageTrackerTest {

    @TempDir
    private Path tempDir;

    @Test
    void reservesOnlyRemainingDailyLimitAcrossTrackerInstances() {
        LocalDate day = LocalDate.of(2026, 7, 15);
        WeatherApiUsageTracker first = tracker(tempDir);

        WeatherApiUsageTracker.UsageReservation firstReservation =
                first.reserve("visual-crossing", day, 800, 1000);

        assertThat(firstReservation.reserved()).isEqualTo(800);
        assertThat(firstReservation.usedBefore()).isZero();

        WeatherApiUsageTracker restarted = tracker(tempDir);
        WeatherApiUsageTracker.UsageReservation secondReservation =
                restarted.reserve("visual-crossing", day, 500, 1000);

        assertThat(secondReservation.usedBefore()).isEqualTo(800);
        assertThat(secondReservation.reserved()).isEqualTo(200);
    }

    @Test
    void keepsProviderBudgetsSeparate() {
        LocalDate day = LocalDate.of(2026, 7, 15);
        WeatherApiUsageTracker tracker = tracker(tempDir);

        tracker.reserve("visual-crossing", day, 1000, 1000);
        WeatherApiUsageTracker.UsageReservation weatherGov =
                tracker.reserve("weather-gov", day, 900, 900);

        assertThat(weatherGov.usedBefore()).isZero();
        assertThat(weatherGov.reserved()).isEqualTo(900);
    }

    @Test
    void returnsZeroReservationWhenUsageCannotBePersisted() throws Exception {
        Path notDirectory = tempDir.resolve("not-directory");
        Files.writeString(notDirectory, "x");
        WeatherApiUsageTracker tracker = tracker(notDirectory.resolve("state"));

        WeatherApiUsageTracker.UsageReservation reservation =
                tracker.reserve("visual-crossing", LocalDate.of(2026, 7, 15), 10, 1000);

        assertThat(reservation.persisted()).isFalse();
        assertThat(reservation.reserved()).isZero();
    }

    private WeatherApiUsageTracker tracker(Path stateDir) {
        WeatherApiUsageTracker tracker = new WeatherApiUsageTracker();
        ReflectionTestUtils.setField(tracker, "stateDir", stateDir.toString());
        return tracker;
    }
}
