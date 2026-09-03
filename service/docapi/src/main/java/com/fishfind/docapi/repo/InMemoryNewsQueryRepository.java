package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;

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

    /**
     * No database: no lake or fish rows to resolve against, so both halves come back empty. The shape
     * is still the real one, so a caller (and the enrichment in {@link MySqlNewsQueryRepository}) can
     * read {@code .lakes} / {@code .fishes} unconditionally in either profile.
     */
    @Override
    public JsonNode resolveRefNames(List<String> lakeIds, List<String> fishIds) {
        ObjectNode root = objectMapper.createObjectNode();
        root.set("lakes", objectMapper.createArrayNode());
        root.set("fishes", objectMapper.createArrayNode());
        return root;
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
    public NewsSearchPage search(String query) {
        return new NewsSearchPage(List.of(), 0, query);
    }
}
