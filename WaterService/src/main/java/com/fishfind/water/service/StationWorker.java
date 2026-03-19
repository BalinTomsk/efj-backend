package com.fishfind.water.service;

import com.fishfind.water.repo.WaterStationRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

@Component
public class StationWorker implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(StationWorker.class);

    private final WaterStationRepository repo;
    private final StationProcessor processor;

    @Value("${water.worker.pause-between-stations-ms:1000}")
    private long pauseBetweenStationsMs;

    @Value("${water.worker.pause-between-cycles-ms:300000}")
    private long pauseBetweenCyclesMs;

    public StationWorker(WaterStationRepository repo, StationProcessor processor) {
        this.repo = repo;
        this.processor = processor;
    }

    @Override
    public void run(org.springframework.boot.ApplicationArguments args) {
        if (args.containsOption("console")) {
            return;
        }

        new Thread(this::loop).start();
    }

    private void loop() {
        while (true) {
            try {
                runOnce(null);
                Thread.sleep(pauseBetweenCyclesMs);

            } catch (Exception e) {
                log.error("Station worker loop failed", e);
            }
        }
    }

    public int runOnce(String requestedMli) throws InterruptedException {
        var stations = repo.findSupported();
        System.out.println("Loaded stations: " + stations.size());
        int processed = 0;

        for (var station : stations) {
            if (requestedMli != null && !requestedMli.isBlank() && !station.mli().equalsIgnoreCase(requestedMli)) {
                continue;
            }

            processor.process(station.mli(), station.state(), station.tz());
            System.out.println("Processed: " + station.mli());
            processed++;

            if (pauseBetweenStationsMs > 0) {
                Thread.sleep(pauseBetweenStationsMs);
            }
        }

        return processed;
    }
}
