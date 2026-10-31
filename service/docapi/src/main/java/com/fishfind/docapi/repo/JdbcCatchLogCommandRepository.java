package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;

import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.sql.Types;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/**
 * JDBC catch-log command repository backed by {@code dbo.sp_add_catch_memo} and
 * {@code dbo.sp_add_catch_memo_photo}, the procedures the portal's catch log uses. Guarded by the shared
 * {@code sqlBreaker}, matching {@link JdbcRiverFishCommandRepository}.
 *
 * <p>Both procedures fail SILENTLY: an insert for a missing water body still succeeds (there is no foreign
 * key), and a fourth photo is simply not inserted. So the water body is checked here, the species and the
 * photo count by the caller through {@link #fishExists} / {@link #photoCount} (a caller mistake must not
 * count as a breaker failure, so nothing in here throws one), and the memo is read back after the write.
 * Every read goes through a database function ({@code fn_catch_log_write_state}, {@code fn_catch_memo_json}),
 * never a table.
 *
 * <p>{@link #add} may retry: the memo id is the caller's and the procedure updates an existing id, so a second
 * attempt cannot duplicate the memo. {@link #addPhoto} does not retry, because a second attempt would.
 */
public class JdbcCatchLogCommandRepository implements CatchLogCommandRepository {

    static final String ADD_SQL = "EXEC dbo.sp_add_catch_memo @id = ?, @lake_id = ?, @userid = ?, @fish_id = ?, "
            + "@species = ?, @angler = ?, @title = ?, @text = ?, @lat = ?, @lon = ?, @method = ?, @tackle = ?, @lure = ?, "
            + "@catch_date = ?, @weight = ?, @weight_unit = ?, @length = ?, @length_unit = ?, @released = ?, "
            + "@private = ?, @weather_temp = ?, @weather_pressure = ?, @weather_text = ?, @weather_icon = ?, @water_temp = ?, "
            + "@is_admin = 1";

    static final String ADD_PHOTO_SQL = "EXEC dbo.sp_add_catch_memo_photo @memo_id = ?, @userid = ?, @pic = ?, "
            + "@label = N'Catch photo', @ord = ?, @description = ?, @author = ?, @is_admin = 1";

    /** Existence flags and visible photo count in one row (envfish-db), so no table is read directly. */
    static final String STATE_SQL = "SELECT lake_exists, fish_exists, memo_exists, visible_photos "
            + "FROM dbo.fn_catch_log_write_state(?, ?, ?)";

    /** The memo as the portal's own JSON function returns it; {@code @top_photos = 0} embeds no photo. */
    static final String READ_SQL = "SELECT dbo.fn_catch_memo_json(?, 0)";

    /** The station forecast snapshot the portal's catch-log form stamps on a memo. */
    static final String WEATHER_SQL = "SELECT TOP 1 weather_temp, weather_pressure, weather_text, weather_icon, "
            + "water_temp FROM dbo.fn_catch_weather_snapshot(?, ?)";

    private static final Logger log = LoggerFactory.getLogger(JdbcCatchLogCommandRepository.class);

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcCatchLogCommandRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fishExistsFallback")
    public boolean fishExists(String fishId) {
        return state(null, fishId, null).fish();
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "photoCountFallback")
    public int photoCount(String catchLogId) {
        State state = state(null, null, catchLogId);
        return state.memo() ? state.photos() : -1;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "findFallback")
    public CatchLog find(String catchLogId) {
        if (!state(null, null, catchLogId).memo()) {
            return null;
        }
        JsonNode m = memo(catchLogId);
        CatchLog.Weather weather = new CatchLog.Weather(dbl(m, "weather_temp"), dbl(m, "weather_pressure"),
                txt(m, "weather_text"), txt(m, "weather_icon"), dbl(m, "water_temp"));
        String date = txt(m, "catch_date");
        return new CatchLog(catchLogId, txt(m, "lake_id"), txt(m, "userid"), txt(m, "fish_id"), txt(m, "species"),
                txt(m, "angler"), txt(m, "title"), txt(m, "text"), dbl(m, "lat"), dbl(m, "lon"), txt(m, "method"),
                txt(m, "tackle"), txt(m, "lure"), date == null ? null : LocalDateTime.parse(date), dbl(m, "weight"),
                txt(m, "weight_unit"), dbl(m, "length"), txt(m, "length_unit"),
                m.path("catch_memo_released").isNull() || m.path("catch_memo_released").isMissingNode()
                        ? null : m.path("catch_memo_released").asBoolean(),
                m.path("catch_memo_private").asBoolean(false), weather);
    }

