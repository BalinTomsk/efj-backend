package com.fishfind.weather.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.weather.canonical.CanonicalForecast;
import com.fishfind.weather.canonical.WeatherGovConverter;
import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.WeatherDataRepository;
import java.io.FileNotFoundException;
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
    private final WeatherGovStationResolver resolver;
    private final WeatherDataRepository weatherDataRepository;
    private final WeatherGovConverter converter;
    private final ObjectMapper mapper;

    public StationProcessorWeatherGov(WeatherGovFetcher fetcher,
                                      WeatherGovStationResolver resolver,
                                      WeatherDataRepository weatherDataRepository,
                                      WeatherGovConverter converter,
                                      ObjectMapper mapper) {
        this.fetcher = fetcher;
        this.resolver = resolver;
        this.weatherDataRepository = weatherDataRepository;
        this.converter = converter;
        this.mapper = mapper;
    }

    @Override
    protected void processStation(StationRef station) throws Exception {
        String json = fetchForStation(station);
        // Convert HERE, not in the database. A shape the converter does not recognise throws and is
        // counted as a failed station; the old T-SQL parser could only fail silently.
        CanonicalForecast forecast = converter.convert(json, station.mli());
        String canonical = mapper.writeValueAsString(forecast);
        log.debug("Saving Weather.gov payload. station={} state={} days={} bytes={}",
                station.mli(), station.state(), forecast.days().size(), canonical.length());
        // Persisted under the WATER gauge's own mli, not the NWS grid cell - ows_meteo is keyed by mli.
        weatherDataRepository.saveStationData(station.mli(), canonical, converter.providerType());
        log.debug("Processed station. station={} state={}", station.mli(), station.state());
    }

    @Override
    protected void verifyStation(StationRef station) throws Exception {
        String json = fetchForStation(station);
        log.info("Startup Weather.gov verification fetched payload. station={} state={} bytes={}",
                station.mli(), station.state(), json.length());
    }

    /**
     * Fetches the gauge coordinate's GRIDPOINT FORECAST -- the multi-day forecast, not the latest
     * observation. A coordinate outside NWS coverage surfaces as a skip, exactly like an unpublished
     * feed would.
     *
     * <p>The nearest-station resolver is no longer on this path: a forecast is keyed by grid cell, not
     * by observation station. {@code WeatherGovStationResolver} and its {@code dbo.weather_gov_station}
     * cache are left in place for the observation endpoint but now have no caller here.
     */
    private String fetchForStation(StationRef station) throws Exception {
        String json = fetcher.fetchGridpointForecast(station.latitude(), station.longitude());
        if (json == null || json.isBlank()) {
            throw new FileNotFoundException(
                    "Weather.gov publishes no gridpoint forecast for station " + station.mli());
        }
        return json;
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
