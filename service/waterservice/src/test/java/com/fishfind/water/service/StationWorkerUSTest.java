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

class StationWorkerUSTest {

    private final WaterStationRepository repo = mock(WaterStationRepository.class);
    private final StationProcessorUS processor = mock(StationProcessorUS.class);
    private final StationWorkerUS worker = new StationWorkerUS(repo, processor);

    @Test
    void runDoesNothingInConsoleMode() {
        worker.run(new DefaultApplicationArguments("--console"));

        verify(repo, never()).findSupported("US");
    }

    @Test
    void runStartsBackgroundThreadInNormalMode() throws Exception {
        when(repo.findSupported("US")).thenReturn(List.of());

        worker.run(new DefaultApplicationArguments());

        Thread thread = waitForWorkerThread();
        assertTrue(thread.isAlive());
        thread.interrupt();
        thread.join(Duration.ofSeconds(2).toMillis());
        verify(repo, times(1)).findSupported("US");
    }

    @Test
    void runOnceProcessesAllStationsAndAppliesFilter() throws Exception {
        when(repo.findSupported("US")).thenReturn(List.of(
                new StationRef("08312000", "NM", -7),
                new StationRef("08313000", "NY", -5)
        ));
        ReflectionTestUtils.setField(worker, "pauseBetweenStationsMs", 0L);

        int processed = worker.runOnce("08313000");

        assertTrue(processed == 1);
        verify(processor).process("08313000", "NY", -5);
        verify(processor, never()).process("08312000", "NM", -7);
        verify(repo, times(1)).findSupported("US");
    }

    @Test
    void runOnceProcessesAllStationsFromSingleLoadedList() throws Exception {
        when(repo.findSupported("US")).thenReturn(List.of(
                new StationRef("08312000", "NM", -7),
                new StationRef("08313000", "NY", -5)
        ));
        ReflectionTestUtils.setField(worker, "pauseBetweenStationsMs", 0L);

        int processed = worker.runOnce(null);

        assertTrue(processed == 2);
        verify(processor).process("08312000", "NM", -7);
        verify(processor).process("08313000", "NY", -5);
        verify(repo, times(1)).findSupported("US");
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
    void millisUntilNextHourReturnsRemainingDelayWithinCurrentCycleWindow() throws Exception {
        ZonedDateTime cycleStartedAt = ZonedDateTime.parse("2026-03-23T12:15:00-04:00[America/New_York]");
        ZonedDateTime now = ZonedDateTime.parse("2026-03-23T12:45:00-04:00[America/New_York]");

        long millis = (long) invokePrivate("millisUntilNextHour",
                new Class<?>[]{ZonedDateTime.class, ZonedDateTime.class},
                cycleStartedAt, now);

        assertTrue(millis == Duration.ofMinutes(15).toMillis());
    }

    @Test
    void loopStopsWhenInterruptedDuringSleep() throws Exception {
        when(repo.findSupported("US")).thenReturn(List.of());

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
            if ("water-station-worker-us".equals(thread.getName())) {
                return thread;
            }
        }
        return null;
    }

    private void waitForRepoCall() throws InterruptedException {
        long deadline = System.currentTimeMillis() + 2000;
        while (System.currentTimeMillis() < deadline) {
            try {
                verify(repo, times(1)).findSupported("US");
                return;
            } catch (AssertionError ignored) {
                Thread.sleep(25);
            }
        }
        throw new AssertionError("loop did not execute runOnce");
    }

    private Object invokePrivate(String name, Class<?>... parameterTypes) throws Exception {
        Method method = StationWorkerUS.class.getDeclaredMethod(name, parameterTypes);
        method.setAccessible(true);
        return method.invoke(worker);
    }

    private Object invokePrivate(String name, Class<?>[] parameterTypes, Object... args) throws Exception {
        Method method = StationWorkerUS.class.getDeclaredMethod(name, parameterTypes);
        method.setAccessible(true);
        return method.invoke(worker, args);
    }
}
