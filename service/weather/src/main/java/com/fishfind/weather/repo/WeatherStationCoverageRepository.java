package com.fishfind.weather.repo;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * Records whether a provider can serve a given gauge, so a fallback worker can pick up the ones it
 * cannot ({@code dbo.weather_station_coverage}, via {@code dbo.sp_save_weather_station_coverage} —
 * never the table directly).
 *
 * <p>Not every provider answers every coordinate. Weather Canada's SWOB is an observation network
 * with real geographic gaps — even a 0.5° (~55 km) search box finds nothing for roughly one Canadian
 * gauge in six. Those gauges otherwise skip silently on every cycle forever, and since a
 * fully-skipped cycle still reports healthy, nothing ever surfaces them.
 *
 * <p>Read the gaps with {@code dbo.fn_weather_uncovered_stations(@provider)}, which returns the
 * coordinate as well as the mli.
 */
@Repository
public class WeatherStationCoverageRepository {

    private final JdbcTemplate jdbc;

    public WeatherStationCoverageRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * Flags whether {@code provider} had data for {@code mli}. Upserts, so a gap that later resolves
     * simply clears.
     */
    public void save(String mli, String provider, boolean covered) {
        jdbc.update("EXEC dbo.sp_save_weather_station_coverage ?, ?, ?", mli, provider, covered ? 1 : 0);
    }
}
