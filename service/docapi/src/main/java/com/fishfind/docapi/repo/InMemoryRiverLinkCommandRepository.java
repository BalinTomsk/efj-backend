package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * In-memory river-link command repository (default, no-database profile). No water bodies exist in
 * memory, so every id is "not found" (controller maps to 404) — the endpoint still runs end-to-end
 * with no database.
 */
public class InMemoryRiverLinkCommandRepository implements RiverLinkCommandRepository {

    @Override
    public JsonNode patchSource(String lakeId, String patchJson) {
        return null;
    }

    @Override
    public JsonNode patchMouth(String lakeId, String patchJson) {
        return null;
    }
}
