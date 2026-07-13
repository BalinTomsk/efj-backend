package com.fishfind.weather.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

/**
 * Executes a single worker pass when the application is started in console mode.
 */
@Component
@Order(0)
public class ConsoleDebugRunner implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(ConsoleDebugRunner.class);

    private final StationWorker stationWorker;

    public ConsoleDebugRunner(StationWorker stationWorker) {
        this.stationWorker = stationWorker;
    }

    @Override
    public void run(ApplicationArguments args) throws Exception {
        if (!args.containsOption("console")) {
            return;
        }

        String station = args.getOptionValues("station") == null || args.getOptionValues("station").isEmpty()
                ? null
                : args.getOptionValues("station").get(0);

        log.info("Running console debug mode. country=US station={}", station == null ? "<all>" : station);
        StationWorker.RunResult result = stationWorker.runOnce(station);
        log.info("Console debug mode finished. country=US processedStations={} failedStations={}",
                result.processedStations(), result.failedStations());

        // Non-zero only when every attempted station failed, so a cron/script wrapper can
        // detect a fully broken pass; a partial success (some processed, some failed) still
        // did useful work and should not be treated as a failed run.
        boolean everyStationFailed = result.processedStations() == 0 && result.failedStations() > 0;
        exit(everyStationFailed ? 1 : 0);
    }

    /** Terminates the process after the one-shot pass. Overridable so tests need not exit the JVM. */
    protected void exit(int code) {
        System.exit(code);
    }
}
