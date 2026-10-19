package com.fishfind.docapi.repo;

import java.util.List;

/**
 * The normalized arguments of one water-body search, {@code dbo.fn_river_search_json} (1.26.0). Built by
 * {@code RiverController.search} and {@code McpToolCatalog} ({@code search_water_bodies}), which validate every
 * field first; {@code null} means "not given".
 *
 * @param name    part of the name — {@code lake_name}, {@code alt_name} or {@code french_name}
 * @param guid    canonical GUID — {@code lake_id} OR {@code secondary_id}
 * @param cgndb   upper-cased code — {@code CGNDB} OR {@code CGNDM}
 * @param stateId the province's/state's own id — {@code state_id}, exact
 * @param mli     a {@code WaterStation.MLI} — the water body that station is linked to
 * @param country upper-case ISO-2 — the water body's source OR mouth is in it
 * @param state   upper-case ISO-2 province/state — the source OR mouth is in it
 * @param locType {@code lake.locType} bitmask; a water body matches when it shares any bit. A filter, not a
 *                criterion: it never makes a search on its own
 * @param sort    one of {@link #SORTS}
 * @param offset  rows skipped, ≥ 0
 * @param limit   rows returned, 1..200
 */
public record RiverSearchCriteria(String name, String guid, String cgndb, String stateId, String mli,
                                  String country, String state, Integer locType, String sort,
                                  int offset, int limit) {

    /** The default: exact name, then name prefix, then the rest, by name. */
    public static final String SORT_NAME = "name";

    /**
     * Every order the function knows. The four measure sorts leave out water bodies whose value is NULL or 0;
     * {@code length_*} order equal whole km by the mapped centre line in metres.
     */
    public static final List<String> SORTS = List.of(SORT_NAME, "length_desc", "length_asc", "area_desc", "depth_desc");

    /** Whether anything that can select water bodies by itself was given (type and sort only filter and order). */
    public boolean hasCriterion() {
        return name != null || guid != null || cgndb != null || stateId != null || mli != null
                || country != null || state != null;
    }
}
