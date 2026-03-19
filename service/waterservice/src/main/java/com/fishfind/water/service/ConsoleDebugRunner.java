package com.fishfind.water.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

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

        log.info("Running console debug mode. station={}", station == null ? "<all>" : station);
        int processed = stationWorker.runOnce(station);
        log.info("Console debug mode finished. processedStations={}", processed);
    }
}
