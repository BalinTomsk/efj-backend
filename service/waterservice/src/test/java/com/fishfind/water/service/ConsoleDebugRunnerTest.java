package com.fishfind.water.service;

import org.junit.jupiter.api.Test;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.DefaultApplicationArguments;

import java.time.Duration;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.doAnswer;

class ConsoleDebugRunnerTest {

    private final StationWorkerCA stationWorkerCA = mock(StationWorkerCA.class);
    private final StationWorkerUS stationWorkerUS = mock(StationWorkerUS.class);
    private final ConsoleDebugRunner runner = new ConsoleDebugRunner(stationWorkerCA, stationWorkerUS);

    @Test
    void runDoesNothingWithoutConsoleFlag() throws Exception {
        ApplicationArguments args = new DefaultApplicationArguments();

        runner.run(args);

        verify(stationWorkerCA, never()).runOnce(any());
        verify(stationWorkerUS, never()).runOnce(any());
    }

    @Test
    void runProcessesAllStationsWhenNoSpecificStationIsProvided() throws Exception {
        ApplicationArguments args = new DefaultApplicationArguments("--console");
        when(stationWorkerCA.runOnce(null)).thenReturn(3);
        when(stationWorkerUS.runOnce(null)).thenReturn(5);

        runner.run(args);

        verify(stationWorkerCA).runOnce(null);
        verify(stationWorkerUS).runOnce(null);
    }

    @Test
    void runProcessesRequestedStationWhenProvided() throws Exception {
        ApplicationArguments args = new DefaultApplicationArguments("--console", "--station=02JE025");
        when(stationWorkerCA.runOnce("02JE025")).thenReturn(1);
        when(stationWorkerUS.runOnce("02JE025")).thenReturn(0);

        runner.run(args);

        verify(stationWorkerCA).runOnce("02JE025");
        verify(stationWorkerUS).runOnce("02JE025");
    }

    @Test
    void runStartsUsAndCaWorkersInParallel() throws Exception {
        ApplicationArguments args = new DefaultApplicationArguments("--console");
        CountDownLatch caStarted = new CountDownLatch(1);
        CountDownLatch usStarted = new CountDownLatch(1);
        CountDownLatch releaseWorkers = new CountDownLatch(1);

        doAnswer(invocation -> {
            caStarted.countDown();
            assertTrue(usStarted.await(1, TimeUnit.SECONDS));
            assertTrue(releaseWorkers.await(1, TimeUnit.SECONDS));
            return 1;
        }).when(stationWorkerCA).runOnce(null);

        doAnswer(invocation -> {
            usStarted.countDown();
            assertTrue(caStarted.await(1, TimeUnit.SECONDS));
            assertTrue(releaseWorkers.await(1, TimeUnit.SECONDS));
            return 1;
        }).when(stationWorkerUS).runOnce(null);

        Thread runnerThread = new Thread(() -> {
            try {
                runner.run(args);
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        });

        runnerThread.start();
        assertTrue(caStarted.await(1, TimeUnit.SECONDS));
        assertTrue(usStarted.await(1, TimeUnit.SECONDS));
        releaseWorkers.countDown();
        runnerThread.join(Duration.ofSeconds(2).toMillis());

        assertTrue(!runnerThread.isAlive());
    }

    @Test
    void runPropagatesWorkerFailures() throws Exception {
        ApplicationArguments args = new DefaultApplicationArguments("--console");
        when(stationWorkerCA.runOnce(null)).thenThrow(new InterruptedException("stop"));
        when(stationWorkerUS.runOnce(null)).thenReturn(1);

        InterruptedException thrown = assertThrows(InterruptedException.class, () -> runner.run(args));

        assertTrue(thrown.getMessage().contains("stop"));
    }
}
