package com.fishfind.water.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;

/**
 * Executes a single worker pass when the application is started in console mode.
 */
@Component
@Order(0)
public class ConsoleDebugRunner implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(ConsoleDebugRunner.class);

    private final StationWorkerCA stationWorkerCA;
    private final StationWorkerUS stationWorkerUS;

    /**
     * Creates the console runner.
     *
     * @param stationWorkerCA CA worker used to execute a single processing pass
     * @param stationWorkerUS US worker used to execute a single processing pass
     */
    public ConsoleDebugRunner(StationWorkerCA stationWorkerCA, StationWorkerUS stationWorkerUS) {
        this.stationWorkerCA = stationWorkerCA;
        this.stationWorkerUS = stationWorkerUS;
    }

    /**
     * Runs one worker pass when {@code --console} is present and then exits.
     *
     * @param args parsed application arguments
     * @throws Exception when the underlying worker pass fails
     */
    @Override
    public void run(ApplicationArguments args) throws Exception {
        if (!args.containsOption("console")) {
            return;
        }

        String station = args.getOptionValues("station") == null || args.getOptionValues("station").isEmpty()
                ? null
                : args.getOptionValues("station").get(0);

        log.info("Running console debug mode. station={}", station == null ? "<all>" : station);

        CompletableFuture<Integer> caRun = CompletableFuture.supplyAsync(() -> runWorker("CA", station, stationWorkerCA));
        CompletableFuture<Integer> usRun = CompletableFuture.supplyAsync(() -> runWorker("US", station, stationWorkerUS));

        try {
            CompletableFuture.allOf(caRun, usRun).join();
            int processed = caRun.join() + usRun.join();
            log.info("Console debug mode finished. processedStations={}", processed);
        } catch (CompletionException ex) {
            throw unwrap(ex);
        }
    }

    private int runWorker(String country, String station, Object worker) {
        try {
            if (worker instanceof StationWorkerCA caWorker) {
                return caWorker.runOnce(station);
            }
            if (worker instanceof StationWorkerUS usWorker) {
                return usWorker.runOnce(station);
            }
            throw new IllegalArgumentException("Unsupported worker type for country " + country);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new CompletionException(ex);
        } catch (RuntimeException ex) {
            throw new CompletionException(ex);
        }
    }

    private Exception unwrap(CompletionException ex) {
        Throwable cause = ex.getCause() == null ? ex : ex.getCause();
        if (cause instanceof Exception exception) {
            return exception;
        }
        return new RuntimeException(cause);
    }
}
