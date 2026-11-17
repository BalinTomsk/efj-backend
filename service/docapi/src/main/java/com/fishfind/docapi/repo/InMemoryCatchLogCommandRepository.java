package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;

import java.time.LocalDate;

/**
 * In-memory catch-log command repository (default, no-database profile). No water bodies exist in memory,
 * so every id is "not found".
 */
public class InMemoryCatchLogCommandRepository implements CatchLogCommandRepository {

    @Override
    public boolean fishExists(String fishId) {
        return false;
    }

    @Override
    public int photoCount(String catchLogId) {
        return -1;
    }

    @Override
    public CatchLog find(String catchLogId) {
        return null;
    }

    @Override
    public CatchLog.Weather stationWeather(String lakeId, LocalDate date) {
        return CatchLog.Weather.NONE;
    }

    @Override
    public JsonNode add(CatchLog log) {
        return null;
    }

    @Override
    public JsonNode addPhoto(String catchLogId, String userId, byte[] jpeg, int ord, String description, String author) {
        return null;
    }

    @Override
    public JsonNode mine(String userId, int limit) {
        return JsonNodeFactory.instance.arrayNode();
    }

    @Override
    public Boolean canEdit(String catchLogId, String userId) {
        return null;
    }

    @Override
    public byte[] photo(String catchLogId, String photoId) {
        return null;
    }
}
