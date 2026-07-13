package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.WeatherStationRepository;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.mockito.Mockito;
import org.slf4j.LoggerFactory;
import org.springframework.boot.DefaultApplicationArguments;
import org.springframework.test.util.ReflectionTestUtils;

class StationWorkerTest {

    private static final long EIGHT_HOURS_MS = 8L * 60 * 60 * 1000;

    private WeatherStationRepository stationRepository;
    private StationProcessorOpen processor;
    private StationPostProcessingService postProcessing;

    private final List<Long> recordedSleeps = new ArrayList<>();
    private RecordingWorker worker;

    private static final List<StationRef> THREE_STATIONS = List.of(
            new StationRef("MLI-1", 1, 1, "WA"),
            new StationRef("MLI-2", 2, 2, "OR"),
            new StationRef("MLI-3", 3, 3, "CA"));

    @BeforeEach
    void setUp() {
        stationRepository = Mockito.mock(WeatherStationRepository.class);
        processor = Mockito.mock(StationProcessorOpen.class);
        postProcessing = Mockito.mock(StationPostProcessingService.class);
        worker = new RecordingWorker();
        ReflectionTestUtils.setField(worker, "maxFailureRate", 0.5);
    }

    @Test
    void calculatesPerStationDelayWithinTimeBudget() {
        assertThat(worker.calculateDelayMs(0)).isEqualTo(2000L);
        assertThat(worker.calculateDelayMs(1)).isEqualTo(2000L);
        assertThat(worker.calculateDelayMs(2)).isEqualTo(EIGHT_HOURS_MS / 2);
        assertThat(worker.calculateDelayMs(1_000_000)).isEqualTo(2000L);
    }

    @Test
    void millisUntilNextMidnightIsWithinADay() {
        long ms = worker.millisUntilNextMidnight();
        assertThat(ms).isGreaterThanOrEqualTo(0L).isLessThanOrEqualTo(24L * 60 * 60 * 1000);
    }

    @Test
    void runOnceProcessesAllStationsThenPostProcesses() throws Exception {
        when(stationRepository.findSupportedUsStations()).thenReturn(THREE_STATIONS);
        when(processor.process(any())).thenReturn(ProcessingOutcome.PROCESSED);

        StationWorker.RunResult result = worker.runOnce(null);

        assertThat(result.processedStations()).isEqualTo(3);
        assertThat(result.failedStations()).isZero();
        InOrder inOrder = Mockito.inOrder(processor, postProcessing);
        inOrder.verify(processor).process(THREE_STATIONS.get(0));
        inOrder.verify(processor).process(THREE_STATIONS.get(1));
        inOrder.verify(processor).process(THREE_STATIONS.get(2));
        inOrder.verify(postProcessing).runAfterStationProcessing();
        assertThat(recordedSleeps).allMatch(ms -> ms <= 60 * 60 * 1000L);
        assertThat(recordedSleeps.stream().mapToLong(Long::longValue).sum()).isEqualTo(EIGHT_HOURS_MS);
    }

    @Test
    void runOnceFiltersToRequestedStation() throws Exception {
        when(stationRepository.findSupportedUsStations()).thenReturn(THREE_STATIONS);
        when(processor.process(any())).thenReturn(ProcessingOutcome.PROCESSED);

        StationWorker.RunResult result = worker.runOnce("MLI-2");

        assertThat(result.processedStations()).isEqualTo(1);
        verify(processor).process(THREE_STATIONS.get(1));
        verify(processor, never()).process(THREE_STATIONS.get(0));
        verify(processor, never()).process(THREE_STATIONS.get(2));
        verify(postProcessing).runAfterStationProcessing();
    }

    @Test
    void skippedStationsDoNotBlockPostProcessing() throws Exception {
        when(stationRepository.findSupportedUsStations()).thenReturn(THREE_STATIONS);
        when(processor.process(any())).thenReturn(ProcessingOutcome.SKIPPED);

        StationWorker.RunResult result = worker.runOnce(null);

        assertThat(result.processedStations()).isZero();
        verify(postProcessing).runAfterStationProcessing();
    }

    @Test
    void degradedCycleSkipsPostProcessing() throws Exception {
        when(stationRepository.findSupportedUsStations()).thenReturn(THREE_STATIONS);
        when(processor.process(any())).thenReturn(ProcessingOutcome.FAILED);

        StationWorker.RunResult result = worker.runOnce(null);

        assertThat(result.processedStations()).isZero();
        assertThat(result.failedStations()).isEqualTo(3);
        verify(postProcessing, never()).runAfterStationProcessing();
    }

