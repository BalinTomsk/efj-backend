package com.fishfind.water.service;

import com.fishfind.water.repo.WaterDataRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Runs synchronous stored procedures that must happen after a station-processing pass completes.
 */
@Service
public class StationPostProcessingService {
    private static final Logger log = LoggerFactory.getLogger(StationPostProcessingService.class);

    private final WaterDataRepository waterDataRepository;

    public StationPostProcessingService(WaterDataRepository waterDataRepository) {
        this.waterDataRepository = waterDataRepository;
    }

    /**
     * Executes the required post-processing procedures in order.
     */
    public void runAfterStationProcessing() {
        log.info("Running post-processing procedure {}", "spCleanWeatherWaterData");
        // waterDataRepository.cleanWeatherWaterData();

        log.info("Running post-processing procedure {}", "spPushSpeciesFromLakeToStation");
        waterDataRepository.pushSpeciesFromLakeToStation();
    }
}
