package com.fishfind.weather.repo;

import java.time.LocalDate;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * SQL procedure gateway for per-station HTTP 503 backoff state.
 */
@Repository
public class StationHttp503BackoffRepository {
    private static final String REFRESH_DUE =
            "EXEC dbo.sp_weather_station_503_refresh_due ?";
    private static final String RECORD_HTTP_503 =
            "EXEC dbo.sp_weather_station_503_record ?, ?, ?, ?, ?";
    private static final String RESET =
            "EXEC dbo.sp_weather_station_503_reset ?, ?, ?";
    private static final String SUMMARY_BY_STATE =
            "EXEC dbo.sp_weather_station_503_summary_by_state";

    private final JdbcTemplate jdbc;

    public StationHttp503BackoffRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void refreshDue(LocalDate today) {
        jdbc.update(REFRESH_DUE, today);
    }

    public void recordHttp503(String provider, String country, String stationMli, String state, LocalDate today) {
        jdbc.update(RECORD_HTTP_503, provider, country, stationMli, state, today);
    }

    public void reset(String provider, String country, String stationMli) {
        jdbc.update(RESET, provider, country, stationMli);
    }

    public List<BackoffSummary> summaryByState() {
        return jdbc.query(SUMMARY_BY_STATE, (rs, rowNum) -> new BackoffSummary(
                rs.getString("state"),
                rs.getString("backoff_stage"),
                rs.getLong("station_count")
        ));
    }

    public record BackoffSummary(String state, String backoffStage, long stationCount) {
    }
}