    @Test
    void runOnceLogsCountryPassAndFullCycleStationSummaries() throws Exception {
        when(stationRepository.findSupportedUsStations()).thenReturn(THREE_STATIONS);
        when(processor.process(THREE_STATIONS.get(0))).thenReturn(ProcessingOutcome.PROCESSED);
        when(processor.process(THREE_STATIONS.get(1))).thenReturn(ProcessingOutcome.FAILED);
        when(processor.process(THREE_STATIONS.get(2))).thenReturn(ProcessingOutcome.PROCESSED);
        ch.qos.logback.classic.Logger logger = stationWorkerLogger();
        ListAppender<ILoggingEvent> appender = attachLogAppender(logger);

        try {
            worker.runOnce(null);

            assertThat(appender.list)
                    .extracting(ILoggingEvent::getFormattedMessage)
                    .anySatisfy(message -> assertThat(message)
                            .contains("Country pass completed. country=US")
                            .contains("successfulStations=2")
                            .contains("failedStations=1")
                            .contains("lastProcessedStation=MLI-3")
                            .contains("lastFailedStation=MLI-2"));
            assertThat(appender.list)
                    .extracting(ILoggingEvent::getFormattedMessage)
                    .noneMatch(message -> message.contains("Full cycle"));
        } finally {
            logger.detachAppender(appender);
        }
    }

    @Test
    void runOnceLogsHourlyProgressBeforeFinalCycleSummary() throws Exception {
        when(stationRepository.findSupportedUsStations()).thenReturn(THREE_STATIONS);
        when(processor.process(THREE_STATIONS.get(0))).thenReturn(ProcessingOutcome.PROCESSED);
        when(processor.process(THREE_STATIONS.get(1))).thenReturn(ProcessingOutcome.FAILED);
        when(processor.process(THREE_STATIONS.get(2))).thenReturn(ProcessingOutcome.PROCESSED);
        ch.qos.logback.classic.Logger logger = stationWorkerLogger();
        ListAppender<ILoggingEvent> appender = attachLogAppender(logger);

        try {
            worker.runOnce(null);

            assertThat(appender.list)
                    .extracting(ILoggingEvent::getFormattedMessage)
                    .anySatisfy(message -> assertThat(message)
                            .contains("Country pass hourly progress. country=US")
                            .contains("successfulStations=1")
                            .contains("failedStations=0")
                            .contains("lastProcessedStation=MLI-1")
                            .contains("lastFailedStation=<none>"))
                    .anySatisfy(message -> assertThat(message)
                            .contains("Country pass completed. country=US")
                            .contains("successfulStations=2")
                            .contains("failedStations=1")
                            .contains("lastProcessedStation=MLI-3")
                            .contains("lastFailedStation=MLI-2"));
            assertThat(appender.list)
                    .extracting(ILoggingEvent::getFormattedMessage)
                    .noneMatch(message -> message.contains("Full cycle"));
        } finally {
            logger.detachAppender(appender);
        }
    }

    @Test
    void stopRequestedBeforeCycleSkipsProcessingAndPostProcessing() throws Exception {
        when(stationRepository.findSupportedUsStations()).thenReturn(THREE_STATIONS);
        ReflectionTestUtils.setField(worker, "running", false);

        StationWorker.RunResult result = worker.runOnce(null);

        assertThat(result.processedStations()).isZero();
        verify(processor, never()).process(any());
        verify(postProcessing, never()).runAfterStationProcessing();
    }

    @Test
    void consoleModeDoesNotStartBackgroundWork() {
        worker.run(new DefaultApplicationArguments("--console"));

        verifyNoInteractions(stationRepository, processor, postProcessing);
    }

    @Test
    void shutdownClearsRunningFlagWhenNoThreadStarted() {
        worker.shutdown();

        assertThat(ReflectionTestUtils.getField(worker, "running")).isEqualTo(false);
    }

    private ch.qos.logback.classic.Logger stationWorkerLogger() {
        return (ch.qos.logback.classic.Logger) LoggerFactory.getLogger(StationWorker.class);
    }

    private ListAppender<ILoggingEvent> attachLogAppender(ch.qos.logback.classic.Logger logger) {
        ListAppender<ILoggingEvent> appender = new ListAppender<>();
        appender.start();
        logger.addAppender(appender);
        return appender;
    }

    private class RecordingWorker extends StationWorker {
        private long currentTimeMs;

        RecordingWorker() {
            super(stationRepository, processor, postProcessing, new CycleReportRecorder());
        }

        @Override
        protected void sleep(long ms) {
            recordedSleeps.add(ms);
            currentTimeMs += ms;
        }

        @Override
        protected long currentTimeMillis() {
            return currentTimeMs;
        }
    }
}
