package com.fishfind.water.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

/**
 * Executes a single station cycle when the application is started in console mode.
 */
@Component
@Order(0)
public class ConsoleDebugRunner implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(ConsoleDebugRunner.class);

    private final StationWorker stationWorker;

    /**
     * Creates the console runner.
     *
     * @param stationWorker worker used to execute a single cycle
     */
    public ConsoleDebugRunner(StationWorker stationWorker) {
        this.stationWorker = stationWorker;
    }

    /**
     * Runs one cycle when {@code --console} is present.
     *
     * <p>Delegates to {@link StationWorker#runCycle(String)}, which processes both countries in parallel and
     * runs post-processing once — matching scheduled behavior exactly.
     *
     * @param args parsed application arguments
     */
    @Override
    public void run(ApplicationArguments args) {
        if (!args.containsOption("console")) {
            return;
        }

        String station = args.getOptionValues("station") == null || args.getOptionValues("station").isEmpty()
                ? null
                : args.getOptionValues("station").get(0);

        log.info("Running console debug mode. station={}", station == null ? "<all>" : station);

        int processed = stationWorker.runCycle(station);

        log.info("Console debug mode finished. processedStations={}", processed);
    }
}
