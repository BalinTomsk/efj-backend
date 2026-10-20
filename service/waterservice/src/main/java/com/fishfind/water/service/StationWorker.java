package com.fishfind.water.service;

import com.fishfind.water.status.ServiceActivity;
import com.fishfind.water.domain.StationRef;
import com.fishfind.water.repo.WaterStationRepository;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;
import org.springframework.scheduling.support.CronTrigger;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.Executor;

/**
 * Schedules and runs the recurring station-processing cycle.
 *
 * <p>In normal mode the CA and US passes are registered as two independent cron tasks on a Spring-managed
 * scheduler, so a slow CA pass (one request per station) cannot hold back the US refresh. Each scheduled pass
 * is followed by post-processing — species push only when at least one station succeeded, cleanup always —
 * serialised between the two countries so the procedures never run concurrently. Console mode
 * ({@link #runCycle(String)}) still processes both countries in parallel and post-processes exactly once.
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
    // The CA and US cron tasks each post-process after their pass; never let the two run the procs at once.
    private final Object postProcessingLock = new Object();

    /** Admin status page: the station in flight (efcs-backend adminservice). Absent in tests and console runs. */
    private ServiceActivity serviceActivity;

    @Autowired(required = false)
    void setServiceActivity(ServiceActivity serviceActivity) {
        this.serviceActivity = serviceActivity;
    }

    // 500, not 1000: at 1000 ms the CA pass took ~66 min (3,937 s on 1.9.0) and overran the hourly cron,
    // so CA refreshed every 2 h. application.yml is git-ignored, so the default is what main records.
    @Value("${water.worker.pause-between-stations-ms:500}")
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
     * Registers one recurring cycle per country on the scheduler, unless the app was started with
     * {@code --console}.
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
        // Independent tasks: one task running both passes meant a ~28 h CA pass also held the US refresh
        // to once per ~28 h.
        for (String country : WORKER_COUNTRIES) {
            cycleScheduler.schedule(() -> runScheduledCycle(country), new CronTrigger(cron));
        }
        log.info("Scheduled hourly station cycle. cron=\"{}\" countries={}", cron, WORKER_COUNTRIES);
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
            prepareUsSnapshot(country, List.of(station.mli()), station.mli());
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
     * Wraps {@link #runCountryCycle(String)} so a failed cycle is logged rather than killing the scheduler task.
     */
    void runScheduledCycle(String country) {
        java.time.Instant start = java.time.Instant.now();
        try {
            runCountryCycle(country);
        } catch (Exception ex) {
            log.error("Station cycle failed. country={}", country, ex);
        } finally {
            recordCycleOutcome(start, java.time.Instant.now(), country);
        }
    }

    /**
     * Makes a cycle that overran its cron period observable: the scheduler silently skips that country's
     * next trigger in that case, so without this a slowly degrading cycle time produces data gaps with no
     * signal. Increments {@code water.cycle.overrun} and logs a warning when the cycle finished at or after
     * the next scheduled fire time.
     *
     * @param country the country whose scheduled cycle this was
     */
    void recordCycleOutcome(java.time.Instant start, java.time.Instant end, String country) {
        long durationSeconds = java.time.Duration.between(start, end).toSeconds();
        java.time.ZonedDateTime nextFire = org.springframework.scheduling.support.CronExpression.parse(cron)
                .next(start.atZone(java.time.ZoneId.systemDefault()));
        if (nextFire != null && !end.isBefore(nextFire.toInstant())) {
            meterRegistry.counter("water.cycle.overrun").increment();
            log.warn("Station cycle overran its cron period; the next scheduled cycle was skipped. "
                    + "country={} durationSeconds={} cron=\"{}\"", country, durationSeconds, cron);
        } else {
            log.info("Station cycle duration. country={} durationSeconds={}", country, durationSeconds);
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
            RuntimeException postProcessingFailure = postProcess(succeeded);
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
     * Runs one country's scheduled cycle: its pass on the calling (scheduler) thread, then post-processing.
     *
     * @param country country code to process
     * @return the number of stations processed successfully
     */
    public int runCountryCycle(String country) {
        String correlationId = UUID.randomUUID().toString().substring(0, 8);
        PassStats stats;
        try {
            stats = runPass(country, null, correlationId);
        } catch (RuntimeException ex) {
            log.error("Station pass failed. country={}", country, ex);
            stats = PassStats.empty(country);
        }

        MDC.put(MDC_CORRELATION_ID, correlationId);
        try {
            RuntimeException postProcessingFailure = postProcess(stats.succeeded());
            log.info("Station cycle completed. country={} successfulStations={} failedStations={} "
                            + "lastProcessedStation={} lastFailedStation={}",
                    country,
                    stats.succeeded(),
                    stats.failed(),
                    logValue(stats.lastProcessedStation()),
                    logValue(stats.lastFailedStation()));
            if (postProcessingFailure != null) {
                throw postProcessingFailure;
            }
        } finally {
            MDC.remove(MDC_CORRELATION_ID);
        }
        return stats.succeeded();
    }

    /**
     * Runs species post-processing (only when {@code succeeded > 0}) and then old-data cleanup, one caller at
     * a time. A species-push failure never blocks cleanup.
     *
     * @param succeeded stations processed successfully by the triggering cycle
     * @return the failure for the caller to rethrow after its summary log (cleanup failure suppressed into the
     *         species failure when both fail), or {@code null}
     */
    private RuntimeException postProcess(int succeeded) {
        synchronized (postProcessingLock) {
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
            return postProcessingFailure;
        }
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

        // US stations are read from one USGS snapshot per pass rather than one request per station.
        prepareUsSnapshot(country, stations.stream().map(StationRef::mli).toList(), requestedMli);

        int succeeded = 0;
        int failed = 0;
        String lastProcessedStation = null;
        String lastFailedStation = null;
        boolean anyProcessed = false;
        for (var station : stations) {
            if (requestedMli != null && !requestedMli.isBlank() && !station.mli().equalsIgnoreCase(requestedMli)) {
                continue;
            }

            // Pause BETWEEN stations only — sleeping after the final station just delays the cycle. US
            // stations make no request of their own (they come from the snapshot), so they never pause.
            if (anyProcessed && !"US".equals(country) && pauseBetweenStationsMs > 0) {
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
                if (outcome == ProcessingOutcome.FAILED_UPSTREAM_OPEN) {
                    log.warn("Stopping station pass because upstream feed is unavailable. country={} station={} state={}",
                            country, station.mli(), station.state());
                    break;
                }
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
        if (serviceActivity != null) {
            serviceActivity.record("station " + mli);
        }
        return switch (country) {
            case "CA" -> processorCA.processWithOutcome(mli, state, tz);
            case "US" -> processorUS.processWithOutcome(mli, state, tz);
            default -> throw new IllegalArgumentException("Unsupported country " + country);
        };
    }

    private void prepareUsSnapshot(String country, List<String> mlis, String requestedMli) {
        if (!"US".equals(country)) {
            return;
        }
        try {
            processorUS.prepareCycle(mlis, requestedMli);
        } catch (IOException ex) {
            throw new UncheckedIOException("USGS snapshot could not be fetched", ex);
        }
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
