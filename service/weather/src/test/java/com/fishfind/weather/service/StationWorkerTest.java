package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.WeatherStationRepository;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.mockito.Mockito;
import org.springframework.boot.DefaultApplicationArguments;

class StationWorkerTest {

    private static final long EIGHT_HOURS_MS = 8L * 60 * 60 * 1000;

    private WeatherStationRepository stationRepository;
    private StationProcessorOpen processor;
    private StationPostProcessingService postProcessing;

    private final List<Long> recordedSleeps = new ArrayList<>();
    private RecordingWorker worker;

    @BeforeEach
    void setUp() {
        stationRepository = Mockito.mock(WeatherStationRepository.class);
        processor = Mockito.mock(StationProcessorOpen.class);
        postProcessing = Mockito.mock(StationPostProcessingService.class);
        worker = new RecordingWorker();
    }

    @Test
    void calculatesPerStationDelayWithinTimeBudget() {
        assertThat(worker.calculateDelayMs(0)).isEqualTo(2000L);
        assertThat(worker.calculateDelayMs(1)).isEqualTo(2000L);
        assertThat(worker.calculateDelayMs(2)).isEqualTo(EIGHT_HOURS_MS / 2);
        // Very large count floors at the minimum delay.
        assertThat(worker.calculateDelayMs(1_000_000)).isEqualTo(2000L);
    }

    @Test
    void millisUntilNextMidnightIsWithinADay() {
        long ms = worker.millisUntilNextMidnight();
        assertThat(ms).isGreaterThanOrEqualTo(0L).isLessThanOrEqualTo(24L * 60 * 60 * 1000);
    }

    @Test
    void runOnceProcessesAllStationsThenPostProcesses() throws Exception {
        List<StationRef> stations = List.of(
                new StationRef("MLI-1", 1, 1, "WA"),
                new StationRef("MLI-2", 2, 2, "OR"),
                new StationRef("MLI-3", 3, 3, "CA"));
        when(stationRepository.findSupportedUsStations()).thenReturn(stations);

        int processed = worker.runOnce(null);

        assertThat(processed).isEqualTo(3);
        InOrder inOrder = Mockito.inOrder(processor, postProcessing);
        inOrder.verify(processor).process(stations.get(0));
        inOrder.verify(processor).process(stations.get(1));
        inOrder.verify(processor).process(stations.get(2));
        inOrder.verify(postProcessing).runAfterStationProcessing();
        assertThat(recordedSleeps).hasSize(3);
    }

    @Test
    void runOnceFiltersToRequestedStation() throws Exception {
        List<StationRef> stations = List.of(
                new StationRef("MLI-1", 1, 1, "WA"),
                new StationRef("MLI-2", 2, 2, "OR"),
                new StationRef("MLI-3", 3, 3, "CA"));
        when(stationRepository.findSupportedUsStations()).thenReturn(stations);

        int processed = worker.runOnce("MLI-2");

        assertThat(processed).isEqualTo(1);
        verify(processor).process(stations.get(1));
        Mockito.verify(processor, Mockito.never()).process(stations.get(0));
        Mockito.verify(processor, Mockito.never()).process(stations.get(2));
        verify(postProcessing).runAfterStationProcessing();
    }

    @Test
    void consoleModeDoesNotStartBackgroundWork() {
        worker.run(new DefaultApplicationArguments("--console"));

        verifyNoInteractions(stationRepository, processor, postProcessing);
    }

    private class RecordingWorker extends StationWorker {
        RecordingWorker() {
            super(stationRepository, processor, postProcessing);
        }

        @Override
        protected void sleep(long ms) {
            recordedSleeps.add(ms);
        }
    }
}
