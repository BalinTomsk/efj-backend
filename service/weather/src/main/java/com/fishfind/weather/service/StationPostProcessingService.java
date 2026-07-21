package com.fishfind.weather.service;

import com.fishfind.weather.repo.WeatherDataRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Runs synchronous stored procedures after station processing completes.
 */
@Service
public class StationPostProcessingService {
    private static final Logger log = LoggerFactory.getLogger(StationPostProcessingService.class);

    private final WeatherDataRepository weatherDataRepository;

    public StationPostProcessingService(WeatherDataRepository weatherDataRepository) {
        this.weatherDataRepository = weatherDataRepository;
    }

    public synchronized void runAfterStationProcessing() {
        log.info("Running post-processing procedure {}", "spPushSpeciesFromLakeToStation");
        weatherDataRepository.pushSpeciesFromLakeToStation();

        log.info("Running post-processing procedure {}", "spTotalUpdateProbability");
        weatherDataRepository.totalUpdateProbability();

        log.info("Running post-processing procedure {}", "sp_clean_old_weather_data");
        weatherDataRepository.cleanOldWeatherData();
    }
}
