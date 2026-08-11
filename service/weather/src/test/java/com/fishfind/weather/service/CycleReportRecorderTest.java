package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import org.junit.jupiter.api.Test;

class CycleReportRecorderTest {

    @Test
    void startsEmpty() {
        assertThat(new CycleReportRecorder().recentEntries()).isEmpty();
    }

    @Test
    void keepsInsertionOrder() {
        CycleReportRecorder recorder = new CycleReportRecorder();
        recorder.record(entry(1));
        recorder.record(entry(2));

        assertThat(recorder.recentEntries())
                .extracting(CycleReportEntry::successfulStations)
                .containsExactly(1, 2);
    }

    @Test
    void evictsOldestBeyondSevenDaysPerWorker() {
        CycleReportRecorder recorder = new CycleReportRecorder();
        int total = CycleReportRecorder.MAX_ENTRIES + 2;
        for (int i = 1; i <= total; i++) {
            recorder.record(entry(i));
        }

        Integer[] expected = java.util.stream.IntStream
                .rangeClosed(total - CycleReportRecorder.MAX_ENTRIES + 1, total)
                .boxed()
                .toArray(Integer[]::new);
        assertThat(recorder.recentEntries())
                .hasSize(CycleReportRecorder.MAX_ENTRIES)
                .extracting(CycleReportEntry::successfulStations)
                .containsExactly(expected);
    }

    @Test
    void capacityCoversAFullWeekForEveryProvider() {
        // MAX_ENTRIES is derived from the actual worker count so it always covers a full week no
        // matter how many providers exist -- the bug this replaced hardcoded the multiplier at 2 and
        // silently fell behind as providers were added (grew to 6 without the constant ever moving).
        assertThat(CycleReportRecorder.MAX_ENTRIES)
                .isEqualTo(CycleReportRecorder.MAX_ENTRIES_PER_WORKER * StationWorker.WORKER_COUNT);
    }

    private static CycleReportEntry entry(int successfulStations) {
        return new CycleReportEntry(
                LocalDate.now(), "Weather.gov", "US", successfulStations, 0, "MLI-" + successfulStations, null);
    }
}
