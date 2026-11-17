package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/** Saved spots in memory (default, no-database profile), with the procedures' rules. */
public class InMemorySpotRepository implements SpotRepository {

    private record Spot(String userId, ObjectNode json) {}

    private final Map<String, Spot> spots = new ConcurrentHashMap<>();

    @Override
    public JsonNode mine(String userId) {
        ArrayNode out = JsonNodeFactory.instance.arrayNode();
        spots.values().stream().filter(s -> s.userId().equalsIgnoreCase(userId)).forEach(s -> out.add(s.json()));
        return out;
    }

    @Override
    public int save(String id, String userId, String name, double lat, double lon, String lakeId, String note) {
        Spot existing = spots.get(id);
        if (existing != null && !existing.userId().equalsIgnoreCase(userId)) {
            return NOT_OWNER;
        }
        ObjectNode json = JsonNodeFactory.instance.objectNode()
                .put("spotId", id).put("name", name).put("lat", lat).put("lon", lon).put("note", note);
        json.putNull("lakeId");
        spots.put(id, new Spot(userId, json));
        return existing == null ? INSERTED : UPDATED;
    }

    @Override
    public boolean delete(String id, String userId) {
        Spot existing = spots.get(id);
        return existing != null && existing.userId().equalsIgnoreCase(userId) && spots.remove(id) != null;
    }
}
