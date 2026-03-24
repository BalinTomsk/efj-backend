package com.fishfind.water.service;

import org.junit.jupiter.api.Test;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.DefaultApplicationArguments;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class ConsoleDebugRunnerTest {

    private final StationWorkerCA stationWorkerCA = mock(StationWorkerCA.class);
    private final ConsoleDebugRunner runner = new ConsoleDebugRunner(stationWorkerCA);

    @Test
    void runDoesNothingWithoutConsoleFlag() throws Exception {
        ApplicationArguments args = new DefaultApplicationArguments();

        runner.run(args);

        verify(stationWorkerCA, never()).runOnce(org.mockito.ArgumentMatchers.any());
    }

    @Test
    void runProcessesAllStationsWhenNoSpecificStationIsProvided() throws Exception {
        ApplicationArguments args = new DefaultApplicationArguments("--console");
        when(stationWorkerCA.runOnce(null)).thenReturn(3);

        runner.run(args);

        verify(stationWorkerCA).runOnce(null);
    }

    @Test
    void runProcessesRequestedStationWhenProvided() throws Exception {
        ApplicationArguments args = new DefaultApplicationArguments("--console", "--station=02JE025");
        when(stationWorkerCA.runOnce("02JE025")).thenReturn(1);

        runner.run(args);

        verify(stationWorkerCA).runOnce("02JE025");
    }
}
