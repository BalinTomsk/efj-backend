package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Read-only map queries behind {@code /api/v1/map/*} (1.33.0, envfish-droid P0-10).
 * Arguments arrive validated and normalized by {@code MapController}.
 */
public interface MapQueryRepository {

    /**
     * The water-body shapes ({@code dbo.Lake_Shape}: lake outlines, river lines) crossing a box, simplified for
     * {@code zoom} -- {@code dbo.fn_shapes_bbox_geojson}.
     *
     * @param west  -180..180, less than {@code east}
     * @param south -85..85, less than {@code north}
     * @param east  -180..180
     * @param north -85..85
     * @param zoom  0..22
     * @param limit 1..2000 features, longest first
     * @return {@code {type:"FeatureCollection", bbox, zoom, toleranceM, truncated, features}}
     */
    JsonNode shapes(double west, double south, double east, double north, int zoom, int limit);
}
