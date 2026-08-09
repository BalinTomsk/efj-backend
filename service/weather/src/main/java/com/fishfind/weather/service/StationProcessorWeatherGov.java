package com.fishfind.weather.service;

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

    public StationProcessorWeatherGov(WeatherGovFetcher fetcher,
                                      WeatherGovStationResolver resolver,
                                      WeatherDataRepository weatherDataRepository) {
        this.fetcher = fetcher;
        this.resolver = resolver;
        this.weatherDataRepository = weatherDataRepository;
    }

    @Override
    protected void processStation(StationRef station) throws Exception {
        String json = fetchForStation(station);
        log.debug("Saving Weather.gov payload. station={} state={} bytes={}", station.mli(), station.state(), json.length());
        // Persisted under the WATER gauge's own mli, not the NWS station's id — ows_meteo is keyed by mli.
        weatherDataRepository.saveStationData(station.mli(), json);
        log.debug("Processed station. station={} state={}", station.mli(), station.state());
    }

    @Override
    protected void verifyStation(StationRef station) throws Exception {
        String json = fetchForStation(station);
        log.info("Startup Weather.gov verification fetched payload. station={} state={} bytes={}",
                station.mli(), station.state(), json.length());
    }

    /**
     * Resolves the gauge's coordinate to an NWS station (cached), then fetches that station's latest
     * observation. A gauge with no NWS station nearby surfaces as a skip, exactly like an unpublished
     * feed would.
     */
    private String fetchForStation(StationRef station) throws Exception {
        String nwsStation = resolver.resolve(station);
        if (nwsStation == null || nwsStation.isBlank()) {
            throw new FileNotFoundException(
                    "Weather.gov has no observation station near station " + station.mli());
        }
        return fetcher.fetchLatestObservation(nwsStation);
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
