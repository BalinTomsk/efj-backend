package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.ArrayList;
import java.util.List;

/**
 * The two reads of {@code /news/near} (1.34.0). The tagged stories come from csnews-env
 * ({@code GET /api/v1/csnews/tagged}, since docapi 1.44.0 -- docapi has no MySQL access; the same narrow columns,
 * never a photo or paragraph column) and the distances from SQL Server ({@code dbo.fn_lakes_near_json},
 * envfish-db 2026-11-15). Only the SQL Server read goes through {@code sqlRetry}/{@code sqlBreaker}; the news read
 * has the {@code csnewsBreaker} inside {@link CsNewsClient}, so a news outage never trips the SQL breaker.
 */
public class JdbcNewsNearRepository implements NewsNearRepository {

    static final String NEAR_SQL = "SELECT dbo.fn_lakes_near_json(?, ?, ?, ?)";

    private final JdbcTemplate sqlServer;
    private final CsNewsClient csnews;
    private final ObjectMapper objectMapper;

    public JdbcNewsNearRepository(JdbcTemplate sqlServer, CsNewsClient csnews, ObjectMapper objectMapper) {
        this.sqlServer = sqlServer;
        this.csnews = csnews;
        this.objectMapper = objectMapper;
    }

    @Override
    public List<TaggedNews> taggedNews(int limit) {
        JsonNode data = csnews.get("/tagged?limit=" + limit);
        if (data == null || !data.isArray()) {
            throw new CsNewsUnavailableException("csnews-env /tagged returned no list", null);
        }
        List<TaggedNews> out = new ArrayList<>(data.size());
        for (JsonNode n : data) {
            out.add(new TaggedNews(
                    n.path("newsId").asText(null),
                    n.path("title").asText(null),
                    n.path("source").asText(null),
                    n.path("stamp").asText(null),
                    n.path("country").asText(null),
                    n.path("lakeId").asText(null)));
        }
        return out;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "lakesNearFallback")
    public JsonNode lakesNear(String lakeIdsJson, double lat, double lon, int radiusKm) {
        List<String> rows = sqlServer.query(NEAR_SQL, ps -> {
            ps.setString(1, lakeIdsJson);
            ps.setDouble(2, lat);
            ps.setDouble(3, lon);
            ps.setDouble(4, radiusKm);
        }, (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        if (json == null || json.isBlank()) {
            // The controller sends a validated point and radius, so NULL is a contract break, not "none near".
            throw new IllegalStateException("fn_lakes_near_json returned NULL for a validated point");
        }
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Database returned malformed lakes-near JSON", e);
        }
    }

    @SuppressWarnings("unused")
    public JsonNode lakesNearFallback(String lakeIdsJson, double lat, double lon, int radiusKm, Throwable ex) {
        throw new RuntimeException("SQL lakes-near query failed for " + lat + "," + lon, ex);
    }
}
