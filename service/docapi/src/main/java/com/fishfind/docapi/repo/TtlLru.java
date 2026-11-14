package com.fishfind.docapi.repo;

import java.time.Clock;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.Supplier;

/**
 * A small time-bounded LRU of whole documents, shared by the caching repository decorators
 * ({@link CachingForecastQueryRepository}, {@link CachingMapQueryRepository}). A {@code null} value (a miss) is never
 * stored. Loads run outside the lock, so one slow query does not stall every other request.
 *
 * @param <V> the cached document type
 */
public final class TtlLru<V> {

    private final long ttlMillis;
    private final Clock clock;
    private final LinkedHashMap<String, Entry<V>> map;

    public TtlLru(int maxEntries, long ttlMillis, Clock clock) {
        this.ttlMillis = ttlMillis;
        this.clock = clock;
        this.map = new LinkedHashMap<>(64, 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<String, Entry<V>> eldest) {
                return size() > maxEntries;
            }
        };
    }

    public V get(String key, Supplier<V> loader) {
        long now = clock.millis();
        synchronized (map) {
            Entry<V> e = map.get(key);
            if (e != null && e.expires() > now) {
                return e.value();
            }
        }
        V value = loader.get();
        if (value != null) {
            synchronized (map) {
                map.put(key, new Entry<>(value, now + ttlMillis));
            }
        }
        return value;
    }

    public int size() {
        synchronized (map) {
            return map.size();
        }
    }

    private record Entry<V>(V value, long expires) {}
}
