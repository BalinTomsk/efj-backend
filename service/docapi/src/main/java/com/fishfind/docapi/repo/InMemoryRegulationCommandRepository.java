package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

/**
 * In-memory regulation command repository (default, no-database profile). Always reports the body as
 * unprocessable rather than pretending to insert/update a row that doesn't really exist anywhere — the
 * endpoint still runs end-to-end with no database.
 */
public class InMemoryRegulationCommandRepository implements RegulationCommandRepository {

    private final ObjectMapper objectMapper;

    public InMemoryRegulationCommandRepository(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Override
    public JsonNode upsert(String bodyJson) {
        ObjectNode node = objectMapper.createObjectNode();
        node.putNull("id");
        node.putNull("action");
        node.put("error", "no database configured (in-memory profile)");
        return node;
    }
}
