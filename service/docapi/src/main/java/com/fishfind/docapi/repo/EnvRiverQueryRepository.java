package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.springframework.jdbc.core.JdbcTemplate;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;

/**
 * {@link RiverQueryRepository} with the Weather tab from env_service (1.45.0, env_service plan step 6c): {@link #weather}
 * reads the water body's name from SQL Server (the fish domain stays there) and its stations, current values and today's
 * weather from env_service {@code /api/v1/env/lakes/{lakeId}/weather}. The other ten methods go to the SQL repository
 * unchanged (it is the proxied bean, so its retry and breaker still apply).
 *
 * <p>The document keeps 1.35.0's shape exactly ({@code dbo.fn_lake_weather_json}, which the app parses):
 * {@code {guid, lakeName, stations:[{sid, mli, lat, lon, locName, science, weather}]}}, stations by mli. {@code science}
 * renders the station's current values as {@code dbo.vScienceView} did (text, rounded, {@code "N/A"} when absent;
 * discharge 0 = {@code "N/A"}), {@code weather} as {@code dbo.fn_station_weather_today} (null when the station has no
 * weather for today). Velocity is always {@code "N/A"}: nothing collects it.</p>
 */
public class EnvRiverQueryRepository implements RiverQueryRepository {

    static final String LAKE_SQL = "SELECT TOP 1 CONVERT(varchar(36), lake_id), lake_name FROM dbo.lake WHERE lake_id = ?";

    private static final DateTimeFormatter DT_107 = DateTimeFormatter.ofPattern("MMM dd, yyyy", Locale.US);
    private static final DateTimeFormatter TM = DateTimeFormatter.ofPattern("HH:mm", Locale.ROOT);
    private static final DateTimeFormatter LOCAL_ISO = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss", Locale.ROOT);

    private final RiverQueryRepository sql;
    private final JdbcTemplate jdbc;
    private final EnvClient env;
    private final ObjectMapper objectMapper;

    public EnvRiverQueryRepository(RiverQueryRepository sql, JdbcTemplate jdbc, EnvClient env, ObjectMapper objectMapper) {
        this.sql = sql;
        this.jdbc = jdbc;
        this.env = env;
        this.objectMapper = objectMapper;
    }

    @Override
    public JsonNode weather(String lakeId) {
        List<String[]> lake = jdbc.query(LAKE_SQL, ps -> ps.setString(1, lakeId),
                (rs, i) -> new String[] {rs.getString(1), rs.getString(2)});
        if (lake.isEmpty()) {
            return null;
        }
        JsonNode data = env.get("/lakes/" + EnvClient.enc(lakeId) + "/weather");
        ObjectNode doc = objectMapper.createObjectNode();
        doc.put("guid", lake.get(0)[0]);
        doc.put("lakeName", lake.get(0)[1]);
        ArrayNode stations = doc.putArray("stations");
        if (data != null) {
            for (JsonNode s : data.path("stations")) {
                stations.add(station(s.path("station"), s.get("current"), s.get("weather")));
            }
        }
        return doc;
    }

    ObjectNode station(JsonNode st, JsonNode current, JsonNode weather) {
        ObjectNode out = objectMapper.createObjectNode();
        out.put("sid", st.path("sid").asInt());
        out.set("mli", st.get("mli"));
        out.set("lat", st.get("lat"));
        out.set("lon", st.get("lon"));
        out.set("locName", st.get("locName"));
        out.set("science", current == null || current.isNull() ? objectMapper.nullNode() : science(st, current));
        out.set("weather", weather == null || weather.isNull() ? objectMapper.nullNode() : today(weather));
        return out;
    }

    /** The current values as dbo.vScienceView rendered them. */
    ObjectNode science(JsonNode st, JsonNode c) {
        ObjectNode s = objectMapper.createObjectNode();
        OffsetDateTime ts = OffsetDateTime.parse(c.path("ts").asText());
        s.set("mli", st.get("mli"));
        s.set("state", st.get("state"));
        s.set("lat", st.get("lat"));
        s.set("lon", st.get("lon"));
        s.put("sid", st.path("sid").asInt());
        s.set("locName", st.get("locName"));
        s.set("country", st.get("country"));
        s.put("stamp", LOCAL_ISO.format(ts));
        s.put("dt", DT_107.format(ts));
        s.put("tm", TM.format(ts));
        JsonNode discharge = c.get("discharge");
        s.put("discharge", discharge == null || discharge.isNull() || round(discharge.asDouble(), 1).signum() == 0
                ? "N/A" : text(round(discharge.asDouble(), 1)));
        s.put("discharge_unit", "m^3/s");
        s.put("elevation", rounded(c.get("level"), 2));
        s.put("elevation_unit", "m");
        s.put("oxygen", rounded(c.get("oxygen"), 3));
        s.put("ph", rounded(c.get("ph"), 2));
        s.put("turbidity", rounded(c.get("turbidity"), 1));
        s.put("velocity", "N/A");
        s.put("velocity_unit", "m/s");
        return s;
    }

    /** One day's weather as dbo.fn_station_weather_today rendered it. */
    ObjectNode today(JsonNode w) {
        ObjectNode t = objectMapper.createObjectNode();
        t.set("dt", w.get("date"));
        t.set("conditions", w.get("conditions"));
        t.set("conditions_long", w.get("conditionsLong"));
        t.set("icon", w.get("icon"));
        t.set("air_temp", w.get("airTempC"));
        t.set("temp_high", w.get("tempHighC"));
        t.set("temp_low", w.get("tempLowC"));
        t.set("humidity", w.get("humidityPct"));
        t.set("wind_speed", w.get("windMaxKmh"));
        t.set("wind_direction", w.get("windDirection"));
        t.set("wind_degree", w.get("windDegree"));
        t.set("precip_chance", w.get("precipChancePct"));
        t.set("precip_amount", w.get("rainTodayMm"));
        return t;
    }

    private static String rounded(JsonNode v, int digits) {
        return v == null || v.isNull() ? "N/A" : text(round(v.asDouble(), digits));
    }

    private static BigDecimal round(double v, int digits) {
        return BigDecimal.valueOf(v).setScale(digits, RoundingMode.HALF_UP);
    }

    /** As SQL's CAST(float AS varchar): no trailing zeros, no exponent. */
    private static String text(BigDecimal v) {
        return v.signum() == 0 ? "0" : v.stripTrailingZeros().toPlainString();
    }

    // ---- the rest goes to SQL Server unchanged ------------------------------------------------------------------

    @Override
    public JsonNode unfished(String country, String state, int river) {
        return sql.unfished(country, state, river);
    }

    @Override
    public JsonNode description(String lakeId) {
        return sql.description(lakeId);
    }

    @Override
    public JsonNode fish(String lakeId) {
        return sql.fish(lakeId);
    }

    @Override
    public JsonNode source(String lakeId) {
        return sql.source(lakeId);
    }

    @Override
    public JsonNode mouth(String lakeId) {
        return sql.mouth(lakeId);
    }

    @Override
    public JsonNode tributaries(String lakeId, int limit) {
        return sql.tributaries(lakeId, limit);
    }

    @Override
    public JsonNode barriers(String lakeId) {
        return sql.barriers(lakeId);
    }

    @Override
    public JsonNode mapPoints(String lakeId, String viewerId, boolean admin) {
        return sql.mapPoints(lakeId, viewerId, admin);
    }

    @Override
    public JsonNode search(RiverSearchCriteria criteria) {
        return sql.search(criteria);
    }
}
