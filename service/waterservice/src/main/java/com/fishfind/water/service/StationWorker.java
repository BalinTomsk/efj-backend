package com.fishfind.water.service;

import com.fishfind.water.domain.StationRef;
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

import java.time.LocalDate;
import java.util.List;
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
    private static final String PROVIDER_CA = "environment-canada";
    private static final String PROVIDER_US = "usgs";
    private static final List<String> WORKER_COUNTRIES = List.of("CA", "US");

    private final WaterStationRepository repo;
    private final StationProcessorCA processorCA;
    private final StationProcessorUS processorUS;
    private final StationPostProcessingService postProcessingService;
    private final ThreadPoolTaskScheduler cycleScheduler;
    private final Executor countryPassExecutor;
    private final MeterRegistry meterRegistry;
    private final StationHttp503BackoffService http503BackoffService;

    @Value("${water.worker.pause-between-stations-ms:1000}")
    private long pauseBetweenStationsMs;

    @Value("${water.worker.cron:0 0 * * * *}")
    private String cron;

    @Value("${water.worker.enabled:true}")
    private boolean enabled;

    public StationWorker(WaterStationRepository repo,
                         StationProcessorCA processorCA,
                         StationProcessorUS processorUS,
                         StationPostProcessingService postProcessingService,
                         ThreadPoolTaskScheduler cycleScheduler,
                         @Qualifier("countryPassExecutor") Executor countryPassExecutor,
                         MeterRegistry meterRegistry,
                         StationHttp503BackoffService http503BackoffService) {
        this.repo = repo;
        this.processorCA = processorCA;
        this.processorUS = processorUS;
        this.postProcessingService = postProcessingService;
        this.cycleScheduler = cycleScheduler;
        this.countryPassExecutor = countryPassExecutor;
        this.meterRegistry = meterRegistry;
        this.http503BackoffService = http503BackoffService;
    }

    /**
     * Registers the recurring cycle on the scheduler, unless the app was started with {@code --console}.
     *
     * @param args parsed application arguments
     */
    @Override
    public void run(ApplicationArguments args) {
        if (!enabled) {
            log.info("Station cycle scheduling is disabled.");
            return;
        }

        if (args.containsOption("console")) {
            return;
        }

        verifyWorkersOnStartup();
        cycleScheduler.schedule(this::runScheduledCycle, new CronTrigger(cron));
        log.info("Scheduled hourly station cycle. cron=\"{}\"", cron);
    }

    /**
     * Verifies each country worker can process one station before the recurring scheduler starts.
     */
    private void verifyWorkersOnStartup() {
        String correlationId = UUID.randomUUID().toString().substring(0, 8);
        MDC.put(MDC_CORRELATION_ID, correlationId);
        try {
            for (String country : WORKER_COUNTRIES) {
                verifyWorkerOnStartup(country);
            }
        } finally {
            MDC.remove(MDC_CORRELATION_ID);
        }
    }

    private void verifyWorkerOnStartup(String country) {
        LocalDate today = LocalDate.now();
        try {
            http503BackoffService.refreshDue(today);
            var stations = repo.findSupported(country);
            if (stations.isEmpty()) {
                log.warn("Startup station verification failed. country={} reason=no-supported-stations", country);
                return;
            }

            var station = stations.get(0);
            ProcessingOutcome outcome = processSingleStation(country, station, today);
            if (outcome == ProcessingOutcome.PROCESSED) {
                log.info("Startup station verification succeeded. country={} station={} state={}",
                        country, station.mli(), station.state());
            } else {
                log.warn("Startup station verification failed. country={} station={} state={} outcome={}",
                        country, station.mli(), station.state(), outcome);
            }
        } catch (RuntimeException ex) {
            log.error("Startup station verification failed. country={}", country, ex);
        }
    }

    /**
     * Wraps {@link #runCycle(String)} so a failed cycle is logged rather than killing the scheduler thread.
     */
    private void runScheduledCycle() {
        java.time.Instant start = java.time.Instant.now();
        try {
            runCycle(null);
        } catch (Exception ex) {
            log.error("Station cycle failed.", ex);
        } finally {
            recordCycleOutcome(start, java.time.Instant.now());
        }
    }

    /**
     * Makes a cycle that overran its cron period observable: the single-threaded scheduler silently skips
     * the next trigger in that case, so without this a slowly degrading cycle time produces data gaps with
     * no signal. Increments {@code water.cycle.overrun} and logs a warning when the cycle finished at or
     * after the next scheduled fire time.
     */
    void recordCycleOutcome(java.time.Instant start, java.time.Instant end) {
        long durationSeconds = java.time.Duration.between(start, end).toSeconds();
        java.time.ZonedDateTime nextFire = org.springframework.scheduling.support.CronExpression.parse(cron)
                .next(start.atZone(java.time.ZoneId.systemDefault()));
        if (nextFire != null && !end.isBefore(nextFire.toInstant())) {
            meterRegistry.counter("water.cycle.overrun").increment();
            log.warn("Station cycle overran its cron period; the next scheduled cycle was skipped. "
                    + "durationSeconds={} cron=\"{}\"", durationSeconds, cron);
        } else {
            log.info("Station cycle duration. durationSeconds={}", durationSeconds);
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

        CompletableFuture<PassStats> caPass = startPass("CA", requestedMli, correlationId);
        CompletableFuture<PassStats> usPass = startPass("US", requestedMli, correlationId);

        PassStats caStats = awaitPass(caPass, "CA");
        PassStats usStats = awaitPass(usPass, "US");
        int succeeded = caStats.succeeded() + usStats.succeeded();
        int failed = caStats.failed() + usStats.failed();

        MDC.put(MDC_CORRELATION_ID, correlationId);
        try {
            RuntimeException postProcessingFailure = null;
            try {
                if (succeeded > 0) {
                    postProcessingService.runAfterStationProcessing();
                } else {
                    log.warn("Skipping post-processing: no stations were processed successfully this cycle.");
                }
            } catch (RuntimeException ex) {
                postProcessingFailure = ex;
                log.error("Species post-processing failed; still running old-data cleanup.", ex);
            }
            try {
                postProcessingService.cleanOldWaterData();
            } catch (RuntimeException ex) {
                // Never let a cleanup failure mask the species-push failure that preceded it.
                if (postProcessingFailure == null) {
                    postProcessingFailure = ex;
                } else {
                    postProcessingFailure.addSuppressed(ex);
                    log.error("Old-data cleanup also failed.", ex);
                }
            }
            log.info("Station cycle completed. successfulStations={} failedStations={} "
                            + "caLastProcessedStation={} usLastProcessedStation={} "
                            + "caLastFailedStation={} usLastFailedStation={}",
                    succeeded,
                    failed,
                    logValue(caStats.lastProcessedStation()),
                    logValue(usStats.lastProcessedStation()),
                    logValue(caStats.lastFailedStation()),
                    logValue(usStats.lastFailedStation()));
            if (postProcessingFailure != null) {
                throw postProcessingFailure;
            }
        } finally {
            MDC.remove(MDC_CORRELATION_ID);
        }
        return succeeded;
    }

    /**
     * Starts one country pass on the pass executor, converting an executor rejection (e.g. during shutdown)
     * into an already-failed future so the cycle degrades gracefully instead of throwing out of scheduling.
     */
    private CompletableFuture<PassStats> startPass(String country, String requestedMli, String correlationId) {
        try {
            return CompletableFuture.supplyAsync(() -> runPass(country, requestedMli, correlationId), countryPassExecutor);
        } catch (java.util.concurrent.RejectedExecutionException ex) {
            return CompletableFuture.failedFuture(ex);
        }
    }

    /**
     * Runs one country pass with the cycle's correlation id bound to the logging context (MDC) for the
     * duration, so every log line emitted on this pass thread carries {@code correlationId}.
     */
    private PassStats runPass(String country, String requestedMli, String correlationId) {
        MDC.put(MDC_CORRELATION_ID, correlationId);
        try {
            PassStats stats = runOnceStats(country, requestedMli);
            log.info("Station pass completed. country={} successfulStations={} failedStations={} "
                            + "lastProcessedStation={} lastFailedStation={}",
                    stats.country(),
                    stats.succeeded(),
                    stats.failed(),
                    logValue(stats.lastProcessedStation()),
                    logValue(stats.lastFailedStation()));
            return stats;
        } finally {
            MDC.clear();
        }
    }

    /**
     * Waits for a country pass to finish, isolating a failure of one country from the other.
     *
     * @param pass the in-flight pass
     * @param country country label for logging
     * @return the pass result, or empty stats if the pass failed
     */
    private PassStats awaitPass(CompletableFuture<PassStats> pass, String country) {
        try {
            return pass.join();
        } catch (CompletionException ex) {
            log.error("Station pass failed. country={}", country, ex.getCause() == null ? ex : ex.getCause());
            return PassStats.empty(country);
        } catch (java.util.concurrent.CancellationException ex) {
            log.error("Station pass was cancelled. country={}", country, ex);
            return PassStats.empty(country);
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
        return runOnceStats(country, requestedMli).succeeded();
    }

    private PassStats runOnceStats(String country, String requestedMli) {
        LocalDate today = LocalDate.now();
        http503BackoffService.refreshDue(today);
        var stations = repo.findSupported(country);
        log.info("Loaded supported stations. country={} count={} requestedStation={}",
                country, stations.size(),
                requestedMli == null || requestedMli.isBlank() ? "<all>" : requestedMli);

        int succeeded = 0;
        int failed = 0;
        String lastProcessedStation = null;
        String lastFailedStation = null;
        boolean anyProcessed = false;
        for (var station : stations) {
            if (requestedMli != null && !requestedMli.isBlank() && !station.mli().equalsIgnoreCase(requestedMli)) {
                continue;
            }

            // Pause BETWEEN stations only — sleeping after the final station just delays the cycle.
            if (anyProcessed && pauseBetweenStationsMs > 0) {
                try {
                    Thread.sleep(pauseBetweenStationsMs);
                } catch (InterruptedException ex) {
                    Thread.currentThread().interrupt();
                    log.info("Station pass interrupted. country={}", country);
                    break;
                }
            }
            anyProcessed = true;

            ProcessingOutcome outcome = processSingleStation(country, station, today);
            lastProcessedStation = station.mli();
            if (outcome == ProcessingOutcome.PROCESSED) {
                succeeded++;
            } else {
                failed++;
                lastFailedStation = station.mli();
            }
        }
        return new PassStats(country, succeeded, failed, lastProcessedStation, lastFailedStation);
    }

    private ProcessingOutcome processSingleStation(String country, StationRef station, LocalDate today) {
        ProcessingOutcome outcome;
        MDC.put(MDC_STATION, station.mli());
        try {
            outcome = processStation(country, station.mli(), station.state(), station.tz());
        } finally {
            MDC.remove(MDC_STATION);
        }
        meterRegistry.counter(STATION_PROCESSED_METRIC,
                "country", country,
                "outcome", outcome == ProcessingOutcome.PROCESSED ? "success" : "failure").increment();
        if (outcome == ProcessingOutcome.PROCESSED) {
            http503BackoffService.recordProcessed(providerFor(country), country, station);
        } else if (outcome == ProcessingOutcome.FAILED_HTTP_503) {
            http503BackoffService.recordHttp503(providerFor(country), country, station, today);
        }
        log.debug("Processed station. country={} station={} state={}", country, station.mli(), station.state());
        return outcome;
    }

    private ProcessingOutcome processStation(String country, String mli, String state, int tz) {
        return switch (country) {
            case "CA" -> processorCA.processWithOutcome(mli, state, tz);
            case "US" -> processorUS.processWithOutcome(mli, state, tz);
            default -> throw new IllegalArgumentException("Unsupported country " + country);
        };
    }

    private String providerFor(String country) {
        return switch (country) {
            case "CA" -> PROVIDER_CA;
            case "US" -> PROVIDER_US;
            default -> throw new IllegalArgumentException("Unsupported country " + country);
        };
    }

    private String logValue(String value) {
        return value == null ? "<none>" : value;
    }

    private record PassStats(
            String country,
            int succeeded,
            int failed,
            String lastProcessedStation,
            String lastFailedStation) {

        private static PassStats empty(String country) {
            return new PassStats(country, 0, 0, null, null);
        }
    }
}
