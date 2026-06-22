package com.fishfind.water.service;

import org.junit.jupiter.api.Test;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.DefaultApplicationArguments;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class ConsoleDebugRunnerTest {

    private final StationWorker stationWorker = mock(StationWorker.class);
    private final ConsoleDebugRunner runner = new ConsoleDebugRunner(stationWorker);

    @Test
    void runDoesNothingWithoutConsoleFlag() {
        ApplicationArguments args = new DefaultApplicationArguments();

        runner.run(args);

        verify(stationWorker, never()).runCycle(any());
    }

    @Test
    void runRunsOneCycleForAllStationsWhenNoSpecificStationIsProvided() {
        ApplicationArguments args = new DefaultApplicationArguments("--console");
        when(stationWorker.runCycle(null)).thenReturn(8);

        runner.run(args);

        verify(stationWorker).runCycle(null);
    }

    @Test
    void runRunsOneCycleForRequestedStationWhenProvided() {
        ApplicationArguments args = new DefaultApplicationArguments("--console", "--station=02JE025");
        when(stationWorker.runCycle("02JE025")).thenReturn(1);

        runner.run(args);

        verify(stationWorker).runCycle("02JE025");
    }
}
