package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;
import com.fishfind.docapi.web.NewsController.NewsSearchQuery;

import java.util.List;
import java.util.UUID;

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

    /** No database: no photo for any id, so the endpoint runs end-to-end returning 404. */
    @Override
    public byte[] newsPhoto(String id) {
        return null;
    }

    /** No database: nothing to export, so every id is "not found" (controller maps to 404). */
    @Override
    public JsonNode exportNews(String id) {
        return null;
    }

    /** No database: accept the import and hand back a synthetic id so the endpoint runs end-to-end. */
    @Override
    public String importNews(String json) {
        return UUID.randomUUID().toString();
    }

    /** No database: no matches, so the search endpoint runs end-to-end returning an empty result. */
    @Override
    public NewsSearchPage search(NewsSearchQuery request) {
        return new NewsSearchPage(List.of(), 0, request.query(), request.offset(), request.limit());
    }
}
