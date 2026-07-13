package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.boot.DefaultApplicationArguments;

class ConsoleDebugRunnerTest {

    private StationWorker stationWorker;
    private Integer exitCode;
    private RecordingRunner runner;

    @BeforeEach
    void setUp() {
        stationWorker = Mockito.mock(StationWorker.class);
        runner = new RecordingRunner();
    }

    @Test
    void noConsoleOptionIsNoOp() throws Exception {
        runner.run(new DefaultApplicationArguments());

        verifyNoInteractions(stationWorker);
        assertThat(exitCode).isNull();
    }

    @Test
    void consoleWithoutStationRunsAllAndExits() throws Exception {
        when(stationWorker.runOnce(null)).thenReturn(new StationWorker.RunResult(5, 0));

        runner.run(new DefaultApplicationArguments("--console"));

        verify(stationWorker).runOnce(null);
        assertThat(exitCode).isZero();
    }

    @Test
    void consoleWithStationFiltersToThatStation() throws Exception {
        when(stationWorker.runOnce("MLI-5")).thenReturn(new StationWorker.RunResult(1, 0));

        runner.run(new DefaultApplicationArguments("--console", "--station=MLI-5"));

        verify(stationWorker).runOnce("MLI-5");
        assertThat(exitCode).isZero();
    }

    @Test
    void exitsNonZeroWhenEveryStationFailed() throws Exception {
        when(stationWorker.runOnce(null)).thenReturn(new StationWorker.RunResult(0, 3));

        runner.run(new DefaultApplicationArguments("--console"));

        assertThat(exitCode).isEqualTo(1);
    }

    @Test
    void exitsZeroWhenSomeStationsProcessedDespiteFailures() throws Exception {
        when(stationWorker.runOnce(null)).thenReturn(new StationWorker.RunResult(2, 1));

        runner.run(new DefaultApplicationArguments("--console"));

        assertThat(exitCode).isZero();
    }

    private class RecordingRunner extends ConsoleDebugRunner {
        RecordingRunner() {
            super(stationWorker);
        }

        @Override
        protected void exit(int code) {
            exitCode = code;
        }
    }
}
