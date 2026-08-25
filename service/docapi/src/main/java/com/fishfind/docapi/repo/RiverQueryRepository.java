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
}
