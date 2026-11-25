package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

import java.util.Locale;

/**
 * The forecast documents from env_service (1.45.0, env_service plan step 6c) instead of SQL Server: its
 * {@code /api/v1/env/forecast/*} answers ARE the bodies {@code /api/v1/forecast/*} returns, so this passes them through.
 * The same three documents as {@link JdbcForecastQueryRepository}, except pressure is in mm Hg and renamed (an app that
 * reads hPa finds none instead of a wrong value): reasoning {@code pressure.mm} / {@code swingMm} / {@code change1d} /
 * {@code series[].mm} (were {@code hpa} / {@code swingHpa} / {@code change1d} in hPa / {@code series[].hpa}), plot
 * {@code pressureMm[]} (was {@code pressure[]}) with {@code units.pressure = "mmHg"}. {@link CachingForecastQueryRepository}
 * stays in front.
 */
public class HttpForecastQueryRepository implements ForecastQueryRepository {

    private final EnvClient env;

    public HttpForecastQueryRepository(EnvClient env) {
        this.env = env;
    }

    @Override
    public JsonNode stations(String fishId, double lat, double lon, int radiusKm, String country, int limit) {
        String query = String.format(Locale.ROOT, "/forecast/stations?fish=%s&lat=%s&lon=%s&radius=%d&limit=%d",
                EnvClient.enc(fishId), lat, lon, radiusKm, limit)
                + (country == null ? "" : "&country=" + EnvClient.enc(country));
        return env.get(query);
    }

    @Override
    public JsonNode plot(int sid, String fishId) {
        return env.get("/forecast/plot/" + sid + "?fish=" + EnvClient.enc(fishId));
    }

    @Override
    public JsonNode reasoning(int sid, String fishId, int day) {
        return env.get("/forecast/reasoning/" + sid + "?fish=" + EnvClient.enc(fishId) + "&day=" + day);
    }
}
