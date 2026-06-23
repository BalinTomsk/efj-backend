package com.fishfind.weather.service;

import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.WeatherStationRepository;
import jakarta.annotation.PreDestroy;
import java.time.Duration;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZonedDateTime;
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
    private static final Duration TIME_BUDGET = Duration.ofHours(8);
    private static final long SHUTDOWN_JOIN_MS = 25_000L;
    private static final String COUNTRY = "US";

    private final WeatherStationRepository stationRepository;
    private final StationProcessorOpen stationProcessorOpen;
    private final StationPostProcessingService postProcessingService;

    @Value("${weather.worker.post-processing.max-failure-rate:0.5}")
    private double maxFailureRate;

    private volatile boolean running = true;
    private volatile Thread workerThread;

    public StationWorker(WeatherStationRepository stationRepository,
                         StationProcessorOpen stationProcessorOpen,
                         StationPostProcessingService postProcessingService) {
        this.stationRepository = stationRepository;
        this.stationProcessorOpen = stationProcessorOpen;
        this.postProcessingService = postProcessingService;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (args.containsOption("console")) {
            return;
        }

        Thread thread = new Thread(this::loop, "weather-data-worker-open");
        thread.setDaemon(false);
        this.workerThread = thread;
        thread.start();
        log.info("Started background weather worker thread. country={} thread={}", COUNTRY, thread.getName());
    }

    /** Stops the worker loop and waits (bounded) for the thread to unwind on context shutdown. */
    @PreDestroy
    void shutdown() {
        running = false;
        Thread thread = workerThread;
        if (thread == null) {
            return;
        }
        log.info("Stopping weather worker thread. thread={}", thread.getName());
        thread.interrupt();
        try {
            thread.join(SHUTDOWN_JOIN_MS);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
        }
    }

    public int runOnce(String requestedMli) throws InterruptedException {
        List<StationRef> stations = stationRepository.findSupportedUsStations();
        log.info("Loaded supported stations. country={} count={} requestedStation={}",
                COUNTRY,
                stations.size(),
                requestedMli == null || requestedMli.isBlank() ? "<all>" : requestedMli);

        long targetDelayMs = calculateDelayMs(stations.size());
        log.info("Weather worker time budget. country={} budgetHours={} delayPerStationMs={}",
                COUNTRY,
                TIME_BUDGET.toHours(),
                targetDelayMs);

        int processed = 0;
        int skipped = 0;
        int failed = 0;
        boolean stoppedEarly = false;

        for (StationRef station : stations) {
            if (!running || Thread.currentThread().isInterrupted()) {
                stoppedEarly = true;
                break;
            }
            if (requestedMli != null && !requestedMli.isBlank() && !station.mli().equalsIgnoreCase(requestedMli)) {
                continue;
            }

            long startedAt = System.currentTimeMillis();
            switch (stationProcessorOpen.process(station)) {
                case PROCESSED -> processed++;
                case SKIPPED -> skipped++;
                case FAILED -> failed++;
            }

            long remainingDelayMs = targetDelayMs - (System.currentTimeMillis() - startedAt);
            if (remainingDelayMs > 0) {
                sleep(remainingDelayMs);
            }
        }

        if (stoppedEarly) {
            log.info("Worker stopped before cycle completion; skipping post-processing. "
                    + "processed={} skipped={} failed={}", processed, skipped, failed);
            return processed;
        }

        maybeRunPostProcessing(processed, skipped, failed);
        return processed;
    }

    /**
     * Runs post-processing only when the cycle was healthy. A high failure rate (e.g. an open
     * circuit or mass SQL failures) is a cycle-level problem: skip post-processing so probabilities
     * are not recomputed from partial data, and log an error for alerting. Skipped stations
     * (no published feed) are normal and never block post-processing.
     */
    private void maybeRunPostProcessing(int processed, int skipped, int failed) {
        int attempted = processed + failed;
        double failureRate = attempted == 0 ? 0.0 : (double) failed / attempted;

        if (attempted > 0 && failureRate > maxFailureRate) {
            log.error("Cycle degraded; skipping post-processing. country={} processed={} skipped={} "
                            + "failed={} failureRate={} threshold={}",
                    COUNTRY, processed, skipped, failed,
                    String.format("%.2f", failureRate), maxFailureRate);
            return;
        }

        log.info("Cycle healthy; running post-processing. country={} processed={} skipped={} failed={}",
                COUNTRY, processed, skipped, failed);
        postProcessingService.runAfterStationProcessing();
    }

    private void loop() {
        while (running && !Thread.currentThread().isInterrupted()) {
            try {
                int processed = runOnce(null);
                long sleepMs = millisUntilNextMidnight();
                ZonedDateTime nextRunAt = ZonedDateTime.now().plus(Duration.ofMillis(sleepMs));
                log.info("Worker cycle completed. country={} processedStations={} nextRunAt={} sleepMs={}",
                        COUNTRY, processed, nextRunAt, sleepMs);

                if (sleepMs <= 0) {
                    continue;
                }

                sleep(sleepMs);
            } catch (InterruptedException ex) {
                Thread.currentThread().interrupt();
                log.info("Weather worker interrupted. thread={}", Thread.currentThread().getName());
                return;
            } catch (Exception ex) {
                log.error("Weather worker loop failed. country={}", COUNTRY, ex);
            }
        }
        log.info("Weather worker loop exited. thread={}", Thread.currentThread().getName());
    }

    /** Pause between stations / between cycles. Overridable so tests can run without real waits. */
    protected void sleep(long ms) throws InterruptedException {
        Thread.sleep(ms);
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
}
