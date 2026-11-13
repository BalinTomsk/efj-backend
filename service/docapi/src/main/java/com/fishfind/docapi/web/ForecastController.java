package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.ForecastQueryRepository;
import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Locale;
import java.util.concurrent.TimeUnit;

/**
 * The website's forecast pages as JSON for the envfish-droid Forecast tab (1.31.0). Each endpoint returns the
 * document of the database function the page itself uses, so the app shows the website's numbers:
 * <ul>
 *   <li>{@code GET /api/v1/forecast/stations?fish=&lat=&lon=&radius=&country=&limit=} — the Planning.aspx map
 *       (stations with water, weather and the fish; {@code today} is the value the map plots) within a radius,
 *       nearest first ({@code dbo.fn_forecast_stations_json} over {@code dbo.fn_map_location});</li>
 *   <li>{@code GET /api/v1/forecast/plot/{sid}?fish=} — what Plot.aspx draws ({@code dbo.fn_forecast_plot_json} and
 *       the {@code dbo.fn_plot_weather} calendar) plus the 7-day score week from the Reasoning tab;</li>
 *   <li>{@code GET /api/v1/forecast/reasoning/{sid}?fish=&day=} — the Reasoning tab's facts
 *       ({@code dbo.fn_fish_reasoning_json}), today or up to 6 days ahead.</li>
 * </ul>
 * Every argument is validated before the repository is called, so bad input is a 400 and never a SQL error on the
 * shared {@code sqlBreaker}. Responses carry {@code Cache-Control: private, max-age=300} and are held in memory for
 * the same 5 minutes ({@code CachingForecastQueryRepository}).
 */
@RestController
@RequestMapping("/api/v1/forecast")
public class ForecastController {

    static final int DEFAULT_RADIUS_KM = 100;
    static final int MAX_RADIUS_KM = 500;
    static final int DEFAULT_LIMIT = 50;
    static final int MAX_LIMIT = 200;
    static final int MAX_DAY = 6;

    private static final CacheControl CACHE = CacheControl.maxAge(300, TimeUnit.SECONDS).cachePrivate();

    private final ForecastQueryRepository repository;

    public ForecastController(ForecastQueryRepository repository) {
        this.repository = repository;
    }

    /**
     * Forecast-map stations near a point for one fish, nearest first.
     *
     * @param fish    the fish GUID (required)
     * @param lat     -90..90 (required); rounded to 0.01° (~1 km), echoed in the document
     * @param lon     -180..180 (required); rounded to 0.01°
     * @param radius  km, default {@value #DEFAULT_RADIUS_KM}, capped at {@value #MAX_RADIUS_KM}; garbage ⇒ default
     * @param country {@code CA} or {@code US}; absent ⇒ both
     * @param limit   default {@value #DEFAULT_LIMIT}, capped at {@value #MAX_LIMIT}; garbage ⇒ default
     * @return {@code {fishId, fish, lat, lon, radiusKm, country, limit, total, stations:[{sid, name, lat, lon,
     *         country, state, county, today, marker, distanceKm}]}}; an empty {@code stations} (never 404) when none
     * @throws InvalidDocumentException  missing/malformed fish, lat, lon, or a country other than CA/US (→ 400)
     * @throws DocumentNotFoundException unknown fish (→ 404)
     */
    @GetMapping("/stations")
    public ResponseEntity<ApiResponse<JsonNode>> stations(
            @RequestParam(required = false) String fish,
            @RequestParam(required = false) String lat,
            @RequestParam(required = false) String lon,
            @RequestParam(required = false) String radius,
            @RequestParam(required = false) String country,
            @RequestParam(required = false) String limit) {
        String fishId = requireFish(fish);
        double la = round2(requireCoordinate(lat, "lat", 90));
        double lo = round2(requireCoordinate(lon, "lon", 180));
        int r = clamp(radius, DEFAULT_RADIUS_KM, MAX_RADIUS_KM);
        int n = clamp(limit, DEFAULT_LIMIT, MAX_LIMIT);
        String c = parseCountry(country);
        JsonNode doc = repository.stations(fishId, la, lo, r, c, n);
        if (doc == null) {
            throw new DocumentNotFoundException(DocumentType.FISH, fishId);
        }
        return ok(doc);
    }

