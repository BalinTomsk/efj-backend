package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

/**
 * In-memory regulation query repository (default, no-database profile). No water body exists in
 * memory, so {@link #lakeRegulation} always answers "not found" (controller maps to 404) — the
 * endpoint still runs end-to-end with no database. {@link #region} always answers an empty rule set,
 * matching {@code fn_region_regulation_json}'s "unknown scope -> empty array, never null" contract.
 */
public class InMemoryRegulationQueryRepository implements RegulationQueryRepository {

    private final ObjectMapper objectMapper;

    public InMemoryRegulationQueryRepository(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Override
    public JsonNode lakeRegulation(String lakeId) {
        return null;
    }

    @Override
    public JsonNode region(String country, String state) {
        ObjectNode node = objectMapper.createObjectNode();
        node.put("country", country);
        if (state == null) {
            node.putNull("state");
        } else {
            node.put("state", state);
        }
        ArrayNode regulations = objectMapper.createArrayNode();
        node.set("regulations", regulations);
        return node;
    }
}
