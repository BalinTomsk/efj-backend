package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fishfind.docapi.repo.NewsNearRepository;
import com.fishfind.docapi.repo.NewsNearRepository.TaggedNews;
import com.fishfind.docapi.repo.TtlLru;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Clock;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.TimeUnit;

/**
 * News near a point (1.34.0, envfish-droid P1-09: the app's Local news tab).
 * <ul>
 *   <li>{@code GET /api/v1/news/near?lat=&lon=&radius=&limit=} — published stories tagged with a water body
 *       ({@code news.lake_id}, MySQL) whose water body lies within {@code radius} km ({@code dbo.fn_lakes_near_json},
 *       SQL Server: the nearer of its source and mouth), nearest first, then newest.</li>
 * </ul>
 * Only the newest {@value #TAGGED_WINDOW} tagged stories are considered. A story without a water body is never "near".
 * The literal {@code /near} path wins over {@code NewsController}'s {@code /{id}}. Arguments are validated before any
 * SQL; {@code lat}/{@code lon} are rounded to 0.01° (about 1 km) so nearby callers share a cache entry. The tagged
 * list and each answer are held {@value #TTL_MINUTES} minutes; responses carry {@code Cache-Control: private,
 * max-age=300}.
 */
@RestController
@RequestMapping("/api/v1/news")
public class NewsNearController {

    static final int DEFAULT_RADIUS_KM = 100;
    static final int MAX_RADIUS_KM = 500;
    static final int DEFAULT_LIMIT = 20;
    static final int MAX_LIMIT = 100;
    static final int TAGGED_WINDOW = 2000;
    static final int TTL_MINUTES = 5;

    private static final CacheControl CACHE = CacheControl.maxAge(300, TimeUnit.SECONDS).cachePrivate();
    private static final long TTL_MILLIS = TTL_MINUTES * 60_000L;

    /** One story near the point: the story, its water body and how far that is. */
    public record NewsNearItem(String newsId, String title, String source, String stamp, String country,
                               String lakeId, String lakeName, double distanceKm) {}

    /** The answer: the (rounded) point and window asked for, how many stories matched, and the nearest of them. */
    public record NewsNearPage(double lat, double lon, int radiusKm, int limit, int total, List<NewsNearItem> items) {}

    private final NewsNearRepository repository;
    private final ObjectMapper objectMapper;
    private final TtlLru<List<TaggedNews>> tagged;
    private final TtlLru<NewsNearPage> answers;

    @Autowired
    public NewsNearController(NewsNearRepository repository, ObjectMapper objectMapper) {
        this(repository, objectMapper, Clock.systemUTC());
    }

    NewsNearController(NewsNearRepository repository, ObjectMapper objectMapper, Clock clock) {
        this.repository = repository;
        this.objectMapper = objectMapper;
        this.tagged = new TtlLru<>(1, TTL_MILLIS, clock);
        this.answers = new TtlLru<>(300, TTL_MILLIS, clock);
    }

    /**
     * @param lat    -90..90, required; rounded to 0.01°
     * @param lon    -180..180, required; rounded to 0.01°
     * @param radius km, default {@value #DEFAULT_RADIUS_KM}, capped at {@value #MAX_RADIUS_KM}; garbage ⇒ default
     * @param limit  stories, default {@value #DEFAULT_LIMIT}, capped at {@value #MAX_LIMIT}; garbage ⇒ default
     * @return {@code {lat, lon, radiusKm, limit, total, items:[{newsId, title, source, stamp, country, lakeId,
     *         lakeName, distanceKm}]}}; empty {@code items} (never 404) when nothing is near
     * @throws InvalidDocumentException a missing or out-of-range lat/lon (→ 400)
     */
    @GetMapping("/near")
    public ResponseEntity<ApiResponse<NewsNearPage>> near(@RequestParam(required = false) String lat,
                                                          @RequestParam(required = false) String lon,
                                                          @RequestParam(required = false) String radius,
                                                          @RequestParam(required = false) String limit) {
        double la = ForecastController.round2(coordinate(lat, "lat", 90));
        double lo = ForecastController.round2(coordinate(lon, "lon", 180));
        int r = clamp(radius, DEFAULT_RADIUS_KM, MAX_RADIUS_KM);
        int n = clamp(limit, DEFAULT_LIMIT, MAX_LIMIT);
        NewsNearPage page = answers.get(la + "|" + lo + "|" + r + "|" + n, () -> compute(la, lo, r, n));
        return ResponseEntity.ok().cacheControl(CACHE).body(ApiResponse.ok(page));
    }

    private NewsNearPage compute(double lat, double lon, int radiusKm, int limit) {
        List<TaggedNews> stories = tagged.get("all", () -> List.copyOf(repository.taggedNews(TAGGED_WINDOW)));
        Set<String> lakeIds = new LinkedHashSet<>();
        for (TaggedNews s : stories) {
            lakeIds.add(s.lakeId().trim().toLowerCase(Locale.ROOT));
        }
        if (lakeIds.isEmpty()) {
            return new NewsNearPage(lat, lon, radiusKm, limit, 0, List.of());
        }
        ArrayNode ids = objectMapper.createArrayNode();
        lakeIds.forEach(ids::add);
        JsonNode near = repository.lakesNear(ids.toString(), lat, lon, radiusKm);

        Map<String, JsonNode> byLake = new HashMap<>();
        for (JsonNode lake : near) {
            byLake.put(lake.path("lakeId").asText().toLowerCase(Locale.ROOT), lake);
        }
        List<NewsNearItem> matches = new ArrayList<>();
        for (TaggedNews s : stories) {
            JsonNode lake = byLake.get(s.lakeId().trim().toLowerCase(Locale.ROOT));
            if (lake != null) {
                matches.add(new NewsNearItem(s.newsId(), s.title(), s.source(), s.stamp(), s.country(),
                        lake.path("lakeId").asText(), lake.path("lakeName").asText(null),
                        lake.path("distanceKm").asDouble()));
            }
        }
        // Nearest water body first; for the same distance, the newest story (the stories arrive newest first and
        // List.sort is stable, so equal distances keep that order).
        matches.sort(Comparator.comparingDouble(NewsNearItem::distanceKm));
        List<NewsNearItem> items = List.copyOf(matches.subList(0, Math.min(limit, matches.size())));
        return new NewsNearPage(lat, lon, radiusKm, limit, matches.size(), items);
    }

    private static double coordinate(String value, String name, double max) {
        if (value == null || value.isBlank()) {
            throw new InvalidDocumentException(name + " is required");
        }
        try {
            double v = Double.parseDouble(value.trim());
            if (Double.isFinite(v) && v >= -max && v <= max) {
                return v;
            }
        } catch (NumberFormatException ignored) {
            // falls through to the 400
        }
        throw new InvalidDocumentException(name + " must be a number between -" + (int) max + " and " + (int) max);
    }

    private static int clamp(String value, int dflt, int max) {
        if (value == null) {
            return dflt;
        }
        try {
            int n = (int) Math.round(Double.parseDouble(value.trim()));
            return n < 1 ? dflt : Math.min(n, max);
        } catch (NumberFormatException ex) {
            return dflt;
        }
    }
}
