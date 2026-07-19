package com.fishfind.water.service;

import com.fishfind.water.domain.StationRef;
import com.fishfind.water.repo.WaterStationRepository;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.boot.DefaultApplicationArguments;
import org.springframework.scheduling.Trigger;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;
import org.springframework.scheduling.support.CronTrigger;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;
import java.util.concurrent.Executor;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
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
    private final ThreadPoolTaskScheduler scheduler = mock(ThreadPoolTaskScheduler.class);
    private final StationHttp503BackoffService http503BackoffService = mock(StationHttp503BackoffService.class);
    // Run "async" work inline so cycle tests are deterministic.
    private final Executor inlineExecutor = Runnable::run;
    private final SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();

    private final StationWorker worker = new StationWorker(
            repo, processorCA, processorUS, postProcessingService, scheduler, inlineExecutor, meterRegistry,
            http503BackoffService);

    StationWorkerTest() {
        ReflectionTestUtils.setField(worker, "pauseBetweenStationsMs", 0L);
        ReflectionTestUtils.setField(worker, "cron", "0 0 * * * *");
        ReflectionTestUtils.setField(worker, "enabled", true);
    }

    @Test
    void consoleModeDoesNotScheduleAnything() {
        worker.run(new DefaultApplicationArguments("--console"));

        verify(scheduler, never()).schedule(any(Runnable.class), any(Trigger.class));
    }

    @Test
    void normalModeSchedulesCronCycle() {
        worker.run(new DefaultApplicationArguments());

        verify(scheduler).schedule(any(Runnable.class), any(CronTrigger.class));
    }

    @Test
    void disabledWorkerDoesNotScheduleAnything() {
        ReflectionTestUtils.setField(worker, "enabled", false);

        worker.run(new DefaultApplicationArguments());

        verify(scheduler, never()).schedule(any(Runnable.class), any(Trigger.class));
    }

    @Test
    void runOnceProcessesFilteredCaStationsAndCountsSuccesses() {
        when(repo.findSupported("CA")).thenReturn(List.of(
                new StationRef("A", "QC", -5),
                new StationRef("B", "ON", -5)
        ));
        when(processorCA.processWithOutcome("B", "ON", -5)).thenReturn(ProcessingOutcome.PROCESSED);

        int processed = worker.runOnce("CA", "B");

        assertEquals(1, processed);
        verify(processorCA).processWithOutcome("B", "ON", -5);
        verify(processorCA, never()).processWithOutcome("A", "QC", -5);
    }

    @Test
    void runOnceCountsOnlySuccessfulStations() {
        when(repo.findSupported("US")).thenReturn(List.of(
                new StationRef("08312000", "NM", -7),
                new StationRef("08313000", "NY", -5)
        ));
        when(processorUS.processWithOutcome("08312000", "NM", -7)).thenReturn(ProcessingOutcome.PROCESSED);
        when(processorUS.processWithOutcome("08313000", "NY", -5)).thenReturn(ProcessingOutcome.SKIPPED);

        int processed = worker.runOnce("US", null);

        assertEquals(1, processed);
    }

    @Test
    void runCycleProcessesBothCountriesAndRunsPostProcessingOnceWhenAnySucceed() {
        when(repo.findSupported("CA")).thenReturn(List.of(new StationRef("A", "QC", -5)));
        when(repo.findSupported("US")).thenReturn(List.of(new StationRef("08312000", "NM", -7)));
        when(processorCA.processWithOutcome("A", "QC", -5)).thenReturn(ProcessingOutcome.PROCESSED);
        when(processorUS.processWithOutcome("08312000", "NM", -7)).thenReturn(ProcessingOutcome.SKIPPED);

        int processed = worker.runCycle(null);

        assertEquals(1, processed);
        verify(processorCA).processWithOutcome("A", "QC", -5);
        verify(processorUS).processWithOutcome("08312000", "NM", -7);
        verify(postProcessingService, times(1)).runAfterStationProcessing();
        verify(postProcessingService, times(1)).cleanOldWaterData();
    }

    @Test
    void runCycleSkipsSpeciesPostProcessingButCleansOldWaterDataWhenNoStationSucceeds() {
        when(repo.findSupported("CA")).thenReturn(List.of(new StationRef("A", "QC", -5)));
        when(repo.findSupported("US")).thenReturn(List.of());
        when(processorCA.processWithOutcome("A", "QC", -5)).thenReturn(ProcessingOutcome.SKIPPED);

        int processed = worker.runCycle(null);

        assertEquals(0, processed);
        verify(postProcessingService, never()).runAfterStationProcessing();
        verify(postProcessingService, times(1)).cleanOldWaterData();
    }

    @Test
    void runOnceRecordsSuccessAndFailureCounters() {
        when(repo.findSupported("US")).thenReturn(List.of(
                new StationRef("08312000", "NM", -7),
                new StationRef("08313000", "NY", -5)
        ));
        when(processorUS.processWithOutcome("08312000", "NM", -7)).thenReturn(ProcessingOutcome.PROCESSED);
        when(processorUS.processWithOutcome("08313000", "NY", -5)).thenReturn(ProcessingOutcome.SKIPPED);

        worker.runOnce("US", null);

        assertEquals(1.0, meterRegistry.counter("water.station.processed",
                "country", "US", "outcome", "success").count());
        assertEquals(1.0, meterRegistry.counter("water.station.processed",
                "country", "US", "outcome", "failure").count());
    }

    @Test
    void refreshesDueHttp503BackoffBeforeLoadingStations() {
        when(repo.findSupported("CA")).thenReturn(List.of());

        worker.runOnce("CA", null);

        var inOrder = inOrder(http503BackoffService, repo);
        inOrder.verify(http503BackoffService).refreshDue(any(java.time.LocalDate.class));
        inOrder.verify(repo).findSupported("CA");
    }

    @Test
    void recordsHttp503FailureAndResetsBackoffOnSuccess() {
        StationRef first = new StationRef("08312000", "NM", -7);
        StationRef second = new StationRef("08313000", "NY", -5);
        when(repo.findSupported("US")).thenReturn(List.of(first, second));
        when(processorUS.processWithOutcome("08312000", "NM", -7))
                .thenReturn(ProcessingOutcome.FAILED_HTTP_503);
        when(processorUS.processWithOutcome("08313000", "NY", -5))
                .thenReturn(ProcessingOutcome.PROCESSED);

        int processed = worker.runOnce("US", null);

        assertEquals(1, processed);
        verify(http503BackoffService).recordHttp503(eq("usgs"), eq("US"), eq(first),
                any(java.time.LocalDate.class));
        verify(http503BackoffService).recordProcessed("usgs", "US", second);
        verify(http503BackoffService, never()).recordProcessed("usgs", "US", first);
    }

    @Test
    void runCycleIsolatesAFailingCountryPassFromTheOther() {
        when(repo.findSupported("CA")).thenThrow(new RuntimeException("db down"));
        when(repo.findSupported("US")).thenReturn(List.of(new StationRef("08312000", "NM", -7)));
        when(processorUS.processWithOutcome("08312000", "NM", -7)).thenReturn(ProcessingOutcome.PROCESSED);

        int processed = worker.runCycle(null);

        // CA pass failed, US pass still ran and post-processing still happened.
        assertEquals(1, processed);
        verify(postProcessingService, times(1)).runAfterStationProcessing();
        verify(postProcessingService, times(1)).cleanOldWaterData();
    }

    @Test
    void runCyclePropagatesSpeciesFailureNotCleanupFailureWhenBothFail() {
        when(repo.findSupported("CA")).thenReturn(List.of(new StationRef("A", "QC", -5)));
        when(repo.findSupported("US")).thenReturn(List.of());
        when(processorCA.processWithOutcome("A", "QC", -5)).thenReturn(ProcessingOutcome.PROCESSED);
        doThrow(new RuntimeException("species push failed"))
                .when(postProcessingService).runAfterStationProcessing();
        doThrow(new RuntimeException("cleanup failed"))
                .when(postProcessingService).cleanOldWaterData();

        RuntimeException ex = assertThrows(RuntimeException.class, () -> worker.runCycle(null));

        // The original species failure must not be masked by the cleanup failure in the finally block.
        assertEquals("species push failed", ex.getMessage());
        assertEquals(1, ex.getSuppressed().length);
        assertEquals("cleanup failed", ex.getSuppressed()[0].getMessage());
    }

    @Test
    void runCycleSurvivesExecutorRejectionAndStillCleansOldWaterData() {
        Executor rejectingExecutor = task -> {
            throw new java.util.concurrent.RejectedExecutionException("executor shutting down");
        };
        StationWorker rejectedWorker = new StationWorker(
                repo, processorCA, processorUS, postProcessingService, scheduler, rejectingExecutor, meterRegistry,
                http503BackoffService);
        ReflectionTestUtils.setField(rejectedWorker, "pauseBetweenStationsMs", 0L);

        int processed = rejectedWorker.runCycle(null);

        // Both passes failed to start; the cycle must complete gracefully and still run cleanup.
        assertEquals(0, processed);
        verify(postProcessingService, never()).runAfterStationProcessing();
        verify(postProcessingService, times(1)).cleanOldWaterData();
    }

    @Test
    void runOnceDoesNotSleepAfterTheFinalStation() {
        // The pause exists to be polite between requests; sleeping after the last station of a pass
        // just delays the cycle for nothing.
        ReflectionTestUtils.setField(worker, "pauseBetweenStationsMs", 500L);
        when(repo.findSupported("CA")).thenReturn(List.of(new StationRef("A", "QC", -5)));
        when(processorCA.processWithOutcome("A", "QC", -5)).thenReturn(ProcessingOutcome.PROCESSED);

        long startNanos = System.nanoTime();
        worker.runOnce("CA", null);
        long elapsedMs = (System.nanoTime() - startNanos) / 1_000_000;

        assertTrue(elapsedMs < 400, "single-station pass slept the between-stations pause: " + elapsedMs + "ms");
    }

    @Test
    void cycleOverrunningItsCronPeriodIsCountedAndVisible() {
        // Cycle started at the top of the hour and finished after the next trigger should have fired:
        // the pool-size-1 scheduler silently skipped a cycle, which must be observable.
        worker.recordCycleOutcome(
                java.time.Instant.parse("2026-07-13T10:00:00Z"),
                java.time.Instant.parse("2026-07-13T11:30:00Z"));

        assertEquals(1.0, meterRegistry.counter("water.cycle.overrun").count());
    }

    @Test
    void cycleFinishingWithinItsCronPeriodDoesNotCountAnOverrun() {
        worker.recordCycleOutcome(
                java.time.Instant.parse("2026-07-13T10:00:00Z"),
                java.time.Instant.parse("2026-07-13T10:10:00Z"));

        assertEquals(0.0, meterRegistry.counter("water.cycle.overrun").count());
    }

    @Test
    void runCycleStillCleansOldWaterDataWhenSpeciesPostProcessingFails() {
        when(repo.findSupported("CA")).thenReturn(List.of(new StationRef("A", "QC", -5)));
        when(repo.findSupported("US")).thenReturn(List.of());
        when(processorCA.processWithOutcome("A", "QC", -5)).thenReturn(ProcessingOutcome.PROCESSED);
        doThrow(new RuntimeException("species push failed"))
                .when(postProcessingService).runAfterStationProcessing();

        RuntimeException ex = assertThrows(RuntimeException.class, () -> worker.runCycle(null));

        assertEquals("species push failed", ex.getMessage());
        verify(postProcessingService, times(1)).cleanOldWaterData();
    }
}
