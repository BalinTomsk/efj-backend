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
import static org.mockito.ArgumentMatchers.any;
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
    // Run "async" work inline so cycle tests are deterministic.
    private final Executor inlineExecutor = Runnable::run;
    private final SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();

    private final StationWorker worker = new StationWorker(
            repo, processorCA, processorUS, postProcessingService, scheduler, inlineExecutor, meterRegistry);

    StationWorkerTest() {
        ReflectionTestUtils.setField(worker, "pauseBetweenStationsMs", 0L);
        ReflectionTestUtils.setField(worker, "cron", "0 0 * * * *");
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
    void runOnceProcessesFilteredCaStationsAndCountsSuccesses() {
        when(repo.findSupported("CA")).thenReturn(List.of(
                new StationRef("A", "QC", -5),
                new StationRef("B", "ON", -5)
        ));
        when(processorCA.process("B", "ON", -5)).thenReturn(true);

        int processed = worker.runOnce("CA", "B");

        assertEquals(1, processed);
        verify(processorCA).process("B", "ON", -5);
        verify(processorCA, never()).process("A", "QC", -5);
    }

    @Test
    void runOnceCountsOnlySuccessfulStations() {
        when(repo.findSupported("US")).thenReturn(List.of(
                new StationRef("08312000", "NM", -7),
                new StationRef("08313000", "NY", -5)
        ));
        when(processorUS.process("08312000", "NM", -7)).thenReturn(true);
        when(processorUS.process("08313000", "NY", -5)).thenReturn(false); // e.g. 404/skip

        int processed = worker.runOnce("US", null);

        assertEquals(1, processed);
    }

    @Test
    void runCycleProcessesBothCountriesAndRunsPostProcessingOnceWhenAnySucceed() {
        when(repo.findSupported("CA")).thenReturn(List.of(new StationRef("A", "QC", -5)));
        when(repo.findSupported("US")).thenReturn(List.of(new StationRef("08312000", "NM", -7)));
        when(processorCA.process("A", "QC", -5)).thenReturn(true);
        when(processorUS.process("08312000", "NM", -7)).thenReturn(false);

        int processed = worker.runCycle(null);

        assertEquals(1, processed);
        verify(processorCA).process("A", "QC", -5);
        verify(processorUS).process("08312000", "NM", -7);
        verify(postProcessingService, times(1)).runAfterStationProcessing();
    }

    @Test
    void runCycleSkipsPostProcessingWhenNoStationSucceeds() {
        when(repo.findSupported("CA")).thenReturn(List.of(new StationRef("A", "QC", -5)));
        when(repo.findSupported("US")).thenReturn(List.of());
        when(processorCA.process("A", "QC", -5)).thenReturn(false);

        int processed = worker.runCycle(null);

        assertEquals(0, processed);
        verify(postProcessingService, never()).runAfterStationProcessing();
    }

    @Test
    void runOnceRecordsSuccessAndFailureCounters() {
        when(repo.findSupported("US")).thenReturn(List.of(
                new StationRef("08312000", "NM", -7),
                new StationRef("08313000", "NY", -5)
        ));
        when(processorUS.process("08312000", "NM", -7)).thenReturn(true);
        when(processorUS.process("08313000", "NY", -5)).thenReturn(false);

        worker.runOnce("US", null);

        assertEquals(1.0, meterRegistry.counter("water.station.processed",
                "country", "US", "outcome", "success").count());
        assertEquals(1.0, meterRegistry.counter("water.station.processed",
                "country", "US", "outcome", "failure").count());
    }

    @Test
    void runCycleIsolatesAFailingCountryPassFromTheOther() {
        when(repo.findSupported("CA")).thenThrow(new RuntimeException("db down"));
        when(repo.findSupported("US")).thenReturn(List.of(new StationRef("08312000", "NM", -7)));
        when(processorUS.process("08312000", "NM", -7)).thenReturn(true);

        int processed = worker.runCycle(null);

        // CA pass failed, US pass still ran and post-processing still happened.
        assertEquals(1, processed);
        verify(postProcessingService, times(1)).runAfterStationProcessing();
    }
}
