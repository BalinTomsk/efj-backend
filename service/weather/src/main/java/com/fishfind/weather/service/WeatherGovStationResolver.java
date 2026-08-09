package com.fishfind.weather.service;

import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.WeatherGovStationRepository;
import java.io.IOException;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Answers "which NWS station serves this water gauge", caching the answer in the database.
 *
 * <p>{@code WaterStation.MLI} is a water-gauge identifier — a USGS site number for US rows — never an
 * NWS call sign, so asking Weather.gov for observations by {@code mli} 404s for every US station. All
 * 2,219 US rows in {@code vwWeatherForecastToDay} are numeric, so this was a permanent 100% skip. The
 * gauge's coordinate resolves to a real station instead.
 *
 * <p>The mapping is geographic and effectively permanent, so it is resolved once per gauge and
 * stored: doing it inline every cycle would double the request count against a rate-limited public
 * API for no benefit. A "no station nearby" answer is cached too — otherwise every cycle would
 * re-ask a point that will never resolve.
 */
@Service
public class WeatherGovStationResolver {
    private static final Logger log = LoggerFactory.getLogger(WeatherGovStationResolver.class);

    private final WeatherGovFetcher fetcher;
    private final WeatherGovStationRepository repository;

    public WeatherGovStationResolver(WeatherGovFetcher fetcher, WeatherGovStationRepository repository) {
        this.fetcher = fetcher;
        this.repository = repository;
    }

    /**
     * The NWS station id to fetch observations from, or {@code null} when there is none nearby.
     *
     * @param station the water gauge, whose coordinate is what actually gets resolved
     */
    public String resolve(StationRef station) throws IOException {
        Optional<WeatherGovStationRepository.CachedStation> cached = repository.find(station.mli());
        if (cached.isPresent()) {
            // A row exists, so the question was already asked — including when the answer was "none".
            return cached.get().stationId();
        }

        String resolved = fetcher.findNearestStation(station.latitude(), station.longitude());

        // Cache the miss as well as the hit; both are answers.
        repository.save(station.mli(), station.latitude(), station.longitude(), resolved);

        if (resolved == null) {
            log.info("No Weather.gov station near station. station={} state={} lat={} lon={}",
                    station.mli(), station.state(), station.latitude(), station.longitude());
        } else {
            log.info("Resolved Weather.gov station for gauge. station={} state={} nwsStation={}",
                    station.mli(), station.state(), resolved);
        }

        return resolved;
    }
}
