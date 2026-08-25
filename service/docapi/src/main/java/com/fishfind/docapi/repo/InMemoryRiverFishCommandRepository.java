package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * In-memory river-fish command repository (default, no-database profile). No water bodies exist in
 * memory, so every id is "not found" (controller maps to 404) — the endpoint still runs end-to-end
 * with no database.
 */
public class InMemoryRiverFishCommandRepository implements RiverFishCommandRepository {

    @Override
    public JsonNode upsertFish(String lakeId, String fishJsonArray) {
        return null;
    }
}
