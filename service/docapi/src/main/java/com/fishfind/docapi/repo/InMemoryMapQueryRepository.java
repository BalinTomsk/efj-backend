package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

/** In-memory map repository (default, no-database profile): no shapes, so every box is an empty FeatureCollection. */
public class InMemoryMapQueryRepository implements MapQueryRepository {

    private final ObjectMapper objectMapper;

    public InMemoryMapQueryRepository(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Override
    public JsonNode shapes(double west, double south, double east, double north, int zoom, int limit) {
        ObjectNode doc = objectMapper.createObjectNode();
        doc.put("type", "FeatureCollection");
        ArrayNode bbox = doc.putArray("bbox");
        bbox.add(west).add(south).add(east).add(north);
        doc.put("zoom", zoom);
        doc.put("truncated", false);
        doc.putArray("features");
        return doc;
    }
}
