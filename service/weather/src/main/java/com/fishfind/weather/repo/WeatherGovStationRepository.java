package com.fishfind.weather.repo;

import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * Reads and writes the cached "which NWS station serves this water gauge" mapping
 * (envdata {@code weather_gov_station}), via the view {@code v_weather_gov_station} and
 * {@code sp_weather_gov_station_save} — never the table directly.
 *
 * <p>{@code WaterStation.MLI} is a WATER gauge identifier — every US row is a numeric USGS site
 * number, never an NWS call sign — so {@code /stations/{mli}/observations} 404s for all of them. The
 * gauge's coordinate resolves to a real station instead, and that mapping is geographic and
 * effectively permanent, so it is cached rather than re-asked on every cycle.
 */
@Repository
public class WeatherGovStationRepository {

    private final JdbcTemplate jdbc;

    public WeatherGovStationRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * The cached answer for a gauge.
     *
     * <p>Note the two distinct "empty" cases: an empty {@link Optional} means <em>never asked</em>,
     * while a present {@link CachedStation} whose {@code stationId()} is {@code null} means
     * <em>asked, and there is no station nearby</em> — a negative cache that stops the resolver
     * re-asking a point that will never resolve.
     */
    public Optional<CachedStation> find(String mli) {
        List<CachedStation> rows = jdbc.query(
                "SELECT station_id FROM v_weather_gov_station WHERE mli = ?",
                (rs, rowNum) -> new CachedStation(rs.getString("station_id")),
                mli);
        return rows.isEmpty() ? Optional.empty() : Optional.of(rows.get(0));
    }

    /**
     * Records the resolution for a gauge. Pass {@code stationId} as {@code null} to cache
     * "no station nearby".
     */
    public void save(String mli, double latitude, double longitude, String stationId) {
        jdbc.update("CALL sp_weather_gov_station_save(?, ?, ?, ?)", ps -> {
            ps.setString(1, mli);
            ps.setDouble(2, latitude);
            ps.setDouble(3, longitude);
            if (stationId == null) {
                ps.setNull(4, java.sql.Types.VARCHAR);
            } else {
                ps.setString(4, stationId);
            }
        });
    }

    /** @param stationId the NWS call sign, or {@code null} for "resolved, none nearby" */
    public record CachedStation(String stationId) {
    }
}