    /**
     * Plot.aspx for one station and fish: {@code plot} (dates −15…+7 days with discharge, level, precipitation,
     * temperature, turbidity — the chart), {@code calendar} (the 23 day/weather cells), {@code week} (7 days of
     * the fish's score, day 0 = the map's {@code today}).
     *
     * @throws InvalidDocumentException  sid not a positive integer, fish missing/malformed (→ 400)
     * @throws DocumentNotFoundException unknown station, or the fish is not listed there (→ 404)
     */
    @GetMapping("/plot/{sid}")
    public ResponseEntity<ApiResponse<JsonNode>> plot(@PathVariable String sid,
                                                      @RequestParam(required = false) String fish) {
        int s = requireSid(sid);
        String fishId = requireFish(fish);
        JsonNode doc = repository.plot(s, fishId);
        if (doc == null) {
            throw new DocumentNotFoundException(DocumentType.STATION, s + " / fish " + fishId);
        }
        return ok(doc);
    }

    /**
     * The Reasoning tab's facts for one station, fish and day: {@code today} = base × season × moon × oxygen with
     * what each factor came from (moon, month, spawn, water, ranges, weather) and the 7-day {@code week}.
     *
     * @param day 0..{@value #MAX_DAY} days ahead, default 0 (today)
     * @throws InvalidDocumentException  bad sid, fish or day (→ 400)
     * @throws DocumentNotFoundException unknown station, or the fish is not listed there (→ 404)
     */
    @GetMapping("/reasoning/{sid}")
    public ResponseEntity<ApiResponse<JsonNode>> reasoning(@PathVariable String sid,
                                                           @RequestParam(required = false) String fish,
                                                           @RequestParam(required = false) String day) {
        int s = requireSid(sid);
        String fishId = requireFish(fish);
        int d = parseDay(day);
        JsonNode doc = repository.reasoning(s, fishId, d);
        if (doc == null) {
            throw new DocumentNotFoundException(DocumentType.STATION, s + " / fish " + fishId);
        }
        return ok(doc);
    }

    private static ResponseEntity<ApiResponse<JsonNode>> ok(JsonNode doc) {
        return ResponseEntity.ok().cacheControl(CACHE).body(ApiResponse.ok(doc));
    }

    private static String requireFish(String value) {
        if (value == null || value.isBlank()) {
            throw new InvalidDocumentException("fish is required (a fish GUID)");
        }
        try {
            return RiverController.normalizeGuid(value);
        } catch (InvalidDocumentException ex) {
            throw new InvalidDocumentException("fish is not a valid GUID");
        }
    }

    private static int requireSid(String value) {
        try {
            int s = Integer.parseInt(value.trim());
            if (s > 0) {
                return s;
            }
        } catch (NumberFormatException ignored) {
            // falls through to the 400
        }
        throw new InvalidDocumentException("sid must be a positive integer station id");
    }

    private static double requireCoordinate(String value, String name, double max) {
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

    static double round2(double v) {
        return Math.round(v * 100.0) / 100.0;
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

    private static String parseCountry(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        String c = value.trim().toUpperCase(Locale.ROOT);
        if (!c.equals("CA") && !c.equals("US")) {
            throw new InvalidDocumentException("country must be CA or US");
        }
        return c;
    }

    private static int parseDay(String value) {
        if (value == null || value.isBlank()) {
            return 0;
        }
        try {
            int d = Integer.parseInt(value.trim());
            if (d >= 0 && d <= MAX_DAY) {
                return d;
            }
        } catch (NumberFormatException ignored) {
            // falls through to the 400
        }
        throw new InvalidDocumentException("day must be 0.." + MAX_DAY);
    }
}
