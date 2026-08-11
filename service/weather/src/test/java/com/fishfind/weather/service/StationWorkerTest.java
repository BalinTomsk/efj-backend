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
import com.fishfind.weather.repo.WeatherStationCoverageRepository;
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

    private static final long TWELVE_HOURS_MS = 12L * 60 * 60 * 1000;
    /** weather-gov daily limit is 900, so the derived gap is 12h/900 = 48s per station. */
    private static final long DERIVED_GAP_MS = TWELVE_HOURS_MS / 900;

    private WeatherStationRepository stationRepository;
    private StationProcessorOpen processor;
    private StationProcessorWeatherGov weatherGovProcessor;
    private StationProcessorVisualCrossing visualCrossingProcessor;
    private StationProcessorGoogleWeather googleWeatherProcessor;
    private StationProcessorWeatherCanada weatherCanadaProcessor;
    private StationProcessorWunderground wundergroundProcessor;
    private StationPostProcessingService postProcessing;
    private WeatherApiUsageTracker usageTracker;
    private WeatherStationCoverageRepository coverageRepository;

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
        wundergroundProcessor = Mockito.mock(StationProcessorWunderground.class);
        postProcessing = Mockito.mock(StationPostProcessingService.class);
        usageTracker = Mockito.mock(WeatherApiUsageTracker.class);
        coverageRepository = Mockito.mock(WeatherStationCoverageRepository.class);
        when(stationRepository.countSupportedStations(anyString())).thenReturn(THREE_STATIONS.size());
        when(stationRepository.findSupportedStations(anyString(), anyInt())).thenAnswer(invocation -> {
            int limit = invocation.getArgument(1);
            return THREE_STATIONS.subList(0, Math.min(limit, THREE_STATIONS.size()));
        });
        when(usageTracker.snapshot(anyString(), any(LocalDate.class), anyInt())).thenAnswer(invocation ->
                new WeatherApiUsageTracker.UsageSnapshot(0, invocation.getArgument(2), invocation.getArgument(2), true));
        when(usageTracker.tryConsume(anyString(), any(LocalDate.class), anyInt())).thenReturn(true);
        worker = new RecordingWorker();
        ReflectionTestUtils.setField(worker, "maxFailureRate", 0.5);
        ReflectionTestUtils.setField(worker, "weatherGovDailyLimit", 900);
        ReflectionTestUtils.setField(worker, "openMeteoDailyLimit", 10000);
        ReflectionTestUtils.setField(worker, "visualCrossingDailyLimit", 1000);
        ReflectionTestUtils.setField(worker, "googleWeatherDailyLimit", 161);
        ReflectionTestUtils.setField(worker, "weatherCanadaDailyLimit", 900);
        ReflectionTestUtils.setField(worker, "wundergroundDailyLimit", 450);
        // All metered providers now refuse to start without a key; the background-mode tests expect
        // all six workers, so give the fixture one.
        ReflectionTestUtils.setField(worker, "visualCrossingApiKey", "test-key");
        ReflectionTestUtils.setField(worker, "googleWeatherApiKey", "test-key");
        ReflectionTestUtils.setField(worker, "wundergroundApiKey", "test-key");
    }

    @Test
    void calculatesPerStationDelayWithinTimeBudget() {
        // An explicit TIMEOUT is used verbatim, floor or no floor.
        assertThat(StationWorker.calculateDelayMs(5, 1400)).isEqualTo(5000L);
        assertThat(StationWorker.calculateDelayMs(1, 1400)).isEqualTo(1000L);
        // Otherwise the daily allowance is spread over 12 hours.
        assertThat(StationWorker.calculateDelayMs(0, 1400)).isEqualTo(TWELVE_HOURS_MS / 1400);
        assertThat(StationWorker.calculateDelayMs(0, 900)).isEqualTo(DERIVED_GAP_MS);
        // A nonsensically large limit must not turn the cycle into a burst.
        assertThat(StationWorker.calculateDelayMs(0, 1_000_000)).isEqualTo(2000L);
        assertThat(StationWorker.calculateDelayMs(0, 0)).isEqualTo(2000L);
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
        assertThat(recordedSleeps.stream().mapToLong(Long::longValue).sum())
                .isEqualTo(THREE_STATIONS.size() * DERIVED_GAP_MS);
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
        // 898 of the day's 900 already spent, so only 2 stations may be loaded and charged.
        when(usageTracker.snapshot(eq("weather-gov"), any(LocalDate.class), anyInt()))
                .thenReturn(new WeatherApiUsageTracker.UsageSnapshot(898, 900, 2, true));
        when(usageTracker.tryConsume(eq("weather-gov"), any(LocalDate.class), anyInt())).thenReturn(true);
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
        when(usageTracker.snapshot(eq("weather-gov"), any(LocalDate.class), anyInt()))
                .thenReturn(new WeatherApiUsageTracker.UsageSnapshot(0, 900, 0, true));
        when(usageTracker.tryConsume(eq("weather-gov"), any(LocalDate.class), anyInt())).thenReturn(false);

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
        // A 2-hour explicit gap, so each station's wait crosses the hourly-summary boundary.
        ReflectionTestUtils.setField(worker, "weatherGovTimeoutSeconds", 7200);
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
                weatherCanadaProcessor, wundergroundProcessor, postProcessing);
    }

    @Test
    void backgroundModeStartsWeatherGovUsOpenMeteoCaVisualCrossingUsGoogleWeatherUsWeatherCanadaCaAndWundergroundUsWorkers() {
        when(stationRepository.countSupportedStations(anyString())).thenReturn(0);
        StationWorker backgroundWorker = new StationWorker(
                stationRepository,
                processor,
                weatherGovProcessor,
                visualCrossingProcessor,
                googleWeatherProcessor,
                weatherCanadaProcessor,
                wundergroundProcessor,
                postProcessing,
                new CycleReportRecorder(),
                usageTracker,
                coverageRepository);
        ReflectionTestUtils.setField(backgroundWorker, "visualCrossingApiKey", "test-key");
        ReflectionTestUtils.setField(backgroundWorker, "googleWeatherApiKey", "test-key");
        ReflectionTestUtils.setField(backgroundWorker, "wundergroundApiKey", "test-key");
        ReflectionTestUtils.setField(backgroundWorker, "maxFailureRate", 0.5);
        ReflectionTestUtils.setField(backgroundWorker, "weatherGovDailyLimit", 900);
        ReflectionTestUtils.setField(backgroundWorker, "openMeteoDailyLimit", 10000);
        ReflectionTestUtils.setField(backgroundWorker, "visualCrossingDailyLimit", 1000);
        ReflectionTestUtils.setField(backgroundWorker, "googleWeatherDailyLimit", 161);
        ReflectionTestUtils.setField(backgroundWorker, "weatherCanadaDailyLimit", 900);
        ReflectionTestUtils.setField(backgroundWorker, "wundergroundDailyLimit", 450);

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
                        "weather-data-worker-weather-canada-ca",
                        "weather-data-worker-wunderground-us");

        verify(usageTracker, timeout(5000)).snapshot(eq("google-weather"), any(LocalDate.class), eq(161));
        verify(usageTracker, timeout(5000)).snapshot(eq("weather-canada"), any(LocalDate.class), eq(900));
        verify(usageTracker, timeout(5000)).snapshot(eq("wunderground"), any(LocalDate.class), eq(450));

        backgroundWorker.shutdown();
    }

    @Test
    void backgroundModeRunsStartupVerificationForEveryProviderWhenEnabled() {
        when(stationRepository.countSupportedStations(anyString())).thenReturn(0);
        when(weatherGovProcessor.verifyStartup(any(), eq("US"))).thenReturn(ProcessingOutcome.PROCESSED);
        when(processor.verifyStartup(any(), eq("CA"))).thenReturn(ProcessingOutcome.PROCESSED);
        when(visualCrossingProcessor.verifyStartup(any(), eq("US"))).thenReturn(ProcessingOutcome.PROCESSED);
        when(googleWeatherProcessor.verifyStartup(any(), eq("US"))).thenReturn(ProcessingOutcome.PROCESSED);
        when(weatherCanadaProcessor.verifyStartup(any(), eq("CA"))).thenReturn(ProcessingOutcome.PROCESSED);
        when(wundergroundProcessor.verifyStartup(any(), eq("US"))).thenReturn(ProcessingOutcome.PROCESSED);
        StationWorker backgroundWorker = new StationWorker(
                stationRepository,
                processor,
                weatherGovProcessor,
                visualCrossingProcessor,
                googleWeatherProcessor,
                weatherCanadaProcessor,
                wundergroundProcessor,
                postProcessing,
                new CycleReportRecorder(),
                usageTracker,
                coverageRepository);
        ReflectionTestUtils.setField(backgroundWorker, "visualCrossingApiKey", "test-key");
        ReflectionTestUtils.setField(backgroundWorker, "googleWeatherApiKey", "test-key");
        ReflectionTestUtils.setField(backgroundWorker, "wundergroundApiKey", "test-key");
        ReflectionTestUtils.setField(backgroundWorker, "startupVerificationEnabled", true);
        ReflectionTestUtils.setField(backgroundWorker, "maxFailureRate", 0.5);
        ReflectionTestUtils.setField(backgroundWorker, "weatherGovDailyLimit", 900);
        ReflectionTestUtils.setField(backgroundWorker, "openMeteoDailyLimit", 10000);
        ReflectionTestUtils.setField(backgroundWorker, "visualCrossingDailyLimit", 1000);
        ReflectionTestUtils.setField(backgroundWorker, "googleWeatherDailyLimit", 161);
        ReflectionTestUtils.setField(backgroundWorker, "weatherCanadaDailyLimit", 900);
        ReflectionTestUtils.setField(backgroundWorker, "wundergroundDailyLimit", 450);

        backgroundWorker.run(new DefaultApplicationArguments());

        verify(weatherGovProcessor, timeout(5000)).verifyStartup(any(), eq("US"));
        verify(processor, timeout(5000)).verifyStartup(any(), eq("CA"));
        verify(visualCrossingProcessor, timeout(5000)).verifyStartup(any(), eq("US"));
        verify(googleWeatherProcessor, timeout(5000)).verifyStartup(any(), eq("US"));
        verify(weatherCanadaProcessor, timeout(5000)).verifyStartup(any(), eq("CA"));
        verify(wundergroundProcessor, timeout(5000)).verifyStartup(any(), eq("US"));

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
                    wundergroundProcessor,
                    postProcessing,
                    new CycleReportRecorder(),
                    usageTracker,
                coverageRepository);
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
