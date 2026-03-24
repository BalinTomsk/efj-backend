package com.fishfind.water.service;

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

    private final StationWorkerCA stationWorkerCA;

    /**
     * Creates the console runner.
     *
     * @param stationWorkerCA worker used to execute a single processing pass
     */
    public ConsoleDebugRunner(StationWorkerCA stationWorkerCA) {
        this.stationWorkerCA = stationWorkerCA;
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
        int processed = stationWorkerCA.runOnce(station);
        log.info("Console debug mode finished. processedStations={}", processed);
    }
}
