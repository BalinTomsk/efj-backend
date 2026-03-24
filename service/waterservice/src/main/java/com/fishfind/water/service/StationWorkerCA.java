package com.fishfind.water.service;

import com.fishfind.water.repo.WaterStationRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.ZonedDateTime;

/**
 * Runs the background station-processing loop in normal application mode.
 */
@Component
public class StationWorkerCA implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(StationWorkerCA.class);

    private final WaterStationRepository repo;
    private final StationProcessorCA processor;

    @Value("${water.worker.pause-between-stations-ms:1000}")
    private long pauseBetweenStationsMs;

    /**
     * Creates the background worker.
     *
     * @param repo repository used to load supported stations
     * @param processor processor used to handle individual stations
     */
    public StationWorkerCA(WaterStationRepository repo, StationProcessorCA processor) {
        this.repo = repo;
        this.processor = processor;
    }

    /**
     * Starts the background worker thread unless the application is running in console mode.
     *
     * @param args parsed application arguments
     */
    @Override
    public void run(org.springframework.boot.ApplicationArguments args) {
        if (args.containsOption("console")) {
            return;
        }

        Thread workerThread = new Thread(this::loop, "water-station-worker");
        workerThread.setDaemon(false);
        workerThread.start();
        log.info("Started background station worker thread. thread={}", workerThread.getName());
    }

    /**
     * Repeatedly processes all supported stations, then waits until the next hour boundary.
     */
    private void loop() {
        while (true) {
            int processed = 0;
            try {
                processed = runOnce(null);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.info("Station worker interrupted. thread={}", Thread.currentThread().getName());
                return;
            } catch (Exception e) {
                log.error("Station worker loop failed", e);
            }

            long sleepMs = millisUntilNextHour();
            ZonedDateTime nextRunAt = ZonedDateTime.now().plus(Duration.ofMillis(sleepMs));
            log.info("Worker cycle completed. processedStations={} nextRunAt={} sleepMs={}",
                    processed, nextRunAt, sleepMs);

            try {
                Thread.sleep(sleepMs);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.info("Station worker interrupted during sleep. thread={}", Thread.currentThread().getName());
                return;
            }
        }
    }

    /**
     * Calculates the delay until the next top-of-hour in the local system timezone.
     *
     * @return milliseconds to sleep before the next worker cycle
     */
    private long millisUntilNextHour() {
        ZonedDateTime now = ZonedDateTime.now();
        ZonedDateTime nextHour = now.plusHours(1).withMinute(0).withSecond(0).withNano(0);
        return Duration.between(now, nextHour).toMillis();
    }

    /**
     * Processes either all supported stations or a single requested station.
     *
     * @param requestedMli optional station identifier to filter by
     * @return number of processed stations
     * @throws InterruptedException when the worker is interrupted while waiting between stations
     */
    public int runOnce(String requestedMli) throws InterruptedException {
        var stations = repo.findSupported();
        log.info("Loaded supported stations. count={} requestedStation={}", stations.size(),
                requestedMli == null || requestedMli.isBlank() ? "<all>" : requestedMli);
        int processed = 0;

        for (var station : stations) {
            if (requestedMli != null && !requestedMli.isBlank() && !station.mli().equalsIgnoreCase(requestedMli)) {
                continue;
            }

            processor.process(station.mli(), station.state(), station.tz());
            log.info("Processed station. station={} state={}", station.mli(), station.state());
            processed++;

            if (pauseBetweenStationsMs > 0) {
                Thread.sleep(pauseBetweenStationsMs);
            }
        }

        return processed;
    }
}
