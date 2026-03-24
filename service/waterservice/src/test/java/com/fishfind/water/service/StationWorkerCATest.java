package com.fishfind.water.service;

import com.fishfind.water.domain.StationRef;
import com.fishfind.water.repo.WaterStationRepository;
import org.junit.jupiter.api.Test;
import org.springframework.boot.DefaultApplicationArguments;
import org.springframework.test.util.ReflectionTestUtils;

import java.lang.reflect.Method;
import java.time.Duration;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class StationWorkerCATest {

    private final WaterStationRepository repo = mock(WaterStationRepository.class);
    private final StationProcessorCA processor = mock(StationProcessorCA.class);
    private final StationWorkerCA worker = new StationWorkerCA(repo, processor);

    @Test
    void runDoesNothingInConsoleMode() {
        worker.run(new DefaultApplicationArguments("--console"));

        verify(repo, never()).findSupported();
    }

    @Test
    void runStartsBackgroundThreadInNormalMode() throws Exception {
        when(repo.findSupported()).thenReturn(List.of());

        worker.run(new DefaultApplicationArguments());

        Thread thread = waitForWorkerThread();
        assertTrue(thread.isAlive());
        thread.interrupt();
        thread.join(Duration.ofSeconds(2).toMillis());
        verify(repo, times(1)).findSupported();
    }

    @Test
    void runOnceProcessesAllStationsAndAppliesFilter() throws Exception {
        when(repo.findSupported()).thenReturn(List.of(
                new StationRef("A", "QC", -5),
                new StationRef("B", "ON", -5)
        ));
        ReflectionTestUtils.setField(worker, "pauseBetweenStationsMs", 0L);

        int processed = worker.runOnce("B");

        assertTrue(processed == 1);
        verify(processor).process("B", "ON", -5);
        verify(processor, never()).process("A", "QC", -5);
        verify(repo, times(1)).findSupported();
    }

    @Test
    void runOnceProcessesAllStationsFromSingleLoadedList() throws Exception {
        when(repo.findSupported()).thenReturn(List.of(
                new StationRef("A", "QC", -5),
                new StationRef("B", "ON", -5)
        ));
        ReflectionTestUtils.setField(worker, "pauseBetweenStationsMs", 0L);

        int processed = worker.runOnce(null);

        assertTrue(processed == 2);
        verify(processor).process("A", "QC", -5);
        verify(processor).process("B", "ON", -5);
        verify(repo, times(1)).findSupported();
    }

    @Test
    void millisUntilNextHourReturnsPositiveDelayWithinOneHour() throws Exception {
        long millis = (long) invokePrivate("millisUntilNextHour");

        assertTrue(millis > 0);
        assertTrue(millis <= Duration.ofHours(1).toMillis());
    }

    @Test
    void loopStopsWhenInterruptedDuringSleep() throws Exception {
        when(repo.findSupported()).thenReturn(List.of());

        Thread thread = new Thread(() -> {
            try {
                invokePrivate("loop");
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        });
        thread.start();

        waitForRepoCall();
        thread.interrupt();
        thread.join(Duration.ofSeconds(2).toMillis());

        assertTrue(!thread.isAlive());
    }

    private Thread waitForWorkerThread() throws InterruptedException {
        long deadline = System.currentTimeMillis() + 2000;
        while (System.currentTimeMillis() < deadline) {
            Thread thread = findWorkerThread();
            if (thread != null) {
                return thread;
            }
            Thread.sleep(25);
        }
        throw new AssertionError("worker thread was not started");
    }

    private Thread findWorkerThread() {
        for (Thread thread : Thread.getAllStackTraces().keySet()) {
            if ("water-station-worker".equals(thread.getName())) {
                return thread;
            }
        }
        return null;
    }

    private void waitForRepoCall() throws InterruptedException {
        long deadline = System.currentTimeMillis() + 2000;
        while (System.currentTimeMillis() < deadline) {
            try {
                verify(repo, times(1)).findSupported();
                return;
            } catch (AssertionError ignored) {
                Thread.sleep(25);
            }
        }
        throw new AssertionError("loop did not execute runOnce");
    }

    private Object invokePrivate(String name, Class<?>... parameterTypes) throws Exception {
        Method method = StationWorkerCA.class.getDeclaredMethod(name, parameterTypes);
        method.setAccessible(true);
        return method.invoke(worker);
    }
}
