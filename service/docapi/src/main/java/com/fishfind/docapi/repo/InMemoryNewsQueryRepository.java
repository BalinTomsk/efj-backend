package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.web.NewsController.NewsListPage;

import java.util.List;

/**
 * In-memory news query repository (default, no-database profile).
 * Returns empty results so the service runs end-to-end with no DB.
 */
public class InMemoryNewsQueryRepository implements NewsQueryRepository {

    private final ObjectMapper objectMapper;

    public InMemoryNewsQueryRepository(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Override
    public NewsListPage list(String country, int offset, int limit) {
        return new NewsListPage(List.of(), 0L, offset, limit);
    }

    @Override
    public JsonNode defaultNews() {
        return objectMapper.createObjectNode().set("items", objectMapper.createArrayNode());
    }
}
