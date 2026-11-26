package com.fishfind.weather.repo;

import com.fishfind.weather.domain.StationRef;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * Loads the weather stations that should be processed, from envdata ({@code sp_station_weather_due}, a random sample
 * of {@code v_station_weather_due}; port of MSSQL {@code vwWeatherForecastToDay}).
 *
 * <p>The limit is the caller's: {@code StationWorker} passes the provider's remaining daily budget
 * ({@code weather.worker.daily-limit.*}, enforced across restarts by {@code WeatherApiUsageTracker}). The two old
 * fixed limits (1,400 default, 900 Weather.gov) were unused overloads and are gone, as in the C# twin.
 */
@Repository
public class WeatherStationRepository {
    private static final String FIND_SUPPORTED_STATIONS = "CALL sp_station_weather_due(?, ?)";
    private static final String COUNT_SUPPORTED_STATIONS = """
            SELECT COUNT(1)
            FROM v_station_weather_due
            WHERE country = ?
            """;

    private final JdbcTemplate jdbc;

    public WeatherStationRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * Stations for one country, capped at {@code limit}, in random order.
     */
    public List<StationRef> findSupportedStations(String country, int limit) {
        if (limit <= 0) {
            throw new IllegalArgumentException("limit must be positive");
        }
        return jdbc.query(
                FIND_SUPPORTED_STATIONS,
                (rs, rowNum) -> new StationRef(
                        rs.getString("mli"),
                        rs.getDouble("lat"),
                        rs.getDouble("lon"),
                        rs.getString("state")
                ),
                country,
                limit
        );
    }

    /**
     * How many stations the view holds for a country, independent of any per-cycle limit.
     */
    public int countSupportedStations(String country) {
        Integer count = jdbc.queryForObject(COUNT_SUPPORTED_STATIONS, Integer.class, country);
        return count == null ? 0 : count;
    }
}
