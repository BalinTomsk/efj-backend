package com.fishfind.water.service;

import com.fishfind.water.repo.WaterStationRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.ZonedDateTime;

/**
 * Runs background station-processing loops for supported countries.
 */
@Component
public class StationWorker implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(StationWorker.class);

    private final WaterStationRepository repo;
    private final StationProcessorCA processorCA;
    private final StationProcessorUS processorUS;
    private final StationPostProcessingService postProcessingService;

    @Value("${water.worker.pause-between-stations-ms:1000}")
    private long pauseBetweenStationsMs;

    public StationWorker(WaterStationRepository repo,
                         StationProcessorCA processorCA,
                         StationProcessorUS processorUS,
                         StationPostProcessingService postProcessingService) {
        this.repo = repo;
        this.processorCA = processorCA;
        this.processorUS = processorUS;
        this.postProcessingService = postProcessingService;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (args.containsOption("console")) {
            return;
        }

        startWorkerThread("CA");
        startWorkerThread("US");
    }

    private void startWorkerThread(String country) {
        Thread workerThread = new Thread(() -> loop(country), workerThreadName(country));
        workerThread.setDaemon(false);
        workerThread.start();
        log.info("Started background station worker thread. country={} thread={}", country, workerThread.getName());
    }

    private void loop(String country) {
        while (true) {
            int processed = 0;
            ZonedDateTime cycleStartedAt = ZonedDateTime.now();
            try {
                processed = runOnce(country, null);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.info("Station worker interrupted. country={} thread={}", country, Thread.currentThread().getName());
                return;
            } catch (Exception e) {
                log.error("Station worker loop failed. country={}", country, e);
            }

            long sleepMs = millisUntilNextHour(cycleStartedAt, ZonedDateTime.now());
            ZonedDateTime nextRunAt = ZonedDateTime.now().plus(Duration.ofMillis(sleepMs));
            log.info("Worker cycle completed. country={} processedStations={} nextRunAt={} sleepMs={}",
                    country, processed, nextRunAt, sleepMs);

            if (sleepMs <= 0) {
                continue;
            }

            try {
                Thread.sleep(sleepMs);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.info("Station worker interrupted during sleep. country={} thread={}",
                        country, Thread.currentThread().getName());
                return;
            }
        }
    }

    private long millisUntilNextHour() {
        ZonedDateTime now = ZonedDateTime.now();
        return millisUntilNextHour(now, now);
    }

    private long millisUntilNextHour(ZonedDateTime cycleStartedAt, ZonedDateTime now) {
        ZonedDateTime nextHour = cycleStartedAt.plusHours(1).withMinute(0).withSecond(0).withNano(0);
        return Math.max(0, Duration.between(now, nextHour).toMillis());
    }

    public int runOnce(String country, String requestedMli) throws InterruptedException {
        var stations = repo.findSupported(country);
        log.info("Loaded supported stations. country={} count={} requestedStation={}", country, stations.size(),
                requestedMli == null || requestedMli.isBlank() ? "<all>" : requestedMli);
        int processed = 0;

        for (var station : stations) {
            if (requestedMli != null && !requestedMli.isBlank() && !station.mli().equalsIgnoreCase(requestedMli)) {
                continue;
            }

            processStation(country, station.mli(), station.state(), station.tz());
            log.debug("Processed station. country={} station={} state={}", country, station.mli(), station.state());
            processed++;

            if (pauseBetweenStationsMs > 0) {
                Thread.sleep(pauseBetweenStationsMs);
            }
        }

        postProcessingService.runAfterStationProcessing();
        return processed;
    }

    private void processStation(String country, String mli, String state, int tz) {
        switch (country) {
            case "CA" -> processorCA.process(mli, state, tz);
            case "US" -> processorUS.process(mli, state, tz);
            default -> throw new IllegalArgumentException("Unsupported country " + country);
        }
    }

    private String workerThreadName(String country) {
        return switch (country) {
            case "CA" -> "water-station-worker-ca";
            case "US" -> "water-station-worker-us";
            default -> "water-station-worker-" + country.toLowerCase();
        };
    }
}
