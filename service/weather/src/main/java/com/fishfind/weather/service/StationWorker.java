package com.fishfind.weather.service;

import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.WeatherStationRepository;
import java.time.Duration;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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
    private static final String COUNTRY = "US";

    private final WeatherStationRepository stationRepository;
    private final StationProcessorOpen stationProcessorOpen;
    private final StationPostProcessingService postProcessingService;

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

        Thread workerThread = new Thread(this::loop, "weather-data-worker-open");
        workerThread.setDaemon(false);
        workerThread.start();
        log.info("Started background weather worker thread. country={} thread={}", COUNTRY, workerThread.getName());
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
        for (StationRef station : stations) {
            if (requestedMli != null && !requestedMli.isBlank() && !station.mli().equalsIgnoreCase(requestedMli)) {
                continue;
            }

            long startedAt = System.currentTimeMillis();
            stationProcessorOpen.process(station);
            processed++;

            long remainingDelayMs = targetDelayMs - (System.currentTimeMillis() - startedAt);
            if (remainingDelayMs > 0) {
                Thread.sleep(remainingDelayMs);
            }
        }

        postProcessingService.runAfterStationProcessing();
        return processed;
    }

    private void loop() {
        while (true) {
            try {
                int processed = runOnce(null);
                long sleepMs = millisUntilNextMidnight();
                ZonedDateTime nextRunAt = ZonedDateTime.now().plus(Duration.ofMillis(sleepMs));
                log.info("Worker cycle completed. country={} processedStations={} nextRunAt={} sleepMs={}",
                        COUNTRY, processed, nextRunAt, sleepMs);

                if (sleepMs <= 0) {
                    continue;
                }

                Thread.sleep(sleepMs);
            } catch (InterruptedException ex) {
                Thread.currentThread().interrupt();
                log.info("Weather worker interrupted. thread={}", Thread.currentThread().getName());
                return;
            } catch (Exception ex) {
                log.error("Weather worker loop failed. country={}", COUNTRY, ex);
            }
        }
    }

    private long calculateDelayMs(int stationCount) {
        if (stationCount <= 1) {
            return MIN_DELAY_BETWEEN_STATIONS_MS;
        }

        long delayMs = TIME_BUDGET.toMillis() / stationCount;
        return Math.max(delayMs, MIN_DELAY_BETWEEN_STATIONS_MS);
    }

    private long millisUntilNextMidnight() {
        ZonedDateTime now = ZonedDateTime.now();
        ZonedDateTime nextMidnight = LocalDate.now(ZoneId.systemDefault())
                .plusDays(1)
                .atStartOfDay(ZoneId.systemDefault());
        return Math.max(0L, Duration.between(now, nextMidnight).toMillis());
    }
}
