package com.fishfind.weather.service;

import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.WeatherDataRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Processes a single US weather station via Weather.gov latest observations.
 */
@Service
public class StationProcessorWeatherGov extends StationProcessorBase {
    private static final Logger log = LoggerFactory.getLogger(StationProcessorWeatherGov.class);

    private final WeatherGovFetcher fetcher;
    private final WeatherDataRepository weatherDataRepository;

    public StationProcessorWeatherGov(WeatherGovFetcher fetcher, WeatherDataRepository weatherDataRepository) {
        this.fetcher = fetcher;
        this.weatherDataRepository = weatherDataRepository;
    }

    @Override
    protected void processStation(StationRef station) throws Exception {
        String json = fetcher.fetchLatestObservation(station.mli());
        log.info("Saving Weather.gov payload. station={} state={} bytes={}", station.mli(), station.state(), json.length());
        weatherDataRepository.saveStationData(station.mli(), json);
        log.info("Processed station. station={} state={}", station.mli(), station.state());
    }

    @Override
    protected void verifyStation(StationRef station) throws Exception {
        String json = fetcher.fetchLatestObservation(station.mli());
        log.info("Startup Weather.gov verification fetched payload. station={} state={} bytes={}",
                station.mli(), station.state(), json.length());
    }

    @Override
    protected Logger logger() {
        return log;
    }

    @Override
    protected String country() {
        return "US";
    }

    @Override
    protected String missingSourceDescription() {
        return "Weather.gov source";
    }
}
