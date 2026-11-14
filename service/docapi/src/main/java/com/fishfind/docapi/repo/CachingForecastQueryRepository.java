package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

import java.time.Clock;

/**
 * Caching decorator for {@link ForecastQueryRepository} (1.31.0). The forecast changes slowly (the map's
 * {@code fish_location.today} is recomputed by a job, water readings arrive hourly), the droplet has one shared
 * vCPU, and cproxy caches only guest GETs while every app call is signed in. So each endpoint keeps a bounded LRU
 * of whole documents for {@link #TTL_MILLIS}; a miss ({@code null}) is never stored.
 *
 * <p>The stations key uses the coordinates exactly as the controller passes them, already rounded to 0.01°, so
 * nearby callers share an entry.
 */
public class CachingForecastQueryRepository implements ForecastQueryRepository {

    /** How long a document is served from memory: 5 minutes. */
    public static final long TTL_MILLIS = 5 * 60 * 1000L;

    /** Entries per endpoint. */
    public static final int MAX_ENTRIES = 500;

    private final ForecastQueryRepository delegate;
    private final TtlLru<JsonNode> stations;
    private final TtlLru<JsonNode> plots;
    private final TtlLru<JsonNode> reasonings;

    public CachingForecastQueryRepository(ForecastQueryRepository delegate) {
        this(delegate, Clock.systemUTC());
    }

    CachingForecastQueryRepository(ForecastQueryRepository delegate, Clock clock) {
        this.delegate = delegate;
        this.stations = new TtlLru<>(MAX_ENTRIES, TTL_MILLIS, clock);
        this.plots = new TtlLru<>(MAX_ENTRIES, TTL_MILLIS, clock);
        this.reasonings = new TtlLru<>(MAX_ENTRIES, TTL_MILLIS, clock);
    }

    @Override
    public JsonNode stations(String fishId, double lat, double lon, int radiusKm, String country, int limit) {
        String key = fishId + '|' + lat + '|' + lon + '|' + radiusKm + '|' + country + '|' + limit;
        return stations.get(key, () -> delegate.stations(fishId, lat, lon, radiusKm, country, limit));
    }

    @Override
    public JsonNode plot(int sid, String fishId) {
        return plots.get(sid + "|" + fishId, () -> delegate.plot(sid, fishId));
    }

    @Override
    public JsonNode reasoning(int sid, String fishId, int day) {
        return reasonings.get(sid + "|" + fishId + '|' + day, () -> delegate.reasoning(sid, fishId, day));
    }

    /** Entries held per endpoint (tests). */
    int size() {
        return stations.size() + plots.size() + reasonings.size();
    }
}
