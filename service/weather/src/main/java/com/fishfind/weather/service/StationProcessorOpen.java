package com.fishfind.weather.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.weather.canonical.CanonicalForecast;
import com.fishfind.weather.canonical.OpenMeteoConverter;
import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.WeatherDataRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Processes a single US weather station via Open-Meteo.
 */
@Service
public class StationProcessorOpen extends StationProcessorBase {
    private static final Logger log = LoggerFactory.getLogger(StationProcessorOpen.class);

    private final OpenMeteoFetcher fetcher;
    private final WeatherDataRepository weatherDataRepository;
    private final OpenMeteoConverter converter;
    private final ObjectMapper mapper;

    public StationProcessorOpen(OpenMeteoFetcher fetcher,
                                WeatherDataRepository weatherDataRepository,
                                OpenMeteoConverter converter,
                                ObjectMapper mapper) {
        this.fetcher = fetcher;
        this.weatherDataRepository = weatherDataRepository;
        this.converter = converter;
        this.mapper = mapper;
    }

    @Override
    protected void processStation(StationRef station) throws Exception {
        String json = fetcher.fetch(station.latitude(), station.longitude());
        // The hourly-to-daily reduction the database used to do now happens here, where it is testable.
        CanonicalForecast forecast = converter.convert(json, station.mli());
        String canonical = mapper.writeValueAsString(forecast);
        log.debug("Saving Open-Meteo payload. station={} state={} days={} bytes={}",
                station.mli(), station.state(), forecast.days().size(), canonical.length());
        weatherDataRepository.saveStationData(station.mli(), canonical, converter.providerType());
        log.debug("Processed station. station={} state={}", station.mli(), station.state());
    }

    @Override
    protected void verifyStation(StationRef station) throws Exception {
        String json = fetcher.fetch(station.latitude(), station.longitude());
        log.info("Startup Open-Meteo verification fetched payload. station={} state={} bytes={}",
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
        return "Open-Meteo source";
    }
}
