package com.fishfind.water.service;

import com.fishfind.water.repo.WaterDataRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Runs synchronous stored procedures that must happen after a station-processing cycle completes.
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
        log.info("Running post-processing procedure {}", "spPushSpeciesFromLakeToStation");
        waterDataRepository.pushSpeciesFromLakeToStation();
    }

    /**
     * Executes cleanup that must run after every cycle, even if no station was processed successfully.
     */
    public void cleanOldWaterData() {
        log.info("Running post-processing procedure {}", "sp_clean_old_water_data");
        waterDataRepository.cleanOldWaterData();
    }
}
