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
     *         CGNDB, CGNDM, throwing }} (fields null when {@code found} is false)
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

    /**
     * The water bodies that flow INTO one water body (1.22.0) — those whose mouth ({@code Tributaries} side 32)
     * is this one, plus the side-4 inflows recorded on it (a lake/pond/reservoir), each listed once. Backed by
     * {@code dbo.fn_lake_inflows_json}.
     *
     * @param lakeId the water body's canonical GUID
     * @param limit  maximum number of items (1..200); {@code total} still counts every inflow
     * @return {@code {guid, lakeName, total, limit, tributaries:[{lakeId, lakeName, altName, frenchName, locType,
     *         CGNDB, CGNDM, link, lat, lon, country, state}]}} by name, or {@code null} if no water body exists for the id
     */
    JsonNode tributaries(String lakeId, int limit);

    /**
     * The waterfalls and dams of one water body (1.24.0), from the CHN / NHN / FWA imports and CGNDB. Backed by
     * {@code dbo.fn_lake_barriers_json}.
     *
     * @param lakeId the water body's canonical GUID
     * @return {@code {guid, lakeName, waterfalls:[...], dams:[...]}} — each item {@code {id, name, type, CGNDB,
     *         chnFeatureId, cabdId, lat, lon, province, linkMethod, linkDistanceM}}, named ones first; empty arrays
     *         when there are none — or {@code null} if no water body exists for the id
     */
    JsonNode barriers(String lakeId);

    /**
     * Water-body lookup and ranking by any combination of criteria; every non-null one must match (AND).
     * Backed by {@code dbo.fn_river_search_json}. The caller validates and normalizes the inputs, and at
     * least one criterion ({@link RiverSearchCriteria#hasCriterion}) is set. Region, type, sort and paging
     * 1.26.0; {@code stateId} 1.23.0.
     *
     * @param criteria the normalized search
     * @return {@code {total, limit, offset, items}} — {@code total} counts every match, {@code items} (empty when
     *         nothing matches) holds one page of {@code {lakeId, secondaryId, lakeName, altName, frenchName,
     *         locType, CGNDB, CGNDM, stateId, country, state, length, lengthM, area, depth, mli:[...]}} in the
     *         requested order
     */
    JsonNode search(RiverSearchCriteria criteria);
}
