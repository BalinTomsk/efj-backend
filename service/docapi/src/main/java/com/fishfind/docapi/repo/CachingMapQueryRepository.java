package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

import java.time.Clock;

/**
 * Caching decorator for {@link MapQueryRepository} (1.33.0). Shapes change only when a province or state is
 * imported, the droplet has one shared vCPU, and a map asks for the same tiles over and over, so whole documents are
 * held for {@link #TTL_MILLIS}. The controller rounds the box to 1e-5° (about a metre), so the same tile is the same key.
 * Fewer entries than the forecast cache: one document can be hundreds of kilobytes.
 */
public class CachingMapQueryRepository implements MapQueryRepository {

    /** 30 minutes. */
    public static final long TTL_MILLIS = 30 * 60 * 1000L;

    public static final int MAX_ENTRIES = 200;

    private final MapQueryRepository delegate;
    private final TtlLru<JsonNode> shapes;

    public CachingMapQueryRepository(MapQueryRepository delegate) {
        this(delegate, Clock.systemUTC());
    }

    CachingMapQueryRepository(MapQueryRepository delegate, Clock clock) {
        this.delegate = delegate;
        this.shapes = new TtlLru<>(MAX_ENTRIES, TTL_MILLIS, clock);
    }

    @Override
    public JsonNode shapes(double west, double south, double east, double north, int zoom, int limit) {
        String key = west + "|" + south + "|" + east + "|" + north + "|" + zoom + "|" + limit;
        return shapes.get(key, () -> delegate.shapes(west, south, east, north, zoom, limit));
    }

    int size() {
        return shapes.size();
    }
}
