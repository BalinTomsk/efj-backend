package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Query repository for river/water-body lookups, backed by SQL functions in the DB. Same repository
 * pattern as {@link NewsQueryRepository} / {@link FishQueryRepository}.
 */
public interface RiverQueryRepository {

    /**
     * The next un-processed water body of a given type in a state: no fish assigned and not flagged
     * "No Fish". Duplicates the frontend {@code Resources/wbUnFish.aspx} JSON endpoint used by the
     * add-fish tooling — backed by {@code dbo.fn_river_unfished_json}.
     *
     * @param country ISO-2 country code (echoed only; the query filters by state, not country)
     * @param state   ISO-2 state/province code (the actual filter)
     * @param river   locType value (2 = river)
     * @return a JSON object {@code { found, country, state, river, lake_id, lake_name, mouth_name,
     *         CGNDB, throwing }} (fields null when {@code found} is false)
     */
    JsonNode unfished(String country, String state, int river);

    /**
     * The full description document for one water body — name/alt names, description text, physical
     * stats, source/mouth detail, assigned fish, and the photo gallery (base64) — the same export the
     * portal's admin "Save JSON" (View tab) uses. Backed by {@code dbo.fn_lake_view_json}.
     *
     * @param lakeId the water body's GUID
     * @return the document as a JSON tree, or {@code null} if no water body exists for the id
     */
    JsonNode description(String lakeId);

    /**
     * The assigned-species document for one water body — every {@code lake_fish} row (name, latin,
     * conservation status, last-catch, external link), the same export the portal's admin "Save JSON"
     * (Fishing tab, {@code EditLakeFish.aspx}) uses. Backed by {@code dbo.fn_lake_fishing_json}.
     *
     * @param lakeId the water body's GUID
     * @return the document as a JSON tree, or {@code null} if no water body exists for the id
     */
    JsonNode fish(String lakeId);

    /**
     * The Source-tab document for one water body — the {@code dbo.Tributaries} link row(s) where
     * {@code side = 16}, with the linked point's name/id and its location fields. Same export the
     * portal's admin "Save JSON" (Source tab, {@code EditLakeLink.aspx?Type=16}) uses. Backed by
     * {@code dbo.fn_lake_source_json}.
     *
     * @param lakeId the water body's GUID
     * @return the document as a JSON tree, or {@code null} if no water body exists for the id
     */
    JsonNode source(String lakeId);

    /**
     * The Mouth-tab document for one water body — same shape as {@link #source(String)} but for the
     * {@code side = 32} link row(s) ({@code EditLakeLink.aspx?Type=32}). Backed by
     * {@code dbo.fn_lake_mouth_json}.
     *
     * @param lakeId the water body's GUID
     * @return the document as a JSON tree, or {@code null} if no water body exists for the id
     */
    JsonNode mouth(String lakeId);
}
