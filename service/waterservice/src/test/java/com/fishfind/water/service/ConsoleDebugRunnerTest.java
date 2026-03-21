package com.fishfind.water.service;

import org.junit.jupiter.api.Test;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.DefaultApplicationArguments;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class ConsoleDebugRunnerTest {

    private final StationWorker stationWorker = mock(StationWorker.class);
    private final ConsoleDebugRunner runner = new ConsoleDebugRunner(stationWorker);

    @Test
    void runDoesNothingWithoutConsoleFlag() throws Exception {
        ApplicationArguments args = new DefaultApplicationArguments();

        runner.run(args);

        verify(stationWorker, never()).runOnce(org.mockito.ArgumentMatchers.any());
    }

    @Test
    void runProcessesAllStationsWhenNoSpecificStationIsProvided() throws Exception {
        ApplicationArguments args = new DefaultApplicationArguments("--console");
        when(stationWorker.runOnce(null)).thenReturn(3);

        runner.run(args);

        verify(stationWorker).runOnce(null);
    }

    @Test
    void runProcessesRequestedStationWhenProvided() throws Exception {
        ApplicationArguments args = new DefaultApplicationArguments("--console", "--station=02JE025");
        when(stationWorker.runOnce("02JE025")).thenReturn(1);

        runner.run(args);

        verify(stationWorker).runOnce("02JE025");
    }
}
