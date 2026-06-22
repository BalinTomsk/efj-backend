package com.fishfind.water.service;

import com.fishfind.water.repo.WaterStationRepository;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;
import org.springframework.scheduling.support.CronTrigger;
import org.springframework.stereotype.Component;

import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.Executor;

/**
 * Schedules and runs the recurring station-processing cycle.
 *
 * <p>In normal mode an hourly cycle is registered on a Spring-managed scheduler. Each cycle processes the
 * CA and US stations in parallel and then runs post-processing <strong>exactly once</strong> — and only when
 * at least one station was processed successfully. The previous design ran two hand-managed threads that each
 * triggered post-processing, causing the same stored procedure to execute twice concurrently.
 */
@Component
public class StationWorker implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(StationWorker.class);

    private static final String MDC_CORRELATION_ID = "correlationId";
    private static final String MDC_STATION = "station";
    private static final String STATION_PROCESSED_METRIC = "water.station.processed";

    private final WaterStationRepository repo;
    private final StationProcessorCA processorCA;
    private final StationProcessorUS processorUS;
    private final StationPostProcessingService postProcessingService;
    private final ThreadPoolTaskScheduler cycleScheduler;
    private final Executor countryPassExecutor;
    private final MeterRegistry meterRegistry;

    @Value("${water.worker.pause-between-stations-ms:1000}")
    private long pauseBetweenStationsMs;

    @Value("${water.worker.cron:0 0 * * * *}")
    private String cron;

    public StationWorker(WaterStationRepository repo,
                         StationProcessorCA processorCA,
                         StationProcessorUS processorUS,
                         StationPostProcessingService postProcessingService,
                         ThreadPoolTaskScheduler cycleScheduler,
                         @Qualifier("countryPassExecutor") Executor countryPassExecutor,
                         MeterRegistry meterRegistry) {
        this.repo = repo;
        this.processorCA = processorCA;
        this.processorUS = processorUS;
        this.postProcessingService = postProcessingService;
        this.cycleScheduler = cycleScheduler;
        this.countryPassExecutor = countryPassExecutor;
        this.meterRegistry = meterRegistry;
    }

    /**
     * Registers the recurring cycle on the scheduler, unless the app was started with {@code --console}.
     *
     * @param args parsed application arguments
     */
    @Override
    public void run(ApplicationArguments args) {
        if (args.containsOption("console")) {
            return;
        }

        cycleScheduler.schedule(this::runScheduledCycle, new CronTrigger(cron));
        log.info("Scheduled hourly station cycle. cron=\"{}\"", cron);
    }

    /**
     * Wraps {@link #runCycle(String)} so a failed cycle is logged rather than killing the scheduler thread.
     */
    private void runScheduledCycle() {
        try {
            runCycle(null);
        } catch (Exception ex) {
            log.error("Station cycle failed.", ex);
        }
    }

    /**
     * Runs one full cycle: process CA and US stations in parallel, then run post-processing exactly once.
     *
     * <p>Post-processing runs only when at least one station was processed successfully, so an outage of the
     * upstream feeds does not push an empty/incomplete state downstream.
     *
     * @param requestedMli optional single station to restrict processing to; {@code null} for all stations
     * @return the number of stations processed successfully across both countries
     */
    public int runCycle(String requestedMli) {
        String correlationId = UUID.randomUUID().toString().substring(0, 8);

        CompletableFuture<Integer> caPass =
                CompletableFuture.supplyAsync(() -> runPass("CA", requestedMli, correlationId), countryPassExecutor);
        CompletableFuture<Integer> usPass =
                CompletableFuture.supplyAsync(() -> runPass("US", requestedMli, correlationId), countryPassExecutor);

        int succeeded = awaitPass(caPass, "CA") + awaitPass(usPass, "US");

        MDC.put(MDC_CORRELATION_ID, correlationId);
        try {
            if (succeeded > 0) {
                postProcessingService.runAfterStationProcessing();
            } else {
                log.warn("Skipping post-processing: no stations were processed successfully this cycle.");
            }
            log.info("Station cycle completed. processedStations={}", succeeded);
        } finally {
            MDC.remove(MDC_CORRELATION_ID);
        }
        return succeeded;
    }

    /**
     * Runs one country pass with the cycle's correlation id bound to the logging context (MDC) for the
     * duration, so every log line emitted on this pass thread carries {@code correlationId}.
     */
    private int runPass(String country, String requestedMli, String correlationId) {
        MDC.put(MDC_CORRELATION_ID, correlationId);
        try {
            return runOnce(country, requestedMli);
        } finally {
            MDC.clear();
        }
    }

    /**
     * Waits for a country pass to finish, isolating a failure of one country from the other.
     *
     * @param pass the in-flight pass
     * @param country country label for logging
     * @return the pass result, or {@code 0} if the pass failed
     */
    private int awaitPass(CompletableFuture<Integer> pass, String country) {
        try {
            return pass.join();
        } catch (CompletionException ex) {
            log.error("Station pass failed. country={}", country, ex.getCause() == null ? ex : ex.getCause());
            return 0;
        }
    }

    /**
     * Processes one country's stations once and returns the number processed successfully.
     *
     * <p>Does not run post-processing. Honors thread interruption by stopping the pass early.
     *
     * @param country country code to process
     * @param requestedMli optional single station filter; {@code null} for all stations
     * @return the number of stations processed successfully
     */
    public int runOnce(String country, String requestedMli) {
        var stations = repo.findSupported(country);
        log.info("Loaded supported stations. country={} count={} requestedStation={}",
                country, stations.size(),
                requestedMli == null || requestedMli.isBlank() ? "<all>" : requestedMli);

        int succeeded = 0;
        for (var station : stations) {
            if (requestedMli != null && !requestedMli.isBlank() && !station.mli().equalsIgnoreCase(requestedMli)) {
                continue;
            }

            boolean ok;
            MDC.put(MDC_STATION, station.mli());
            try {
                ok = processStation(country, station.mli(), station.state(), station.tz());
            } finally {
                MDC.remove(MDC_STATION);
            }
            meterRegistry.counter(STATION_PROCESSED_METRIC,
                    "country", country,
                    "outcome", ok ? "success" : "failure").increment();
            if (ok) {
                succeeded++;
            }
            log.debug("Processed station. country={} station={} state={}", country, station.mli(), station.state());

            if (pauseBetweenStationsMs > 0) {
                try {
                    Thread.sleep(pauseBetweenStationsMs);
                } catch (InterruptedException ex) {
                    Thread.currentThread().interrupt();
                    log.info("Station pass interrupted. country={}", country);
                    break;
                }
            }
        }
        return succeeded;
    }

    private boolean processStation(String country, String mli, String state, int tz) {
        return switch (country) {
            case "CA" -> processorCA.process(mli, state, tz);
            case "US" -> processorUS.process(mli, state, tz);
            default -> throw new IllegalArgumentException("Unsupported country " + country);
        };
    }
}
