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

    private final StationWorker stationWorker;

    /**
     * Creates the console runner.
     *
     * @param stationWorker worker used to execute single processing passes
     */
    public ConsoleDebugRunner(StationWorker stationWorker) {
        this.stationWorker = stationWorker;
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

        CompletableFuture<Integer> caRun = CompletableFuture.supplyAsync(() -> runWorker("CA", station));
        CompletableFuture<Integer> usRun = CompletableFuture.supplyAsync(() -> runWorker("US", station));

        try {
            CompletableFuture.allOf(caRun, usRun).join();
            int processed = caRun.join() + usRun.join();
            log.info("Console debug mode finished. processedStations={}", processed);
        } catch (CompletionException ex) {
            throw unwrap(ex);
        }
    }

    private int runWorker(String country, String station) {
        try {
            return stationWorker.runOnce(country, station);
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
