package com.fishfind.weather.service;

import com.fishfind.weather.canonical.WeatherSourceType;
import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.WeatherDataRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Processes a single Canadian station via Weather Canada SWOB observations.
 */
@Service
public class StationProcessorWeatherCanada extends StationProcessorBase {
    private static final Logger log = LoggerFactory.getLogger(StationProcessorWeatherCanada.class);

    private final WeatherCanadaFetcher fetcher;
    private final WeatherDataRepository weatherDataRepository;

    public StationProcessorWeatherCanada(WeatherCanadaFetcher fetcher,
                                         WeatherDataRepository weatherDataRepository) {
        this.fetcher = fetcher;
        this.weatherDataRepository = weatherDataRepository;
    }

    @Override
    protected void processStation(StationRef station) throws Exception {
        String json = fetcher.fetchLatestObservation(station.latitude(), station.longitude());
        log.debug("Saving Weather Canada payload. station={} state={} bytes={}",
                station.mli(), station.state(), json.length());
        weatherDataRepository.saveStationData(station.mli(), json, WeatherSourceType.ENVIRONMENT_CANADA);
        log.debug("Processed station. station={} state={}", station.mli(), station.state());
    }

    @Override
    protected void verifyStation(StationRef station) throws Exception {
        String json = fetcher.fetchLatestObservation(station.latitude(), station.longitude());
        log.info("Startup Weather Canada verification fetched payload. station={} state={} bytes={}",
                station.mli(), station.state(), json.length());
    }

    @Override
    protected Logger logger() {
        return log;
    }

    @Override
    protected String country() {
        return "CA";
    }

    @Override
    protected String missingSourceDescription() {
        return "Weather Canada source";
    }
}
