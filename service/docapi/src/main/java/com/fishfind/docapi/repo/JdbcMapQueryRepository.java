package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;

/**
 * JDBC map repository (1.33.0): one call of {@code dbo.fn_shapes_bbox_geojson} (envfish-db 2026-11-14), which finds
 * the shapes through the {@code SIDX_Lake_Shape} spatial index. Guarded by the shared {@code sqlRetry}/{@code sqlBreaker};
 * {@link CachingMapQueryRepository} sits in front of it.
 */
public class JdbcMapQueryRepository implements MapQueryRepository {

    static final String SHAPES_SQL = "SELECT dbo.fn_shapes_bbox_geojson(?, ?, ?, ?, ?, ?)";

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcMapQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "shapesFallback")
    public JsonNode shapes(double west, double south, double east, double north, int zoom, int limit) {
        List<String> rows = jdbc.query(SHAPES_SQL, ps -> {
            ps.setDouble(1, west);
            ps.setDouble(2, south);
            ps.setDouble(3, east);
            ps.setDouble(4, north);
            ps.setInt(5, zoom);
            ps.setInt(6, limit);
        }, (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        if (json == null || json.isBlank()) {
            // The controller sends only boxes the function accepts, so NULL here is a contract break, not a 404.
            throw new IllegalStateException("fn_shapes_bbox_geojson returned NULL for a validated box");
        }
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Database returned malformed shapes GeoJSON", e);
        }
    }

    @SuppressWarnings("unused")
    public JsonNode shapesFallback(double west, double south, double east, double north, int zoom, int limit,
                                   Throwable ex) {
        throw new RuntimeException("SQL map-shapes query failed for box " + west + "," + south + "," + east + ","
                + north + " zoom " + zoom, ex);
    }
}
