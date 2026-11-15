package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.util.List;

/** Default (no-database) profile: no stories, nothing near. */
public class InMemoryNewsNearRepository implements NewsNearRepository {

    private final ObjectMapper objectMapper;

    public InMemoryNewsNearRepository(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Override
    public List<TaggedNews> taggedNews(int limit) {
        return List.of();
    }

    @Override
    public JsonNode lakesNear(String lakeIdsJson, double lat, double lon, int radiusKm) {
        return objectMapper.createArrayNode();
    }
}
