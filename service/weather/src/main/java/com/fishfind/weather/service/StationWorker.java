package com.fishfind.weather.service;

import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.WeatherStationCoverageRepository;
import com.fishfind.weather.repo.WeatherStationRepository;
import jakarta.annotation.PreDestroy;
import java.time.Duration;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

/**
 * Runs the weather-processing loop.
 */
@Component
public class StationWorker implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(StationWorker.class);
    private static final long MIN_DELAY_BETWEEN_STATIONS_MS = 2000L;
    private static final long SUMMARY_LOG_INTERVAL_MS = Duration.ofHours(1).toMillis();
    private static final Duration TIME_BUDGET = Duration.ofHours(8);
    private static final Duration CYCLE_FAILURE_COOLDOWN = Duration.ofMinutes(1);
    /** Window a provider's whole daily allowance is spread across when no TIMEOUT is set. */
    private static final Duration DERIVED_PACING_WINDOW = Duration.ofHours(12);
    private static final long SHUTDOWN_JOIN_MS = 25_000L;
    private static final String DEFAULT_COUNTRY = "US";
    private static final WorkerDefinition WEATHER_GOV_US = new WorkerDefinition(
            "weather-gov", "Weather.gov", "US",
            new StationRef("KNYC", 40.7128, -74.0060, "NY"));
    private static final WorkerDefinition OPEN_METEO_CA = new WorkerDefinition(
            "open", "Open-Meteo", "CA",
            new StationRef("STARTUP-OPEN-CA", 43.6532, -79.3832, "ON"));
    private static final WorkerDefinition VISUAL_CROSSING_US = new WorkerDefinition(
            "visual-crossing", "Visual Crossing", "US",
            new StationRef("STARTUP-VISUAL-US", 48.3060, -120.6543, "WA"));
    private static final WorkerDefinition GOOGLE_WEATHER_US = new WorkerDefinition(
            "google-weather", "Google Weather", "US",
            new StationRef("STARTUP-GOOGLE-US", 48.3060, -120.6543, "WA"));
    private static final WorkerDefinition WEATHER_CANADA_CA = new WorkerDefinition(
            "weather-canada", "Weather Canada", "CA",
            new StationRef("STARTUP-WEATHER-CANADA-CA", 43.6532, -79.3832, "ON"));
    private static final List<WorkerDefinition> WORKERS = List.of(
            WEATHER_GOV_US, OPEN_METEO_CA, VISUAL_CROSSING_US, GOOGLE_WEATHER_US, WEATHER_CANADA_CA);

    private final WeatherStationRepository stationRepository;
    private final StationProcessorOpen stationProcessorOpen;
    private final StationProcessorWeatherGov stationProcessorWeatherGov;
    private final StationProcessorVisualCrossing stationProcessorVisualCrossing;
    private final StationProcessorGoogleWeather stationProcessorGoogleWeather;
    private final StationProcessorWeatherCanada stationProcessorWeatherCanada;
    private final StationPostProcessingService postProcessingService;
    private final CycleReportRecorder cycleReportRecorder;
    private final WeatherApiUsageTracker usageTracker;
    private final WeatherStationCoverageRepository coverageRepository;

    @Value("${weather.worker.post-processing.max-failure-rate:0.5}")
    private double maxFailureRate;

    @Value("${weather.worker.daily-limit.weather-gov:900}")
    private int weatherGovDailyLimit;

    @Value("${weather.worker.daily-limit.open-meteo:10000}")
    private int openMeteoDailyLimit;

    @Value("${weather.worker.daily-limit.visual-crossing:1000}")
    private int visualCrossingDailyLimit;

    @Value("${weather.worker.daily-limit.google-weather:161}")
    private int googleWeatherDailyLimit;

    @Value("${weather.worker.daily-limit.weather-canada:900}")
    private int weatherCanadaDailyLimit;

    @Value("${weather.worker.startup-verification.enabled:true}")
    private boolean startupVerificationEnabled;

    @Value("${weather.worker.enable.weather-gov:true}")
    private boolean weatherGovEnabled = true;

    @Value("${weather.worker.enable.open-meteo:true}")
    private boolean openMeteoEnabled = true;

    @Value("${weather.worker.enable.visual-crossing:true}")
    private boolean visualCrossingEnabled = true;

    @Value("${weather.worker.enable.google-weather:true}")
    private boolean googleWeatherEnabled = true;

    @Value("${weather.worker.enable.weather-canada:true}")
    private boolean weatherCanadaEnabled = true;

    @Value("${weather.worker.timeout.weather-gov:0}")
    private int weatherGovTimeoutSeconds;

    @Value("${weather.worker.timeout.open-meteo:0}")
    private int openMeteoTimeoutSeconds;

    @Value("${weather.worker.timeout.visual-crossing:0}")
    private int visualCrossingTimeoutSeconds;

    @Value("${weather.worker.timeout.google-weather:0}")
    private int googleWeatherTimeoutSeconds;

    @Value("${weather.worker.timeout.weather-canada:0}")
    private int weatherCanadaTimeoutSeconds;

    @Value("${weather.worker.visual-crossing-api-key:${VISUAL_CROSSING_API_KEY:}}")
    private String visualCrossingApiKey;

    @Value("${weather.worker.google-weather-api-key:${GOOGLE_WEATHER_API_KEY:}}")
    private String googleWeatherApiKey;

    private volatile boolean running = true;
    private final List<Thread> workerThreads = new ArrayList<>();

    public StationWorker(WeatherStationRepository stationRepository,
                         StationProcessorOpen stationProcessorOpen,
                         StationProcessorWeatherGov stationProcessorWeatherGov,
                         StationProcessorVisualCrossing stationProcessorVisualCrossing,
                         StationProcessorGoogleWeather stationProcessorGoogleWeather,
                         StationProcessorWeatherCanada stationProcessorWeatherCanada,
                         StationPostProcessingService postProcessingService,
                         CycleReportRecorder cycleReportRecorder,
                         WeatherApiUsageTracker usageTracker,
                         WeatherStationCoverageRepository coverageRepository) {
        this.stationRepository = stationRepository;
        this.stationProcessorOpen = stationProcessorOpen;
        this.stationProcessorWeatherGov = stationProcessorWeatherGov;
        this.stationProcessorVisualCrossing = stationProcessorVisualCrossing;
        this.stationProcessorGoogleWeather = stationProcessorGoogleWeather;
        this.stationProcessorWeatherCanada = stationProcessorWeatherCanada;
        this.postProcessingService = postProcessingService;
        this.cycleReportRecorder = cycleReportRecorder;
        this.usageTracker = usageTracker;
        this.coverageRepository = coverageRepository;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (args.containsOption("console")) {
            return;
        }

        for (WorkerDefinition worker : WORKERS) {
            String disabledReason = workerDisabledReason(worker.provider());
            if (disabledReason != null) {
                log.warn("Weather worker not started. provider={} country={} reason={}",
                        worker.reportName(), worker.country(), disabledReason);
                continue;
            }

            Thread thread = new Thread(() -> runStartupVerificationThenLoop(worker), workerThreadName(worker));
            thread.setDaemon(false);
            workerThreads.add(thread);
            thread.start();
            log.info("Started background weather worker thread. provider={} country={} thread={}",
                    worker.reportName(), worker.country(), thread.getName());
        }
    }

    /** Stops the worker loop and waits (bounded) for the thread to unwind on context shutdown. */
    @PreDestroy
    void shutdown() {
        running = false;
        if (workerThreads.isEmpty()) {
            return;
        }
        for (Thread thread : workerThreads) {
            log.info("Stopping weather worker thread. thread={}", thread.getName());
            thread.interrupt();
        }
        for (Thread thread : workerThreads) {
            try {
                thread.join(SHUTDOWN_JOIN_MS);
            } catch (InterruptedException ex) {
                Thread.currentThread().interrupt();
                return;
            }
        }
    }

    /** Outcome of a single {@code --console} pass, used to pick the process exit code. */
    public record RunResult(int processedStations, int failedStations) {
    }

    public RunResult runOnce(String requestedMli) throws InterruptedException {
        return runOnce(DEFAULT_COUNTRY, requestedMli);
    }

    public RunResult runOnce(String country, String requestedMli) throws InterruptedException {
        CountryPassSummary summary = runCycle(workerForCountry(country), requestedMli);
        return new RunResult(summary.successfulStations(), summary.failedStations());
    }

    private CountryPassSummary runCycle(WorkerDefinition worker, String requestedMli) throws InterruptedException {
        String country = worker.country();
        int totalSupportedStations = stationRepository.countSupportedStations(country);
        int dailyLimit = dailyLimitFor(worker);
        int requestedStations = requestedMli == null || requestedMli.isBlank()
                ? Math.min(totalSupportedStations, dailyLimit)
                : Math.min(1, totalSupportedStations);
        LocalDate today = LocalDate.now();
        WeatherApiUsageTracker.UsageSnapshot budget = usageTracker.snapshot(worker.provider(), today, dailyLimit);

        // Budget is NOT booked here — each station is charged individually just before it is fetched,
        // so an interrupted cycle costs only what it actually used. This is only the page size.
        int stationLimit = requestedMli == null || requestedMli.isBlank()
                ? budget.remaining()
                : (budget.remaining() > 0 ? Math.min(totalSupportedStations, dailyLimit) : 0);

        log.info("Weather API daily budget. provider={} country={} totalSupportedStations={} "
                        + "dailyLimit={} usedToday={} requestedForCycle={} remainingToday={} persisted={}",
                worker.reportName(),
                country,
                totalSupportedStations,
                budget.dailyLimit(),
                budget.usedToday(),
                requestedStations,
                budget.remaining(),
                budget.persisted());

        List<StationRef> stations = stationLimit > 0
                ? stationRepository.findSupportedStations(country, stationLimit)
                : List.of();
        log.info("Loaded supported stations. provider={} country={} count={} requestedStation={}",
                worker.reportName(),
                country,
                stations.size(),
                requestedMli == null || requestedMli.isBlank() ? "<all>" : requestedMli);

        int timeoutSeconds = timeoutSecondsFor(worker);
        long targetDelayMs = calculateDelayMs(timeoutSeconds, dailyLimit);
        log.info("Weather worker pacing. provider={} country={} delayPerStationMs={} source={}",
                worker.reportName(),
                country,
                targetDelayMs,
                timeoutSeconds > 0 ? "TIMEOUT" : "dailyLimit/" + DERIVED_PACING_WINDOW.toHours() + "h");

        int processed = 0;
        int skipped = 0;
        int failed = 0;
        String lastProcessedStation = null;
        String lastFailedStation = null;
        long nextSummaryLogAt = currentTimeMillis() + SUMMARY_LOG_INTERVAL_MS;
        boolean stoppedEarly = false;
        boolean budgetExhausted = false;

        for (StationRef station : stations) {
            if (!running || Thread.currentThread().isInterrupted()) {
                stoppedEarly = true;
                break;
            }
            if (requestedMli != null && !requestedMli.isBlank() && !station.mli().equalsIgnoreCase(requestedMli)) {
                continue;
            }

            // Charge this one station before fetching it. A restart therefore forfeits at most the
            // station in flight, not the rest of the day's allowance.
            if (!usageTracker.tryConsume(worker.provider(), today, dailyLimit)) {
                budgetExhausted = true;
                break;
            }

            long startedAt = currentTimeMillis();
            ProcessingOutcome outcome = processorFor(worker).process(station, country);
            recordCoverage(worker, station, outcome);
            switch (outcome) {
                case PROCESSED -> {
                    processed++;
                    lastProcessedStation = station.mli();
                }
                case SKIPPED -> skipped++;
                case FAILED, FAILED_HTTP_503 -> {
                    failed++;
                    lastFailedStation = station.mli();
                }
            }

            long remainingDelayMs = targetDelayMs - (currentTimeMillis() - startedAt);
            CountryPassSummary progressSummary = new CountryPassSummary(
                    worker.reportName(), country, processed, skipped, failed, lastProcessedStation, lastFailedStation);
            nextSummaryLogAt = sleepUntilNextStationWithHourlySummaries(remainingDelayMs, nextSummaryLogAt,
                    progressSummary);
        }

        CountryPassSummary summary = new CountryPassSummary(
                worker.reportName(), country, processed, skipped, failed, lastProcessedStation, lastFailedStation);
        logCountryPassSummary(summary);

        if (budgetExhausted) {
            // A normal end to the day's work, not a fault: the allowance ran out mid-pass. The stations
            // that did run are sound, so post-processing still applies.
            log.info("Daily API allowance spent; ending cycle. provider={} country={} processed={}",
                    worker.reportName(), country, processed);
        }

        if (stoppedEarly) {
            log.info("Worker stopped before cycle completion; skipping post-processing. "
                    + "processed={} skipped={} failed={}", processed, skipped, failed);
            return summary;
        }

        maybeRunPostProcessing(summary);
        return summary;
    }

    /**
     * Flags whether this provider could serve this gauge, so {@code fn_weather_uncovered_stations} can
     * hand the gaps to a fallback worker.
     *
     * <p>Only PROCESSED and SKIPPED are coverage facts. A failure is transient — a timeout or a 503
     * says nothing about whether the provider covers the point, and recording it would send a
     * perfectly-served gauge to the fallback worker on the strength of one bad night.
     *
     * <p>Never allowed to fail the station: the flag is an optimisation, and the payload for this
     * cycle is already saved by the time we get here.
     */
    private void recordCoverage(WorkerDefinition worker, StationRef station, ProcessingOutcome outcome) {
        if (outcome != ProcessingOutcome.PROCESSED && outcome != ProcessingOutcome.SKIPPED) {
            return;
        }
        try {
            coverageRepository.save(station.mli(), worker.provider(), outcome == ProcessingOutcome.PROCESSED);
        } catch (RuntimeException ex) {
            log.warn("Could not record provider coverage. provider={} station={}",
                    worker.reportName(), station.mli(), ex);
        }
    }

    private void runStartupVerificationThenLoop(WorkerDefinition worker) {
        runStartupVerification(worker);
        loop(worker);
    }

    private void runStartupVerification(WorkerDefinition worker) {
        if (!startupVerificationEnabled || !running || Thread.currentThread().isInterrupted()) {
            return;
        }

        StationRef station = worker.startupStation();
        long startedAt = currentTimeMillis();
        log.info("Startup weather worker verification started. provider={} country={} station={} state={}",
                worker.reportName(), worker.country(), station.mli(), station.state());
        ProcessingOutcome outcome = processorFor(worker).verifyStartup(station, worker.country());
        long elapsedMs = Math.max(0L, currentTimeMillis() - startedAt);
        if (outcome == ProcessingOutcome.PROCESSED) {
            log.info("Startup weather worker verification succeeded. provider={} country={} station={} state={} "
                            + "outcome={} elapsedMs={}",
                    worker.reportName(), worker.country(), station.mli(), station.state(), outcome, elapsedMs);
            return;
        }

        log.error("Startup weather worker verification failed. provider={} country={} station={} state={} "
                        + "outcome={} elapsedMs={}",
                worker.reportName(), worker.country(), station.mli(), station.state(), outcome, elapsedMs);
    }

    private void logCountryPassSummary(CountryPassSummary summary) {
        log.info("Country pass completed. country={} successfulStations={} failedStations={} "
                        + "lastProcessedStation={} lastFailedStation={} provider={}",
                summary.country(),
                summary.successfulStations(),
                summary.failedStations(),
                logStation(summary.lastProcessedStation()),
                logStation(summary.lastFailedStation()),
                summary.provider());
    }

    private void logCountryPassProgress(CountryPassSummary summary) {
        log.info("Country pass hourly progress. country={} successfulStations={} failedStations={} "
                        + "lastProcessedStation={} lastFailedStation={} provider={}",
                summary.country(),
                summary.successfulStations(),
                summary.failedStations(),
                logStation(summary.lastProcessedStation()),
                logStation(summary.lastFailedStation()),
                summary.provider());
    }

    private long sleepUntilNextStationWithHourlySummaries(long remainingDelayMs,
                                                          long nextSummaryLogAt,
                                                          CountryPassSummary summary)
            throws InterruptedException {
        long delayLeftMs = Math.max(0L, remainingDelayMs);
        while (delayLeftMs > 0 || currentTimeMillis() >= nextSummaryLogAt) {
            long now = currentTimeMillis();
            long sleepMs = Math.min(delayLeftMs, Math.max(0L, nextSummaryLogAt - now));
            if (sleepMs > 0) {
                sleep(sleepMs);
                delayLeftMs -= sleepMs;
            }

            if (currentTimeMillis() >= nextSummaryLogAt) {
                logCountryPassProgress(summary);
                do {
                    nextSummaryLogAt += SUMMARY_LOG_INTERVAL_MS;
                } while (currentTimeMillis() >= nextSummaryLogAt);
            }
        }

        return nextSummaryLogAt;
    }

    private String logStation(String station) {
        return station == null || station.isBlank() ? "<none>" : station;
    }

    /**
     * Runs post-processing only when the cycle was healthy. A high failure rate (e.g. an open
     * circuit or mass SQL failures) is a cycle-level problem: skip post-processing so probabilities
     * are not recomputed from partial data, and log an error for alerting. Skipped stations
     * (no published feed) are normal and never block post-processing.
     */
    private void maybeRunPostProcessing(CountryPassSummary summary) {
        int processed = summary.successfulStations();
        int skipped = summary.skippedStations();
        int failed = summary.failedStations();
        int attempted = processed + failed;
        double failureRate = attempted == 0 ? 0.0 : (double) failed / attempted;

        if (attempted > 0 && failureRate > maxFailureRate) {
            log.error("Cycle degraded; skipping post-processing. country={} processed={} skipped={} "
                    + "failed={} failureRate={} threshold={}",
                    summary.country(), processed, skipped, failed,
                    String.format("%.2f", failureRate), maxFailureRate);
            return;
        }

        log.info("Cycle healthy; running post-processing. country={} processed={} skipped={} failed={}",
                summary.country(), processed, skipped, failed);
        try {
            postProcessingService.runAfterStationProcessing();
        } catch (RuntimeException ex) {
            log.error("Post-processing failed after healthy cycle. country={} processed={} skipped={} failed={}",
                    summary.country(), processed, skipped, failed, ex);
        }
    }

    private void loop(WorkerDefinition worker) {
        while (running && !Thread.currentThread().isInterrupted()) {
            try {
                CountryPassSummary summary = runCycle(worker, null);
                cycleReportRecorder.record(new CycleReportEntry(
                        LocalDate.now(),
                        worker.reportName(),
                        worker.country(),
                        summary.successfulStations(),
                        summary.failedStations(),
                        summary.lastProcessedStation(),
                        summary.lastFailedStation()));
                long sleepMs = millisUntilNextMidnight();
                ZonedDateTime nextRunAt = ZonedDateTime.now().plus(Duration.ofMillis(sleepMs));
                log.info("Worker cycle completed. provider={} country={} successfulStations={} failedStations={} "
                                + "lastProcessedStation={} lastFailedStation={} "
                                + "nextRunAt={} sleepMs={}",
                        worker.reportName(),
                        worker.country(),
                        summary.successfulStations(),
                        summary.failedStations(),
                        logStation(summary.lastProcessedStation()),
                        logStation(summary.lastFailedStation()),
                        nextRunAt,
                        sleepMs);

                if (sleepMs <= 0) {
                    continue;
                }

                sleep(sleepMs);
            } catch (InterruptedException ex) {
                Thread.currentThread().interrupt();
                log.info("Weather worker interrupted. thread={}", Thread.currentThread().getName());
                return;
            } catch (Exception ex) {
                // One bad cycle must not kill the loop. DELIBERATE COOLDOWN: every failure here happens
                // before the first station (the station COUNT query), so with the database down there is
                // nothing to slow the loop — it would spin at thousands of iterations a second across
                // five workers, pinning a core and burying the log.
                log.error("Weather worker loop failed. provider={} country={} retryInSeconds={}",
                        worker.reportName(), worker.country(), CYCLE_FAILURE_COOLDOWN.toSeconds(), ex);
                try {
                    sleep(CYCLE_FAILURE_COOLDOWN.toMillis());
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    return;
                }
            }
        }
        log.info("Weather worker loop exited. thread={}", Thread.currentThread().getName());
    }

    /** Pause between stations / between cycles. Overridable so tests can run without real waits. */
    protected void sleep(long ms) throws InterruptedException {
        Thread.sleep(ms);
    }

    protected long currentTimeMillis() {
        return System.currentTimeMillis();
    }

    /**
     * Explains why a provider's worker must not start, or {@code null} when it is good to go. The
     * text is logged verbatim, so it names the environment variable an operator has to change.
     *
     * <p>Two independent reasons, checked in this order: the operator turned it off
     * ({@code <PROVIDER>_ENABLE=false}), or a metered provider has no API key. The toggle is checked
     * first so a deliberately disabled provider does not also nag about a key it will never use.
     * Starting a keyed worker without its key would fail EVERY station it touched, pushing the
     * cycle's failure rate past the threshold and suppressing post-processing for a country whose
     * other providers were perfectly healthy.
     */
    String workerDisabledReason(String provider) {
        return switch (provider) {
            case "weather-gov" -> weatherGovEnabled ? null : "WEATHER_GOV_ENABLE is false";
            case "open" -> openMeteoEnabled ? null : "OPEN_METEO_ENABLE is false";
            case "weather-canada" -> weatherCanadaEnabled ? null : "WEATHER_CANADA_ENABLE is false";
            case "visual-crossing" -> {
                if (!visualCrossingEnabled) {
                    yield "VISUAL_CROSSING_ENABLE is false";
                }
                yield isBlank(visualCrossingApiKey) ? "VISUAL_CROSSING_API_KEY is not configured" : null;
            }
            case "google-weather" -> {
                if (!googleWeatherEnabled) {
                    yield "GOOGLE_WEATHER_ENABLE is false";
                }
                yield isBlank(googleWeatherApiKey) ? "GOOGLE_WEATHER_API_KEY is not configured" : null;
            }
            default -> null;
        };
    }

    private static boolean isBlank(String value) {
        return value == null || value.isBlank();
    }

    /** Configured seconds between calls to this provider; 0 means derive from the daily limit. */
    private int timeoutSecondsFor(WorkerDefinition worker) {
        return switch (worker.provider()) {
            case "weather-gov" -> weatherGovTimeoutSeconds;
            case "visual-crossing" -> visualCrossingTimeoutSeconds;
            case "google-weather" -> googleWeatherTimeoutSeconds;
            case "weather-canada" -> weatherCanadaTimeoutSeconds;
            default -> openMeteoTimeoutSeconds;
        };
    }

    /**
     * Seconds between calls to one provider, in milliseconds.
     *
     * <p>An explicit {@code <PROVIDER>_TIMEOUT} is honoured verbatim. Otherwise it is derived by
     * spreading the provider's daily allowance over {@link #DERIVED_PACING_WINDOW}, floored at
     * {@link #MIN_DELAY_BETWEEN_STATIONS_MS} so a nonsensically large limit cannot burst.
     *
     * <p>Keying this to the provider's own quota rather than the day's station count (the previous
     * behaviour: an 8-hour budget divided by however many stations happened to load) makes the
     * request rate predictable per provider and independent of the day's station count.
     */
    static long calculateDelayMs(int timeoutSeconds, int dailyLimit) {
        if (timeoutSeconds > 0) {
            return timeoutSeconds * 1000L;
        }
        if (dailyLimit <= 0) {
            return MIN_DELAY_BETWEEN_STATIONS_MS;
        }
        return Math.max(DERIVED_PACING_WINDOW.toMillis() / dailyLimit, MIN_DELAY_BETWEEN_STATIONS_MS);
    }

    long millisUntilNextMidnight() {
        ZonedDateTime now = ZonedDateTime.now();
        ZonedDateTime nextMidnight = LocalDate.now(ZoneId.systemDefault())
                .plusDays(1)
                .atStartOfDay(ZoneId.systemDefault());
        return Math.max(0L, Duration.between(now, nextMidnight).toMillis());
    }

    private WorkerDefinition workerForCountry(String country) {
        return "US".equalsIgnoreCase(country) ? WEATHER_GOV_US : OPEN_METEO_CA;
    }

    private StationProcessorBase processorFor(WorkerDefinition worker) {
        return switch (worker.provider()) {
            case "weather-gov" -> stationProcessorWeatherGov;
            case "visual-crossing" -> stationProcessorVisualCrossing;
            case "google-weather" -> stationProcessorGoogleWeather;
            case "weather-canada" -> stationProcessorWeatherCanada;
            default -> stationProcessorOpen;
        };
    }

    private int dailyLimitFor(WorkerDefinition worker) {
        return switch (worker.provider()) {
            case "weather-gov" -> weatherGovDailyLimit;
            case "visual-crossing" -> visualCrossingDailyLimit;
            case "google-weather" -> googleWeatherDailyLimit;
            case "weather-canada" -> weatherCanadaDailyLimit;
            default -> openMeteoDailyLimit;
        };
    }

    private String workerThreadName(WorkerDefinition worker) {
        return "weather-data-worker-" + worker.provider() + "-" + worker.country().toLowerCase();
    }

    private record CountryPassSummary(
            String provider,
            String country,
            int successfulStations,
            int skippedStations,
            int failedStations,
            String lastProcessedStation,
            String lastFailedStation) {
    }

    private record WorkerDefinition(String provider, String reportName, String country, StationRef startupStation) {
    }
}
