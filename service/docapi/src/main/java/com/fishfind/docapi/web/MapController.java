package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.repo.MapQueryRepository;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.concurrent.TimeUnit;

/**
 * Map data for the envfish-droid app (1.33.0, TODO P0-10).
 * <ul>
 *   <li>{@code GET /api/v1/map/shapes?bbox=west,south,east,north&zoom=&limit=} — the water-body shapes
 *       ({@code dbo.Lake_Shape}: lake outlines, river lines) crossing the box as a GeoJSON FeatureCollection,
 *       each shape simplified to one screen pixel at {@code zoom} and left out when under two pixels long
 *       ({@code dbo.fn_shapes_bbox_geojson}).</li>
 * </ul>
 * Every argument is validated before the repository is called (a 400, never a SQL error on the shared
 * {@code sqlBreaker}). A box may span at most {@value #MAX_SPAN_DEG}° and at most {@value #MAX_PIXELS} pixels at the
 * zoom (a phone screen is about 4 tiles across), so one request stays small. Responses carry
 * {@code Cache-Control: private, max-age=3600} and are held in memory for 30 minutes ({@code CachingMapQueryRepository}).
 */
@RestController
@RequestMapping("/api/v1/map")
public class MapController {

    static final double MAX_SPAN_DEG = 5;
    static final double MAX_LAT = 85;
    static final int MAX_ZOOM = 22;
    /** Widest box, in 256-px web-map pixels at the requested zoom: 16 tiles. */
    static final int MAX_PIXELS = 4096;
    static final int DEFAULT_LIMIT = 500;
    static final int MAX_LIMIT = 2000;

    private static final CacheControl CACHE = CacheControl.maxAge(3600, TimeUnit.SECONDS).cachePrivate();

    private final MapQueryRepository repository;

    public MapController(MapQueryRepository repository) {
        this.repository = repository;
    }

    /**
     * @param bbox  {@code west,south,east,north} in degrees (required); west &lt; east, south &lt; north, latitudes
     *              within ±{@value #MAX_LAT}, at most {@value #MAX_SPAN_DEG}° each way, not across the antimeridian.
     *              Rounded to 1e-5° (about a metre) and echoed in the document.
     * @param zoom  web-map zoom 0..{@value #MAX_ZOOM} (required)
     * @param limit most features, longest first; default {@value #DEFAULT_LIMIT}, capped at {@value #MAX_LIMIT};
     *              garbage ⇒ default
     * @return {@code {type:"FeatureCollection", bbox, zoom, toleranceM, truncated, features:[{type:"Feature",
     *         properties:{id, lakeId, lakeName, locType, kind}, geometry}]}}; an empty {@code features} (never 404)
     * @throws InvalidDocumentException a missing or malformed box or zoom, or a box too big for the zoom (→ 400)
     */
    @GetMapping("/shapes")
    public ResponseEntity<ApiResponse<JsonNode>> shapes(@RequestParam(required = false) String bbox,
                                                        @RequestParam(required = false) String zoom,
                                                        @RequestParam(required = false) String limit) {
        double[] box = parseBox(bbox);
        int z = parseZoom(zoom);
        double pixels = Math.max(box[2] - box[0], box[3] - box[1]) / 360.0 * 256 * Math.pow(2, z);
        if (pixels > MAX_PIXELS) {
            throw new InvalidDocumentException("bbox is too big for zoom " + z + " (" + Math.round(pixels)
                    + " px across, at most " + MAX_PIXELS + "): ask for smaller boxes, e.g. one per tile");
        }
        JsonNode doc = repository.shapes(box[0], box[1], box[2], box[3], z, clamp(limit));
        return ResponseEntity.ok().cacheControl(CACHE).body(ApiResponse.ok(doc));
    }

    static double[] parseBox(String value) {
        if (value == null || value.isBlank()) {
            throw new InvalidDocumentException("bbox is required: west,south,east,north in degrees");
        }
        String[] parts = value.split(",");
        if (parts.length != 4) {
            throw new InvalidDocumentException("bbox must be four numbers: west,south,east,north");
        }
        double[] box = new double[4];
        for (int i = 0; i < 4; i++) {
            try {
                box[i] = round5(Double.parseDouble(parts[i].trim()));
            } catch (NumberFormatException ex) {
                throw new InvalidDocumentException("bbox must be four numbers: west,south,east,north");
            }
            if (!Double.isFinite(box[i])) {
                throw new InvalidDocumentException("bbox must be four numbers: west,south,east,north");
            }
        }
        double w = box[0], s = box[1], e = box[2], n = box[3];
        if (w < -180 || e > 180 || s < -MAX_LAT || n > MAX_LAT) {
            throw new InvalidDocumentException("bbox longitudes must be within -180..180 and latitudes within -"
                    + (int) MAX_LAT + ".." + (int) MAX_LAT);
        }
        if (w >= e || s >= n) {
            throw new InvalidDocumentException("bbox must have west < east and south < north");
        }
        if (e - w > MAX_SPAN_DEG || n - s > MAX_SPAN_DEG) {
            throw new InvalidDocumentException("bbox may span at most " + (int) MAX_SPAN_DEG + " degrees each way");
        }
        return box;
    }

    private static int parseZoom(String value) {
        if (value == null || value.isBlank()) {
            throw new InvalidDocumentException("zoom is required (0.." + MAX_ZOOM + ")");
        }
        try {
            int z = Integer.parseInt(value.trim());
            if (z >= 0 && z <= MAX_ZOOM) {
                return z;
            }
        } catch (NumberFormatException ignored) {
            // falls through to the 400
        }
        throw new InvalidDocumentException("zoom must be an integer 0.." + MAX_ZOOM);
    }

    private static int clamp(String value) {
        if (value == null) {
            return DEFAULT_LIMIT;
        }
        try {
            int n = (int) Math.round(Double.parseDouble(value.trim()));
            return n < 1 ? DEFAULT_LIMIT : Math.min(n, MAX_LIMIT);
        } catch (NumberFormatException ex) {
            return DEFAULT_LIMIT;
        }
    }

    static double round5(double v) {
        return Math.round(v * 100000.0) / 100000.0;
    }
}
