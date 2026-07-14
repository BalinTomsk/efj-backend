package com.fishfind.weather.service;

import com.fishfind.weather.domain.StationRef;
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
 * Runs the Open-Meteo weather-processing loop.
 */
@Component
public class StationWorker implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(StationWorker.class);
    private static final long MIN_DELAY_BETWEEN_STATIONS_MS = 2000L;
    private static final long SUMMARY_LOG_INTERVAL_MS = Duration.ofHours(1).toMillis();
    private static final Duration TIME_BUDGET = Duration.ofHours(8);
    private static final long SHUTDOWN_JOIN_MS = 25_000L;
    private static final String DEFAULT_COUNTRY = "US";
    private static final List<String> COUNTRIES = List.of("US", "CA");

    private final WeatherStationRepository stationRepository;
    private final StationProcessorOpen stationProcessorOpen;
    private final StationPostProcessingService postProcessingService;
    private final CycleReportRecorder cycleReportRecorder;

    @Value("${weather.worker.post-processing.max-failure-rate:0.5}")
    private double maxFailureRate;

    private volatile boolean running = true;
    private final List<Thread> workerThreads = new ArrayList<>();

    public StationWorker(WeatherStationRepository stationRepository,
                         StationProcessorOpen stationProcessorOpen,
                         StationPostProcessingService postProcessingService,
                         CycleReportRecorder cycleReportRecorder) {
        this.stationRepository = stationRepository;
        this.stationProcessorOpen = stationProcessorOpen;
        this.postProcessingService = postProcessingService;
        this.cycleReportRecorder = cycleReportRecorder;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (args.containsOption("console")) {
            return;
        }

        for (String country : COUNTRIES) {
            Thread thread = new Thread(() -> loop(country), "weather-data-worker-open-" + country.toLowerCase());
            thread.setDaemon(false);
            workerThreads.add(thread);
            thread.start();
            log.info("Started background weather worker thread. country={} thread={}", country, thread.getName());
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
        CountryPassSummary summary = runCycle(country, requestedMli);
        return new RunResult(summary.successfulStations(), summary.failedStations());
    }

    private CountryPassSummary runCycle(String country, String requestedMli) throws InterruptedException {
        List<StationRef> stations = stationRepository.findSupportedStations(country);
        log.info("Loaded supported stations. country={} count={} requestedStation={}",
                country,
                stations.size(),
                requestedMli == null || requestedMli.isBlank() ? "<all>" : requestedMli);

        long targetDelayMs = calculateDelayMs(stations.size());
        log.info("Weather worker time budget. country={} budgetHours={} delayPerStationMs={}",
                country,
                TIME_BUDGET.toHours(),
                targetDelayMs);

        int processed = 0;
        int skipped = 0;
        int failed = 0;
        String lastProcessedStation = null;
        String lastFailedStation = null;
        long nextSummaryLogAt = currentTimeMillis() + SUMMARY_LOG_INTERVAL_MS;
        boolean stoppedEarly = false;

        for (StationRef station : stations) {
            if (!running || Thread.currentThread().isInterrupted()) {
                stoppedEarly = true;
                break;
            }
            if (requestedMli != null && !requestedMli.isBlank() && !station.mli().equalsIgnoreCase(requestedMli)) {
                continue;
            }

            long startedAt = currentTimeMillis();
            switch (stationProcessorOpen.process(station, country)) {
                case PROCESSED -> {
                    processed++;
                    lastProcessedStation = station.mli();
                }
                case SKIPPED -> skipped++;
                case FAILED -> {
                    failed++;
                    lastFailedStation = station.mli();
                }
            }

            long remainingDelayMs = targetDelayMs - (currentTimeMillis() - startedAt);
            CountryPassSummary progressSummary = new CountryPassSummary(
                    country, processed, skipped, failed, lastProcessedStation, lastFailedStation);
            nextSummaryLogAt = sleepUntilNextStationWithHourlySummaries(remainingDelayMs, nextSummaryLogAt,
                    progressSummary);
        }

        CountryPassSummary summary = new CountryPassSummary(
                country, processed, skipped, failed, lastProcessedStation, lastFailedStation);
        logCountryPassSummary(summary);

        if (stoppedEarly) {
            log.info("Worker stopped before cycle completion; skipping post-processing. "
                    + "processed={} skipped={} failed={}", processed, skipped, failed);
            return summary;
        }

        maybeRunPostProcessing(summary);
        return summary;
    }

    private void logCountryPassSummary(CountryPassSummary summary) {
        log.info("Country pass completed. country={} successfulStations={} failedStations={} "
                        + "lastProcessedStation={} lastFailedStation={}",
                summary.country(),
                summary.successfulStations(),
                summary.failedStations(),
                logStation(summary.lastProcessedStation()),
                logStation(summary.lastFailedStation()));
    }

    private void logCountryPassProgress(CountryPassSummary summary) {
        log.info("Country pass hourly progress. country={} successfulStations={} failedStations={} "
                        + "lastProcessedStation={} lastFailedStation={}",
                summary.country(),
                summary.successfulStations(),
                summary.failedStations(),
                logStation(summary.lastProcessedStation()),
                logStation(summary.lastFailedStation()));
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
        postProcessingService.runAfterStationProcessing();
    }

    private void loop(String country) {
        while (running && !Thread.currentThread().isInterrupted()) {
            try {
                CountryPassSummary summary = runCycle(country, null);
                cycleReportRecorder.record(new CycleReportEntry(
                        LocalDate.now(),
                        summary.successfulStations(),
                        summary.failedStations(),
                        summary.lastProcessedStation(),
                        summary.lastFailedStation()));
                long sleepMs = millisUntilNextMidnight();
                ZonedDateTime nextRunAt = ZonedDateTime.now().plus(Duration.ofMillis(sleepMs));
                log.info("Worker cycle completed. country={} successfulStations={} failedStations={} "
                                + "lastProcessedStation={} lastFailedStation={} "
                                + "nextRunAt={} sleepMs={}",
                        country,
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
                log.error("Weather worker loop failed. country={}", country, ex);
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

    long calculateDelayMs(int stationCount) {
        if (stationCount <= 1) {
            return MIN_DELAY_BETWEEN_STATIONS_MS;
        }

        long delayMs = TIME_BUDGET.toMillis() / stationCount;
        return Math.max(delayMs, MIN_DELAY_BETWEEN_STATIONS_MS);
    }

    long millisUntilNextMidnight() {
        ZonedDateTime now = ZonedDateTime.now();
        ZonedDateTime nextMidnight = LocalDate.now(ZoneId.systemDefault())
                .plusDays(1)
                .atStartOfDay(ZoneId.systemDefault());
        return Math.max(0L, Duration.between(now, nextMidnight).toMillis());
    }

    private record CountryPassSummary(
            String country,
            int successfulStations,
            int skippedStations,
            int failedStations,
            String lastProcessedStation,
            String lastFailedStation) {
    }
}