    /** Not guarded: like the portal's form, a failed lookup is no forecast, never a save failure. */
    @Override
    public CatchLog.Weather stationWeather(String lakeId, LocalDate date) {
        try {
            List<CatchLog.Weather> rows = jdbc.query(WEATHER_SQL, (rs, n) -> new CatchLog.Weather(
                    dbl(rs, 1), dbl(rs, 2), rs.getString(3), rs.getString(4), dbl(rs, 5)), lakeId, date);
            return rows.isEmpty() ? CatchLog.Weather.NONE : rows.get(0);
        } catch (DataAccessException ex) {
            log.warn("Station weather lookup failed for lake {} on {}", lakeId, date, ex);
            return CatchLog.Weather.NONE;
        }
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "addFallback")
    public JsonNode add(CatchLog log) {
        if (!state(log.lakeId(), null, null).lake()) {
            return null;
        }
        jdbc.update(ADD_SQL, ps -> {
            int i = 1;
            ps.setString(i++, log.id());
            ps.setString(i++, log.lakeId());
            ps.setString(i++, log.userId());
            ps.setString(i++, log.fishId());
            ps.setString(i++, log.species());
            ps.setString(i++, log.angler());
            ps.setString(i++, log.title());
            ps.setString(i++, log.text());
            setDouble(ps, i++, log.lat());
            setDouble(ps, i++, log.lon());
            ps.setString(i++, log.method());
            ps.setString(i++, log.tackle());
            ps.setString(i++, log.lure());
            if (log.catchDate() == null) ps.setNull(i++, Types.TIMESTAMP);
            else ps.setTimestamp(i++, Timestamp.valueOf(log.catchDate()));
            setDouble(ps, i++, log.weight());
            ps.setString(i++, log.weightUnit());
            setDouble(ps, i++, log.length());
            ps.setString(i++, log.lengthUnit());
            if (log.released() == null) ps.setNull(i++, Types.BIT);
            else ps.setBoolean(i++, log.released());
            ps.setBoolean(i++, log.isPrivate());
            CatchLog.Weather w = log.weather();
            setDouble(ps, i++, w.temp());
            setDouble(ps, i++, w.pressure());
            ps.setString(i++, w.text());
            ps.setString(i++, w.icon());
            setDouble(ps, i, w.water());
        });
        return read(log.id(), 0);
    }

    @Override
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "addPhotoFallback")
    public JsonNode addPhoto(String catchLogId, String userId, byte[] jpeg, int ord, String description, String author) {
        State before = state(null, null, catchLogId);
        if (!before.memo()) {
            return null;
        }
        jdbc.update(ADD_PHOTO_SQL, ps -> {
            ps.setString(1, catchLogId);
            ps.setString(2, userId);
            ps.setBytes(3, jpeg);
            ps.setInt(4, ord);
            ps.setString(5, description);
            ps.setString(6, author);
        });
        int after = state(null, null, catchLogId).photos();
        if (after == before.photos()) {
            // The procedure skips the insert silently at MAX_PHOTOS; the caller checked, so this is a race.
            throw new IllegalStateException("sp_add_catch_memo_photo inserted nothing for " + catchLogId);
        }
        return read(catchLogId, after);
    }

    @SuppressWarnings("unused")
    public boolean fishExistsFallback(String fishId, Throwable ex) {
        throw new RuntimeException("SQL species lookup failed for " + fishId, ex);
    }

    @SuppressWarnings("unused")
    public int photoCountFallback(String catchLogId, Throwable ex) {
        throw new RuntimeException("SQL photo count failed for " + catchLogId, ex);
    }

    @SuppressWarnings("unused")
    public CatchLog findFallback(String catchLogId, Throwable ex) {
        throw new RuntimeException("SQL catch-log read failed for " + catchLogId, ex);
    }

    /** Circuit-breaker fallback for {@link #add}. */
    @SuppressWarnings("unused")
    public JsonNode addFallback(CatchLog log, Throwable ex) {
        throw new RuntimeException("SQL catch-log insert failed for lake " + log.lakeId(), ex);
    }

    /** Circuit-breaker fallback for {@link #addPhoto}. */
    @SuppressWarnings("unused")
    public JsonNode addPhotoFallback(String catchLogId, String userId, byte[] jpeg, int ord, String description,
                                     String author, Throwable ex) {
        throw new RuntimeException("SQL catch-log photo insert failed for " + catchLogId, ex);
    }

    private record State(boolean lake, boolean fish, boolean memo, int photos) {
    }

    private State state(String lakeId, String fishId, String memoId) {
        return jdbc.queryForObject(STATE_SQL, (rs, n) -> new State(rs.getBoolean(1), rs.getBoolean(2),
                rs.getBoolean(3), rs.getInt(4)), lakeId, fishId, memoId);
    }

    /** The stored memo plus {@code catchLogId} and {@code imageCount} (the visible photos), for the model. */
    private JsonNode read(String id, int photos) {
        JsonNode node = memo(id);
        if (node instanceof ObjectNode out) {
            out.remove("photos");
            out.put("catchLogId", id);
            out.put("imageCount", photos);
        }
        return node;
    }

    private JsonNode memo(String id) {
        String json = jdbc.queryForObject(READ_SQL, String.class, id);
        if (json == null || json.isBlank()) {
            throw new IllegalStateException("Catch log " + id + " was not found after it was written");
        }
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("Catch-log JSON returned by the database is not valid JSON", ex);
        }
    }

    /** {@code catch_memo_<key>} of the memo JSON as text, {@code null} when absent or JSON null. */
    private static String txt(JsonNode memo, String key) {
        JsonNode v = memo.get("catch_memo_" + key);
        return v == null || v.isNull() ? null : v.asText();
    }

    private static Double dbl(JsonNode memo, String key) {
        JsonNode v = memo.get("catch_memo_" + key);
        return v == null || v.isNull() ? null : v.asDouble();
    }

    private static Double dbl(ResultSet rs, int column) throws SQLException {
        double v = rs.getDouble(column);
        return rs.wasNull() ? null : v;
    }

    private static void setDouble(PreparedStatement ps, int index, Double value) throws SQLException {
        if (value == null) ps.setNull(index, Types.DOUBLE);
        else ps.setDouble(index, value);
    }
}
