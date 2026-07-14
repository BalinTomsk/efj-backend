package com.fishfind.weather.repo;

import com.fishfind.weather.domain.StationRef;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * Loads weather stations that should be processed by the Open-Meteo worker.
 */
@Repository
public class WeatherStationRepository {
    private static final String FIND_SUPPORTED_STATIONS = """
            SELECT TOP 1400 mli, lat, lon, state
            FROM dbo.vwWeatherForecastToDay
            WHERE country = ? ORDER BY stamp DESC
            """;

    private final JdbcTemplate jdbc;

    public WeatherStationRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<StationRef> findSupportedUsStations() {
        return findSupportedStations("US");
    }

    public List<StationRef> findSupportedStations(String country) {
        return jdbc.query(
                FIND_SUPPORTED_STATIONS,
                (rs, rowNum) -> new StationRef(
                        rs.getString("mli"),
                        rs.getDouble("lat"),
                        rs.getDouble("lon"),
                        rs.getString("state")
                ),
                country
        );
    }
}
