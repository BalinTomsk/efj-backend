package com.fishfind.water.service;

import com.fishfind.water.domain.StationRef;
import com.fishfind.water.repo.WaterStationRepository;
import org.junit.jupiter.api.Test;
import org.springframework.boot.DefaultApplicationArguments;
import org.springframework.test.util.ReflectionTestUtils;

import java.lang.reflect.Method;
import java.time.Duration;
import java.time.ZonedDateTime;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class StationWorkerTest {

    private final WaterStationRepository repo = mock(WaterStationRepository.class);
    private final StationProcessorCA processorCA = mock(StationProcessorCA.class);
    private final StationProcessorUS processorUS = mock(StationProcessorUS.class);
    private final StationPostProcessingService postProcessingService = mock(StationPostProcessingService.class);
    private final StationWorker worker = new StationWorker(repo, processorCA, processorUS, postProcessingService);

    @Test
    void runDoesNothingInConsoleMode() {
        worker.run(new DefaultApplicationArguments("--console"));

        verify(repo, never()).findSupported("CA");
        verify(repo, never()).findSupported("US");
    }

    @Test
    void runStartsBackgroundThreadsInNormalMode() throws Exception {
        when(repo.findSupported("CA")).thenReturn(List.of());
        when(repo.findSupported("US")).thenReturn(List.of());

        worker.run(new DefaultApplicationArguments());

        Thread caThread = waitForWorkerThread("water-station-worker-ca");
        Thread usThread = waitForWorkerThread("water-station-worker-us");
        assertTrue(caThread.isAlive());
        assertTrue(usThread.isAlive());
        caThread.interrupt();
        usThread.interrupt();
        caThread.join(Duration.ofSeconds(2).toMillis());
        usThread.join(Duration.ofSeconds(2).toMillis());
        verify(repo, times(1)).findSupported("CA");
        verify(repo, times(1)).findSupported("US");
    }

    @Test
    void runOnceProcessesFilteredCaStations() throws Exception {
        when(repo.findSupported("CA")).thenReturn(List.of(
                new StationRef("A", "QC", -5),
                new StationRef("B", "ON", -5)
        ));
        ReflectionTestUtils.setField(worker, "pauseBetweenStationsMs", 0L);

        int processed = worker.runOnce("CA", "B");

        assertTrue(processed == 1);
        verify(processorCA).process("B", "ON", -5);
        verify(processorCA, never()).process("A", "QC", -5);
        verify(repo, times(1)).findSupported("CA");
        verify(postProcessingService, times(1)).runAfterStationProcessing();
    }

    @Test
    void runOnceProcessesAllUsStations() throws Exception {
        when(repo.findSupported("US")).thenReturn(List.of(
                new StationRef("08312000", "NM", -7),
                new StationRef("08313000", "NY", -5)
        ));
        ReflectionTestUtils.setField(worker, "pauseBetweenStationsMs", 0L);

        int processed = worker.runOnce("US", null);

        assertTrue(processed == 2);
        verify(processorUS).process("08312000", "NM", -7);
        verify(processorUS).process("08313000", "NY", -5);
        verify(repo, times(1)).findSupported("US");
        verify(postProcessingService, times(1)).runAfterStationProcessing();
    }

    @Test
    void millisUntilNextHourReturnsPositiveDelayWithinOneHour() throws Exception {
        long millis = (long) invokePrivate("millisUntilNextHour");

        assertTrue(millis > 0);
        assertTrue(millis <= Duration.ofHours(1).toMillis());
    }

    @Test
    void millisUntilNextHourReturnsZeroWhenCycleAlreadyExceededNextHourBoundary() throws Exception {
        ZonedDateTime cycleStartedAt = ZonedDateTime.parse("2026-03-23T12:15:00-04:00[America/New_York]");
        ZonedDateTime now = ZonedDateTime.parse("2026-03-23T13:05:00-04:00[America/New_York]");

        long millis = (long) invokePrivate("millisUntilNextHour",
                new Class<?>[]{ZonedDateTime.class, ZonedDateTime.class},
                cycleStartedAt, now);

        assertTrue(millis == 0);
    }

    @Test
    void loopStopsWhenInterruptedDuringSleep() throws Exception {
        when(repo.findSupported("US")).thenReturn(List.of());

        Thread thread = new Thread(() -> {
            try {
                invokePrivate("loop", new Class<?>[]{String.class}, "US");
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        });
        thread.start();

        waitForRepoCall("US");
        thread.interrupt();
        thread.join(Duration.ofSeconds(2).toMillis());

        assertTrue(!thread.isAlive());
    }

    private Thread waitForWorkerThread(String name) throws InterruptedException {
        long deadline = System.currentTimeMillis() + 2000;
        while (System.currentTimeMillis() < deadline) {
            for (Thread thread : Thread.getAllStackTraces().keySet()) {
                if (name.equals(thread.getName())) {
                    return thread;
                }
            }
            Thread.sleep(25);
        }
        throw new AssertionError("worker thread was not started");
    }

    private void waitForRepoCall(String country) throws InterruptedException {
        long deadline = System.currentTimeMillis() + 2000;
        while (System.currentTimeMillis() < deadline) {
            try {
                verify(repo, times(1)).findSupported(country);
                return;
            } catch (AssertionError ignored) {
                Thread.sleep(25);
            }
        }
        throw new AssertionError("loop did not execute runOnce");
    }

    private Object invokePrivate(String name, Class<?>... parameterTypes) throws Exception {
        Method method = StationWorker.class.getDeclaredMethod(name, parameterTypes);
        method.setAccessible(true);
        return method.invoke(worker);
    }

    private Object invokePrivate(String name, Class<?>[] parameterTypes, Object... args) throws Exception {
        Method method = StationWorker.class.getDeclaredMethod(name, parameterTypes);
        method.setAccessible(true);
        return method.invoke(worker, args);
    }
}
