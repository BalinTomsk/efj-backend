package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

/**
 * In-memory river query repository (default, no-database profile). Returns a not-found result so the
 * endpoint runs end-to-end with no DB.
 */
public class InMemoryRiverQueryRepository implements RiverQueryRepository {

    private final ObjectMapper objectMapper;

    public InMemoryRiverQueryRepository(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Override
    public JsonNode unfished(String country, String state, int river) {
        ObjectNode node = objectMapper.createObjectNode();
        node.put("found", false);
        node.put("country", country);
        node.put("state", state);
        node.put("river", river);
        return node;
    }

    /** No database: nothing to describe, so every id is "not found" (controller maps to 404). */
    @Override
    public JsonNode description(String lakeId) {
        return null;
    }

    /** No database: nothing to list, so every id is "not found" (controller maps to 404). */
    @Override
    public JsonNode fish(String lakeId) {
        return null;
    }
}
