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
 * JDBC river query repository backed by {@code dbo.fn_river_unfished_json} /
 * {@code dbo.fn_lake_view_json}. Guarded by Resilience4j retry + circuit breaker, like every
 * other repository bean here.
 */
public class JdbcRiverQueryRepository implements RiverQueryRepository {

    /** Next un-processed water body as a single JSON document. */
    static final String UNFISHED_SQL = "SELECT dbo.fn_river_unfished_json(?, ?, ?)";

    /**
     * Full description document for one water body (name/stats/source/mouth/fish/gallery). Same
     * function the admin "Save JSON" View-tab export uses ({@code Editor/HandlerImage.ashx?lakejson=&
     * tab=view}); already live in {@code envfish-db} — no new DB object for this endpoint.
     */
    static final String DESCRIPTION_SQL = "SELECT dbo.fn_lake_view_json(?)";

    /**
     * Assigned-species document for one water body. Same function the admin "Save JSON" Fishing-tab
     * export uses ({@code Editor/EditLakeFish.aspx} → {@code HandlerImage.ashx?lakejson=&tab=fishing});
     * already live in {@code envfish-db} — no new DB object for this endpoint.
     */
    static final String FISH_SQL = "SELECT dbo.fn_lake_fishing_json(?)";

    /**
     * Source-tab document (the {@code side = 16} Tributaries link). Same function the admin "Save
     * JSON" Source-tab export uses ({@code Editor/EditLakeLink.aspx?Type=16} →
     * {@code HandlerImage.ashx?lakejson=&tab=source}); already live in {@code envfish-db}.
     */
    static final String SOURCE_SQL = "SELECT dbo.fn_lake_source_json(?)";

    /** Mouth-tab document ({@code side = 32}), same shape as {@link #SOURCE_SQL}. */
    static final String MOUTH_SQL = "SELECT dbo.fn_lake_mouth_json(?)";

