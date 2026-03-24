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
 * Runs the US background station-processing loop in normal application mode.
 */
@Component
public class StationWorkerUS implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(StationWorkerUS.class);

    private final WaterStationRepository repo;
    private final StationProcessorUS processorUS;

    @Value("${water.worker.pause-between-stations-ms:1000}")
    private long pauseBetweenStationsMs;

    /**
     * Creates the US background worker.
     *
     * @param repo repository used to load supported stations
     * @param processorUS processor used to handle individual US stations
     */
    public StationWorkerUS(WaterStationRepository repo, StationProcessorUS processorUS) {
        this.repo = repo;
        this.processorUS = processorUS;
    }

    @Override
    public void run(org.springframework.boot.ApplicationArguments args) {
        if (args.containsOption("console")) {
            return;
        }

        Thread workerThread = new Thread(this::loop, "water-station-worker-us");
        workerThread.setDaemon(false);
        workerThread.start();
        log.info("Started US background station worker thread. thread={}", workerThread.getName());
    }

    private void loop() {
        while (true) {
            int processed = 0;
            try {
                processed = runOnce(null);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.info("US station worker interrupted. thread={}", Thread.currentThread().getName());
                return;
            } catch (Exception e) {
                log.error("US station worker loop failed", e);
            }

            long sleepMs = millisUntilNextHour();
            ZonedDateTime nextRunAt = ZonedDateTime.now().plus(Duration.ofMillis(sleepMs));
            log.info("US worker cycle completed. processedStations={} nextRunAt={} sleepMs={}",
                    processed, nextRunAt, sleepMs);

            try {
                Thread.sleep(sleepMs);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.info("US station worker interrupted during sleep. thread={}", Thread.currentThread().getName());
                return;
            }
        }
    }

    private long millisUntilNextHour() {
        ZonedDateTime now = ZonedDateTime.now();
        ZonedDateTime nextHour = now.plusHours(1).withMinute(0).withSecond(0).withNano(0);
        return Duration.between(now, nextHour).toMillis();
    }

    /**
     * Processes either all supported US stations or a single requested station.
     *
     * @param requestedMli optional station identifier to filter by
     * @return number of processed stations
     * @throws InterruptedException when the worker is interrupted while waiting between stations
     */
    public int runOnce(String requestedMli) throws InterruptedException {
        var stationsUS = repo.findSupported("US");
        log.info("Loaded supported US stations. count={} requestedStation={}", stationsUS.size(),
                requestedMli == null || requestedMli.isBlank() ? "<all>" : requestedMli);
        int processed = 0;

        for (var station : stationsUS) {
            if (requestedMli != null && !requestedMli.isBlank() && !station.mli().equalsIgnoreCase(requestedMli)) {
                continue;
            }

            processorUS.process(station.mli(), station.state(), station.tz());
            log.info("Processed US station. station={} state={}", station.mli(), station.state());
            processed++;

            if (pauseBetweenStationsMs > 0) {
                Thread.sleep(pauseBetweenStationsMs);
            }
        }

        return processed;
    }
}
