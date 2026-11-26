package com.fishfind.weather.repo;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * Records whether a provider can serve a given gauge, so a fallback worker can pick up the ones it
 * cannot (envdata {@code provider_coverage}, via {@code sp_provider_coverage_save} — never the table
 * directly).
 *
 * <p>Not every provider answers every coordinate. Weather Canada's SWOB is an observation network
 * with real geographic gaps — even a 0.5° (~55 km) search box finds nothing for roughly one Canadian
 * gauge in six. Those gauges otherwise skip silently on every cycle forever, and since a
 * fully-skipped cycle still reports healthy, nothing ever surfaces them.
 *
 * <p>Read the gaps with the envdata view {@code v_provider_coverage}.
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
        jdbc.update("CALL sp_provider_coverage_save(?, ?, ?)", mli, provider, covered ? 1 : 0);
    }
}
