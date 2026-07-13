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
    void evictsOldestBeyondSevenEntries() {
        CycleReportRecorder recorder = new CycleReportRecorder();
        for (int i = 1; i <= 9; i++) {
            recorder.record(entry(i));
        }

        assertThat(recorder.recentEntries())
                .hasSize(CycleReportRecorder.MAX_ENTRIES)
                .extracting(CycleReportEntry::successfulStations)
                .containsExactly(3, 4, 5, 6, 7, 8, 9);
    }

    private static CycleReportEntry entry(int successfulStations) {
        return new CycleReportEntry(LocalDate.now(), successfulStations, 0, "MLI-" + successfulStations, null);
    }
}
