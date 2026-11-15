package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

import java.util.List;

/**
 * The two reads behind {@code GET /api/v1/news/near} (1.34.0, envfish-droid P1-09). News lives in MySQL and only knows
 * the water body a story is tagged with ({@code news.lake_id}); where that water body is lives in SQL Server. So the
 * endpoint reads the tagged stories from one and the distances from the other, and joins them in Java.
 */
public interface NewsNearRepository {

    /** A published story tagged with a water body. */
    record TaggedNews(String newsId, String title, String source, String stamp, String country, String lakeId) {}

    /**
     * The newest published stories that carry a water body, newest first.
     *
     * @param limit at most this many
     */
    List<TaggedNews> taggedNews(int limit);

    /**
     * Which of [lakeIdsJson] (a JSON array of GUID strings) lie within {@code radiusKm} of the point, nearest first:
     * {@code dbo.fn_lakes_near_json}.
     *
     * @return {@code [{lakeId, lakeName, state, country, distanceKm}]}, empty when none is near
     */
    JsonNode lakesNear(String lakeIdsJson, double lat, double lon, int radiusKm);
}
