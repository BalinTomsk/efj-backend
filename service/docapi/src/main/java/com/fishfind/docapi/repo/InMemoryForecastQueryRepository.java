package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * In-memory forecast repository (default, no-database profile): there is no forecast without the database, so
 * every fish and station is "not found" (the controller maps that to 404).
 */
public class InMemoryForecastQueryRepository implements ForecastQueryRepository {

    @Override
    public JsonNode stations(String fishId, double lat, double lon, int radiusKm, String country, int limit) {
        return null;
    }

    @Override
    public JsonNode plot(int sid, String fishId) {
        return null;
    }

    @Override
    public JsonNode reasoning(int sid, String fishId, int day) {
        return null;
    }
}
