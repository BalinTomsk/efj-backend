package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.timeout;
import static org.mockito.Mockito.when;

import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.WeatherStationRepository;
import java.time.LocalDate;
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
    private StationProcessorWeatherGov weatherGovProcessor;
    private StationProcessorVisualCrossing visualCrossingProcessor;
    private StationProcessorGoogleWeather googleWeatherProcessor;
    private StationProcessorWeatherCanada weatherCanadaProcessor;
    private StationPostProcessingService postProcessing;
    private WeatherApiUsageTracker usageTracker;

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
        weatherGovProcessor = Mockito.mock(StationProcessorWeatherGov.class);
        visualCrossingProcessor = Mockito.mock(StationProcessorVisualCrossing.class);
        googleWeatherProcessor = Mockito.mock(StationProcessorGoogleWeather.class);
        weatherCanadaProcessor = Mockito.mock(StationProcessorWeatherCanada.class);
        postProcessing = Mockito.mock(StationPostProcessingService.class);
        usageTracker = Mockito.mock(WeatherApiUsageTracker.class);
        when(stationRepository.countSupportedStations(anyString())).thenReturn(THREE_STATIONS.size());
        when(stationRepository.findSupportedStations(anyString(), anyInt())).thenAnswer(invocation -> {
            int limit = invocation.getArgument(1);
            return THREE_STATIONS.subList(0, Math.min(limit, THREE_STATIONS.size()));
        });
        when(usageTracker.reserve(anyString(), any(LocalDate.class), anyInt(), anyInt())).thenAnswer(invocation -> {
            int requested = invocation.getArgument(2);
            int dailyLimit = invocation.getArgument(3);
            return new WeatherApiUsageTracker.UsageReservation(0, dailyLimit, requested, requested, true);
        });
        worker = new RecordingWorker();
        ReflectionTestUtils.setField(worker, "maxFailureRate", 0.5);
        ReflectionTestUtils.setField(worker, "weatherGovDailyLimit", 900);
        ReflectionTestUtils.setField(worker, "openMeteoDailyLimit", 10000);
        ReflectionTestUtils.setField(worker, "visualCrossingDailyLimit", 1000);
        ReflectionTestUtils.setField(worker, "googleWeatherDailyLimit", 161);
        ReflectionTestUtils.setField(worker, "weatherCanadaDailyLimit", 900);
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
        when(weatherGovProcessor.process(any(), anyString())).thenReturn(ProcessingOutcome.PROCESSED);

        StationWorker.RunResult result = worker.runOnce(null);

        assertThat(result.processedStations()).isEqualTo(3);
        assertThat(result.failedStations()).isZero();
        InOrder inOrder = Mockito.inOrder(weatherGovProcessor, postProcessing);
        inOrder.verify(weatherGovProcessor).process(THREE_STATIONS.get(0), "US");
        inOrder.verify(weatherGovProcessor).process(THREE_STATIONS.get(1), "US");
        inOrder.verify(weatherGovProcessor).process(THREE_STATIONS.get(2), "US");
        inOrder.verify(postProcessing).runAfterStationProcessing();
        assertThat(recordedSleeps).allMatch(ms -> ms <= 60 * 60 * 1000L);
        assertThat(recordedSleeps.stream().mapToLong(Long::longValue).sum()).isEqualTo(EIGHT_HOURS_MS);
    }

    @Test
    void runOnceFiltersToRequestedStation() throws Exception {
        when(weatherGovProcessor.process(any(), anyString())).thenReturn(ProcessingOutcome.PROCESSED);

        StationWorker.RunResult result = worker.runOnce("MLI-2");

        assertThat(result.processedStations()).isEqualTo(1);
        verify(weatherGovProcessor).process(THREE_STATIONS.get(1), "US");
        verify(weatherGovProcessor, never()).process(THREE_STATIONS.get(0), "US");
        verify(weatherGovProcessor, never()).process(THREE_STATIONS.get(2), "US");
        verify(postProcessing).runAfterStationProcessing();
    }

    @Test
    void skippedStationsDoNotBlockPostProcessing() throws Exception {
        when(weatherGovProcessor.process(any(), anyString())).thenReturn(ProcessingOutcome.SKIPPED);

        StationWorker.RunResult result = worker.runOnce(null);

        assertThat(result.processedStations()).isZero();
        verify(postProcessing).runAfterStationProcessing();
    }

    @Test
    void degradedCycleSkipsPostProcessing() throws Exception {
        when(weatherGovProcessor.process(any(), anyString())).thenReturn(ProcessingOutcome.FAILED);

        StationWorker.RunResult result = worker.runOnce(null);

        assertThat(result.processedStations()).isZero();
        assertThat(result.failedStations()).isEqualTo(3);
        verify(postProcessing, never()).runAfterStationProcessing();
    }

    @Test
    void dailyReservationCapsStationsLoadedAndProcessed() throws Exception {
        when(usageTracker.reserve(eq("weather-gov"), any(LocalDate.class), anyInt(), anyInt()))
                .thenReturn(new WeatherApiUsageTracker.UsageReservation(898, 900, 2, 3, true));
        when(weatherGovProcessor.process(any(), anyString())).thenReturn(ProcessingOutcome.PROCESSED);

        StationWorker.RunResult result = worker.runOnce(null);

        assertThat(result.processedStations()).isEqualTo(2);
        verify(stationRepository).findSupportedStations("US", 2);
        verify(weatherGovProcessor).process(THREE_STATIONS.get(0), "US");
        verify(weatherGovProcessor).process(THREE_STATIONS.get(1), "US");
        verify(weatherGovProcessor, never()).process(THREE_STATIONS.get(2), "US");
    }

    @Test
    void exhaustedDailyReservationSkipsProviderWithoutApiCalls() throws Exception {
        when(usageTracker.reserve(eq("weather-gov"), any(LocalDate.class), anyInt(), anyInt()))
                .thenReturn(new WeatherApiUsageTracker.UsageReservation(900, 900, 0, 3, true));

        StationWorker.RunResult result = worker.runOnce(null);

        assertThat(result.processedStations()).isZero();
        assertThat(result.failedStations()).isZero();
        verify(stationRepository, never()).findSupportedStations(anyString(), anyInt());
        verify(weatherGovProcessor, never()).process(any(), anyString());
        verify(postProcessing).runAfterStationProcessing();
    }

    @Test
    void runOnceLogsCountryPassAndFullCycleStationSummaries() throws Exception {
        when(weatherGovProcessor.process(THREE_STATIONS.get(0), "US")).thenReturn(ProcessingOutcome.PROCESSED);
        when(weatherGovProcessor.process(THREE_STATIONS.get(1), "US")).thenReturn(ProcessingOutcome.FAILED);
        when(weatherGovProcessor.process(THREE_STATIONS.get(2), "US")).thenReturn(ProcessingOutcome.PROCESSED);
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
        when(weatherGovProcessor.process(THREE_STATIONS.get(0), "US")).thenReturn(ProcessingOutcome.PROCESSED);
        when(weatherGovProcessor.process(THREE_STATIONS.get(1), "US")).thenReturn(ProcessingOutcome.FAILED);
        when(weatherGovProcessor.process(THREE_STATIONS.get(2), "US")).thenReturn(ProcessingOutcome.PROCESSED);
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
        ReflectionTestUtils.setField(worker, "running", false);

        StationWorker.RunResult result = worker.runOnce(null);

        assertThat(result.processedStations()).isZero();
        verify(weatherGovProcessor, never()).process(any(), anyString());
        verify(postProcessing, never()).runAfterStationProcessing();
    }

    @Test
    void consoleModeDoesNotStartBackgroundWork() {
        worker.run(new DefaultApplicationArguments("--console"));

        verifyNoInteractions(processor, weatherGovProcessor, visualCrossingProcessor, googleWeatherProcessor,
                weatherCanadaProcessor, postProcessing);
    }

    @Test
    void backgroundModeStartsWeatherGovUsOpenMeteoCaVisualCrossingUsGoogleWeatherUsAndWeatherCanadaCaWorkers() {
        when(stationRepository.countSupportedStations(anyString())).thenReturn(0);
        StationWorker backgroundWorker = new StationWorker(
                stationRepository,
                processor,
                weatherGovProcessor,
                visualCrossingProcessor,
                googleWeatherProcessor,
                weatherCanadaProcessor,
                postProcessing,
                new CycleReportRecorder(),
                usageTracker);
        ReflectionTestUtils.setField(backgroundWorker, "maxFailureRate", 0.5);
        ReflectionTestUtils.setField(backgroundWorker, "weatherGovDailyLimit", 900);
        ReflectionTestUtils.setField(backgroundWorker, "openMeteoDailyLimit", 10000);
        ReflectionTestUtils.setField(backgroundWorker, "visualCrossingDailyLimit", 1000);
        ReflectionTestUtils.setField(backgroundWorker, "googleWeatherDailyLimit", 161);
        ReflectionTestUtils.setField(backgroundWorker, "weatherCanadaDailyLimit", 900);

        backgroundWorker.run(new DefaultApplicationArguments());

        @SuppressWarnings("unchecked")
        List<Thread> threads = (List<Thread>) ReflectionTestUtils.getField(backgroundWorker, "workerThreads");
        assertThat(threads)
                .extracting(Thread::getName)
                .containsExactly(
                        "weather-data-worker-weather-gov-us",
                        "weather-data-worker-open-ca",
                        "weather-data-worker-visual-crossing-us",
                        "weather-data-worker-google-weather-us",
                        "weather-data-worker-weather-canada-ca");

        verify(usageTracker, timeout(2000)).reserve(eq("google-weather"), any(LocalDate.class), eq(0), eq(161));
        verify(usageTracker, timeout(2000)).reserve(eq("weather-canada"), any(LocalDate.class), eq(0), eq(900));

        backgroundWorker.shutdown();
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
            super(stationRepository,
                    processor,
                    weatherGovProcessor,
                    visualCrossingProcessor,
                    googleWeatherProcessor,
                    weatherCanadaProcessor,
                    postProcessing,
                    new CycleReportRecorder(),
                    usageTracker);
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
