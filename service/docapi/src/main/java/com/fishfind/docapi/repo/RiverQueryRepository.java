package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

import java.util.Collection;
import java.util.Set;

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

    /**
     * The water bodies that flow INTO one water body (1.22.0) — those whose mouth ({@code Tributaries} side 32)
     * is this one, plus the side-4 inflows recorded on it (a lake/pond/reservoir), each listed once. Backed by
     * {@code dbo.fn_lake_inflows_json}.
     *
     * @param lakeId the water body's canonical GUID
     * @param limit  maximum number of items (1..200); {@code total} still counts every inflow
     * @return {@code {guid, lakeName, total, limit, tributaries:[{lakeId, lakeName, altName, frenchName, locType,
     *         CGNDB, link, lat, lon, country, state}]}} by name, or {@code null} if no water body exists for the id
     */
    JsonNode tributaries(String lakeId, int limit);

    /**
     * Water-body lookup by any combination of criteria; every non-null one must match (AND). Backed by
     * {@code dbo.fn_river_search_json}. The caller validates and normalizes the inputs; at least one
     * criterion is non-null.
     *
     * @param name  part of the name — matched against {@code lake_name}, {@code alt_name}, {@code french_name}
     * @param guid  canonical GUID — matched against {@code lake_id} OR {@code secondary_id}
     * @param cgndb   upper-cased code — matched against {@code CGNDB} OR {@code CGNDM}
     * @param stateId the province's/state's own id — matched exactly against {@code state_id} (1.23.0)
     * @param mli     a {@code WaterStation.MLI} — matches the water body that station is linked to
     * @param limit   maximum number of hits (1..200)
     * @return a JSON array (empty when nothing matches) of {@code {lakeId, secondaryId, lakeName, altName,
     *         frenchName, locType, CGNDB, CGNDM, stateId, country, state, mli:[...]}}, exact name first
     */
    JsonNode search(String name, String guid, String cgndb, String stateId, String mli, int limit);

    /**
     * Which of the given water bodies are Canadian, backed by {@code dbo.fn_lake_canadian_ids_json}: a CGNDB
     * code, or a source or mouth in country {@code CA}. Used by the MCP tools (docapi 1.21.0), which show
     * Canadian water bodies only.
     *
     * @param lakeIds canonical GUIDs (any case); empty yields an empty set without a query
     * @return the qualifying ids, UPPER-case; never {@code null}
     */
    Set<String> canadianIds(Collection<String> lakeIds);
}
