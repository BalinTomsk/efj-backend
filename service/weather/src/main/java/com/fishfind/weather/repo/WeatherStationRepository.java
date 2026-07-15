package com.fishfind.weather.repo;

import com.fishfind.weather.domain.StationRef;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * Loads weather stations that should be processed by the weather workers.
 */
@Repository
public class WeatherStationRepository {
    private static final int DEFAULT_STATION_LIMIT = 1400;
    private static final int US_WEATHER_GOV_STATION_LIMIT = 900;
    private static final String FIND_SUPPORTED_STATIONS = """
            SELECT TOP (?) mli, lat, lon, state
            FROM dbo.vwWeatherForecastToDay
            WHERE country = ?
            """;

    private final JdbcTemplate jdbc;

    public WeatherStationRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<StationRef> findSupportedUsStations() {
        return findSupportedStations("US", US_WEATHER_GOV_STATION_LIMIT);
    }

    public List<StationRef> findSupportedStations(String country) {
        return findSupportedStations(country, DEFAULT_STATION_LIMIT);
    }

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
                limit,
                country
        );
    }
}