    /**
     * Water-body search and ranking by name part / either GUID / either CGNDB code / state id / station MLI /
     * country / state, filtered by type, sorted and paged, as one {@code {total, limit, offset, items}} document.
     * The function picks the most selective supplied key to drive the lookup.
     */
    static final String SEARCH_SQL = "SELECT dbo.fn_river_search_json(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcRiverQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "unfishedFallback")
    public JsonNode unfished(String country, String state, int river) {
        List<String> rows = jdbc.query(
                UNFISHED_SQL,
                ps -> {
                    ps.setString(1, country);
                    ps.setString(2, state);
                    ps.setInt(3, river);
                },
                (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "descriptionFallback")
    public JsonNode description(String lakeId) {
        List<String> rows = jdbc.query(DESCRIPTION_SQL, ps -> ps.setString(1, lakeId), (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    /** Circuit-breaker fallback for {@link #unfished}. */
    @SuppressWarnings("unused")
    public JsonNode unfishedFallback(String country, String state, int river, Throwable ex) {
        throw new RuntimeException("SQL river-unfished query failed", ex);
    }

    /** Circuit-breaker fallback for {@link #description}. */
    @SuppressWarnings("unused")
    public JsonNode descriptionFallback(String lakeId, Throwable ex) {
        throw new RuntimeException("SQL river-description query failed for id " + lakeId, ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fishFallback")
    public JsonNode fish(String lakeId) {
        List<String> rows = jdbc.query(FISH_SQL, ps -> ps.setString(1, lakeId), (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    /** Circuit-breaker fallback for {@link #fish}. */
    @SuppressWarnings("unused")
    public JsonNode fishFallback(String lakeId, Throwable ex) {
        throw new RuntimeException("SQL river-fish query failed for id " + lakeId, ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "sourceFallback")
    public JsonNode source(String lakeId) {
        List<String> rows = jdbc.query(SOURCE_SQL, ps -> ps.setString(1, lakeId), (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    /** Circuit-breaker fallback for {@link #source}. */
    @SuppressWarnings("unused")
    public JsonNode sourceFallback(String lakeId, Throwable ex) {
        throw new RuntimeException("SQL river-source query failed for id " + lakeId, ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "mouthFallback")
    public JsonNode mouth(String lakeId) {
        List<String> rows = jdbc.query(MOUTH_SQL, ps -> ps.setString(1, lakeId), (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    /** Circuit-breaker fallback for {@link #mouth}. */
    @SuppressWarnings("unused")
    public JsonNode mouthFallback(String lakeId, Throwable ex) {
        throw new RuntimeException("SQL river-mouth query failed for id " + lakeId, ex);
    }

    /** The water bodies flowing into one water body (1.22.0); new in {@code envfish-db}, not a reused export. */
    static final String TRIBUTARIES_SQL = "SELECT dbo.fn_lake_inflows_json(?, ?)";

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "tributariesFallback")
    public JsonNode tributaries(String lakeId, int limit) {
        List<String> rows = jdbc.query(
                TRIBUTARIES_SQL,
                ps -> {
                    ps.setString(1, lakeId);
                    ps.setInt(2, limit);
                },
                (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    /** Circuit-breaker fallback for {@link #tributaries}. */
    @SuppressWarnings("unused")
    public JsonNode tributariesFallback(String lakeId, int limit, Throwable ex) {
        throw new RuntimeException("SQL river-tributaries query failed for id " + lakeId, ex);
    }

    /** The waterfalls and dams of one water body (1.24.0); live on docapi's database since envfish-db #70. */
    static final String BARRIERS_SQL = "SELECT dbo.fn_lake_barriers_json(?)";

    /**
     * Fishing spots and visible catch logs with a position, for the app's map (1.38.0): the same two sources as the
     * website's river map (wfRiverViewer.aspx GetFishPoints / GetCatchMemoPoints), on existing objects only. Parameters:
     * viewer (for {@code mine}), viewer, admin bit, lake. Run on a real SQL Server (local envionx) before release.
     */
    static final String MAP_POINTS_SQL = """
            SET NOCOUNT ON;
            SELECT
                l.Lake_id AS guid,
                l.lake_name AS lakeName,
                JSON_QUERY(COALESCE((SELECT s.spot_lat AS lat, s.spot_lon AS lon FROM dbo.Spot s
                    WHERE s.lake_Id = l.Lake_id AND s.spot_lat IS NOT NULL AND s.spot_lon IS NOT NULL
                    FOR JSON PATH), '[]')) AS spots,
                JSON_QUERY(COALESCE((SELECT c.catch_memo_id AS catchLogId, c.catch_memo_fish_id AS fishId,
                        c.catch_memo_species AS species, c.catch_memo_title AS title,
                        CONVERT(char(10), c.catch_memo_catch_date, 23) AS catchDate,
                        c.catch_memo_lat AS lat, c.catch_memo_lon AS lon,
                        CAST(CASE WHEN c.catch_memo_userid = ? THEN 1 ELSE 0 END AS bit) AS mine
                    FROM dbo.fn_catch_memo_list(l.Lake_id, ?, ?) c
                    WHERE c.catch_memo_lat IS NOT NULL AND c.catch_memo_lon IS NOT NULL
                    ORDER BY c.catch_memo_catch_date DESC, c.catch_memo_created DESC
                    FOR JSON PATH), '[]')) AS catches
            FROM dbo.Lake l WHERE l.Lake_id = ?
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER""";

    /**
     * Not served here: the Weather tab comes from env_service ({@link EnvRiverQueryRepository}, 1.45.0). The SQL Server
     * read ({@code dbo.fn_lake_weather_json}) was removed in 1.45.1, since its tables are no longer written.
     */
    @Override
    public JsonNode weather(String lakeId) {
        throw new UnsupportedOperationException("The Weather tab is served by env_service (EnvRiverQueryRepository)");
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "barriersFallback")
    public JsonNode barriers(String lakeId) {
        List<String> rows = jdbc.query(BARRIERS_SQL, ps -> ps.setString(1, lakeId), (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parse(json);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "mapPointsFallback")
    public JsonNode mapPoints(String lakeId, String viewerId, boolean admin) {
        // FOR JSON splits a long document over several rows of one column: join them.
        List<String> rows = jdbc.query(MAP_POINTS_SQL, ps -> {
            ps.setString(1, viewerId);
            ps.setString(2, viewerId);
            ps.setBoolean(3, admin);
            ps.setString(4, lakeId);
        }, (rs, i) -> rs.getString(1));
        String json = String.join("", rows);
        return json.isBlank() ? null : parse(json);
    }

    /** Circuit-breaker fallback for {@link #mapPoints}. */
    @SuppressWarnings("unused")
    public JsonNode mapPointsFallback(String lakeId, String viewerId, boolean admin, Throwable ex) {
        throw new RuntimeException("SQL river-map-points query failed for id " + lakeId, ex);
    }

    /** Circuit-breaker fallback for {@link #barriers}. */
    @SuppressWarnings("unused")
    public JsonNode barriersFallback(String lakeId, Throwable ex) {
        throw new RuntimeException("SQL river-barriers query failed for id " + lakeId, ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "searchFallback")
    public JsonNode search(RiverSearchCriteria c) {
        List<String> rows = jdbc.query(
                SEARCH_SQL,
                ps -> {
                    ps.setString(1, c.name());
                    ps.setString(2, c.guid());
                    ps.setString(3, c.cgndb());
                    ps.setString(4, c.stateId());
                    ps.setString(5, c.mli());
                    ps.setString(6, c.country());
                    ps.setString(7, c.state());
                    if (c.locType() == null) {
                        ps.setNull(8, Types.INTEGER);
                    } else {
                        ps.setInt(8, c.locType());
                    }
                    ps.setString(9, c.sort());
                    ps.setInt(10, c.offset());
                    ps.setInt(11, c.limit());
                },
                (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? emptySearch(objectMapper, c) : parse(json);
    }

    /** The {@link #search} document for no matches. */
    static JsonNode emptySearch(ObjectMapper objectMapper, RiverSearchCriteria c) {
        ObjectNode out = objectMapper.createObjectNode();
        out.put("total", 0);
        out.put("limit", c.limit());
        out.put("offset", c.offset());
        out.putArray("items");
        return out;
    }

    /** Circuit-breaker fallback for {@link #search}. */
    @SuppressWarnings("unused")
    public JsonNode searchFallback(RiverSearchCriteria criteria, Throwable ex) {
        throw new RuntimeException("SQL river-search query failed", ex);
    }

    private JsonNode parse(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("River JSON returned by the database is not valid JSON", ex);
        }
    }
}
