package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;

import java.sql.Types;
import java.util.List;

/**
 * JDBC forecast repository (1.31.0). Each method is one statement against objects the website's forecast pages
 * already use, so the app gets the website's numbers. Guarded by the shared {@code sqlRetry}/{@code sqlBreaker}
 * like every other repository bean; {@link CachingForecastQueryRepository} sits in front of it.
 */
public class JdbcForecastQueryRepository implements ForecastQueryRepository {

    /** Planning.aspx's map ({@code dbo.fn_map_location}) cut to a radius; envfish-db 2026-11-13. */
    static final String STATIONS_SQL = "SELECT dbo.fn_forecast_stations_json(?, ?, ?, ?, ?, ?)";

    /**
     * Plot.aspx in one round trip: the chart document ({@code GetJsonPlot}), the first 23 rows of the day/weather
     * calendar with the columns {@code LoadPlaceLatLon} reads, and the 7-day score of Reasoning.aspx (day 0 = the
     * map's value). The week doubles as the existence check: it is NULL for an unknown station or a fish not listed
     * there, while {@code fn_forecast_plot_json} returns a document for any sid.
     */
    static final String PLOT_SQL = "SELECT dbo.fn_forecast_plot_json(?, ?) AS plot"
            + ", (SELECT TOP 23 CONVERT(char(10), w.dt, 23) AS dt, w.wind_degree, w.precipitation, w.wind_direction"
            + ", w.temperature_low, w.temperature_high, w.wind_max_speed, w.icon, w.shortText"
            + " FROM dbo.fn_plot_weather(?) w ORDER BY w.dt FOR JSON PATH, INCLUDE_NULL_VALUES) AS calendar"
            + ", JSON_QUERY(dbo.fn_fish_reasoning_json(?, ?, SYSUTCDATETIME()), '$.week') AS week";

    /** Reasoning.aspx's document ({@code LoadReasoning}), moved {@code day} days ahead. */
    static final String REASONING_SQL =
            "SELECT dbo.fn_fish_reasoning_json(?, ?, DATEADD(DAY, ?, SYSUTCDATETIME()))";

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcForecastQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "stationsFallback")
    public JsonNode stations(String fishId, double lat, double lon, int radiusKm, String country, int limit) {
        List<String> rows = jdbc.query(STATIONS_SQL, ps -> {
            ps.setString(1, fishId);
            ps.setDouble(2, lat);
            ps.setDouble(3, lon);
            ps.setDouble(4, radiusKm);
            if (country == null) {
                ps.setNull(5, Types.CHAR);
            } else {
                ps.setString(5, country);
            }
            ps.setInt(6, limit);
        }, (rs, i) -> rs.getString(1));
        return parseFirst(rows);
    }

    @SuppressWarnings("unused")
    public JsonNode stationsFallback(String fishId, double lat, double lon, int radiusKm, String country, int limit,
                                     Throwable ex) {
        throw new RuntimeException("SQL forecast-stations query failed for fish " + fishId, ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "plotFallback")
    public JsonNode plot(int sid, String fishId) {
        List<String[]> rows = jdbc.query(PLOT_SQL, ps -> {
            ps.setInt(1, sid);
            ps.setString(2, fishId);
            ps.setInt(3, sid);
            ps.setInt(4, sid);
            ps.setString(5, fishId);
        }, (rs, i) -> new String[] {rs.getString(1), rs.getString(2), rs.getString(3)});
        if (rows.isEmpty() || isBlank(rows.get(0)[2]) || isBlank(rows.get(0)[0])) {
            return null;
        }
        String[] row = rows.get(0);
        ObjectNode node = objectMapper.createObjectNode();
        node.put("sid", sid);
        node.put("fishId", fishId);
        node.set("plot", parse(row[0]));
        node.set("calendar", isBlank(row[1]) ? objectMapper.createArrayNode() : parse(row[1]));
        node.set("week", parse(row[2]));
        return node;
    }

    @SuppressWarnings("unused")
    public JsonNode plotFallback(int sid, String fishId, Throwable ex) {
        throw new RuntimeException("SQL forecast-plot query failed for station " + sid, ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "reasoningFallback")
    public JsonNode reasoning(int sid, String fishId, int day) {
        List<String> rows = jdbc.query(REASONING_SQL, ps -> {
            ps.setInt(1, sid);
            ps.setString(2, fishId);
            ps.setInt(3, day);
        }, (rs, i) -> rs.getString(1));
        return parseFirst(rows);
    }

    @SuppressWarnings("unused")
    public JsonNode reasoningFallback(int sid, String fishId, int day, Throwable ex) {
        throw new RuntimeException("SQL forecast-reasoning query failed for station " + sid, ex);
    }

    private JsonNode parseFirst(List<String> rows) {
        String json = rows.isEmpty() ? null : rows.get(0);
        return isBlank(json) ? null : parse(json);
    }

    private static boolean isBlank(String s) {
        return s == null || s.isBlank();
    }

    private JsonNode parse(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Database returned malformed forecast JSON", e);
        }
    }
}
