package com.fishfind.weather.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.ratelimiter.annotation.RateLimiter;
import io.github.resilience4j.retry.annotation.Retry;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Fetches current conditions from Weather Underground (IBM/The Weather Company PWS API).
 *
 * <p>A PWS Contributor key has no lat/lon forecast endpoint, so each station costs two calls:
 * {@code v3/location/near} resolves the nearest personal weather station to the water station's
 * coordinates, then {@code v2/pws/observations/current} fetches that station's latest reading.
 * Both calls share the retry/circuit-breaker/rate-limiter around {@link #fetchCurrent}, so a
 * configured daily limit is spent in stations, not raw HTTP calls -- the effective call volume
 * against the Wunderground quota is roughly double the configured station limit.
 */
@Service
public class WundergroundFetcher {
    private static final Logger log = LoggerFactory.getLogger(WundergroundFetcher.class);
    private static final int HTTP_TOO_MANY_REQUESTS = 429;
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    @Value("${weather.worker.connect-timeout-ms:15000}")
    private int connectTimeoutMs;

    @Value("${weather.worker.read-timeout-ms:30000}")
    private int readTimeoutMs;

    @Value("${weather.worker.wunderground-location-base-url:https://api.weather.com/v3/location/near}")
    private String locationBaseUrl;

    @Value("${weather.worker.wunderground-observation-base-url:"
            + "https://api.weather.com/v2/pws/observations/current}")
    private String observationBaseUrl;

    @Value("${weather.worker.wunderground-api-key:${WUNDERGROUND_API_KEY:}}")
    private String apiKey;

    @Value("${weather.worker.rate-limit.max-retries:2}")
    private int rateLimitMaxRetries;

    @Value("${weather.worker.rate-limit.default-wait-ms:5000}")
    private long rateLimitDefaultWaitMs;

    @Value("${weather.worker.rate-limit.max-wait-ms:60000}")
    private long rateLimitMaxWaitMs;

    @Value("${weather.worker.max-response-bytes:5242880}")
    private int maxResponseBytes;

    @Retry(name = "wunderground")
    @CircuitBreaker(name = "wunderground")
    @RateLimiter(name = "wunderground")
    public String fetchCurrent(double latitude, double longitude) throws IOException {
        String stationId = nearestStationId(latitude, longitude);
        String json = fetchJson(buildObservationUrl(stationId), "Wunderground observation");
        log.debug("Wunderground fetch succeeded. latitude={} longitude={} stationId={}",
                latitude, longitude, stationId);
        return json;
    }

    private String nearestStationId(double latitude, double longitude) throws IOException {
        String json = fetchJson(buildLocationUrl(latitude, longitude), "Wunderground nearest-station lookup");
        JsonNode stationIds = readTree(json).path("location").path("stationId");
        if (!stationIds.isArray() || stationIds.isEmpty() || stationIds.get(0).asText("").isBlank()) {
            throw new FileNotFoundException(
                    "No Wunderground PWS station found near latitude=" + latitude + " longitude=" + longitude);
        }
        return stationIds.get(0).asText();
    }

    private static JsonNode readTree(String json) throws IOException {
        try {
            return OBJECT_MAPPER.readTree(json);
        } catch (IOException ex) {
            throw new IOException("Wunderground returned unparsable JSON", ex);
        }
    }

    private String fetchJson(String url, String label) throws IOException {
        int rateLimitWaits = 0;
        while (true) {
            HttpURLConnection connection = open(url);
            try {
                int status = connection.getResponseCode();

                if (status == HttpURLConnection.HTTP_NOT_FOUND) {
                    throw new FileNotFoundException(label + " not found (HTTP 404)");
                }
                if (status == HttpURLConnection.HTTP_UNAUTHORIZED || status == HttpURLConnection.HTTP_FORBIDDEN) {
                    throw new IOException(label + " authentication failed with HTTP " + status);
                }
                if (status == HTTP_TOO_MANY_REQUESTS) {
                    if (rateLimitWaits >= rateLimitMaxRetries) {
                        throw new RateLimitedException(
                                label + " rate limited (429) after " + rateLimitWaits + " waits");
                    }
                    long waitMs = retryAfterMillis(connection);
                    rateLimitWaits++;
                    log.warn("{} rate limited (429). Honouring Retry-After. waitMs={} attempt={}",
                            label, waitMs, rateLimitWaits);
                    honourRetryAfter(waitMs, label);
                    continue;
                }
                if (status != HttpURLConnection.HTTP_OK) {
                    throw new IOException(label + " returned HTTP " + status);
                }

                try (InputStream inputStream = connection.getInputStream()) {
                    byte[] body = inputStream.readNBytes(maxResponseBytes + 1);
                    if (body.length > maxResponseBytes) {
                        throw new IOException(label + " response exceeded " + maxResponseBytes + " bytes");
                    }
                    String json = new String(body, StandardCharsets.UTF_8);
                    requireJsonShape(json, label);
                    return json;
                }
            } finally {
                connection.disconnect();
            }
        }
    }

    private HttpURLConnection open(String url) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) URI.create(url).toURL().openConnection();
        connection.setRequestMethod("GET");
        connection.setConnectTimeout(connectTimeoutMs);
        connection.setReadTimeout(readTimeoutMs);
        connection.setRequestProperty("Accept", "application/json");
        return connection;
    }

    private long retryAfterMillis(HttpURLConnection connection) {
        String header = connection.getHeaderField("Retry-After");
        if (header == null || header.isBlank()) {
            return clampWait(rateLimitDefaultWaitMs);
        }
        try {
            return clampWait(Long.parseLong(header.trim()) * 1000L);
        } catch (NumberFormatException notSeconds) {
            try {
                long epochMillis = ZonedDateTime.parse(header.trim(), DateTimeFormatter.RFC_1123_DATE_TIME)
                        .toInstant().toEpochMilli();
                return clampWait(epochMillis - System.currentTimeMillis());
            } catch (Exception notDate) {
                return clampWait(rateLimitDefaultWaitMs);
            }
        }
    }

    private long clampWait(long ms) {
        return Math.max(0L, Math.min(ms, rateLimitMaxWaitMs));
    }

    private void honourRetryAfter(long ms, String label) throws IOException {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new RateLimitedException("Interrupted while waiting out " + label + " Retry-After", ex);
        }
    }

    private static void requireJsonShape(String body, String label) throws IOException {
        String trimmed = body.stripLeading();
        if (trimmed.isEmpty() || (trimmed.charAt(0) != '{' && trimmed.charAt(0) != '[')) {
            throw new IOException(label + " returned a non-JSON body");
        }
    }

    private String buildLocationUrl(double latitude, double longitude) throws IOException {
        String key = requireApiKey();
        return locationBaseUrl.replaceAll("/+$", "")
                + "?geocode=" + latitude + "," + longitude
                + "&product=pws"
                + "&format=json"
                + "&apiKey=" + encode(key);
    }

    private String buildObservationUrl(String stationId) throws IOException {
        String key = requireApiKey();
        return observationBaseUrl.replaceAll("/+$", "")
                + "?stationId=" + encode(stationId)
                + "&format=json"
                + "&units=e"
                + "&apiKey=" + encode(key);
    }

    private static String encode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20");
    }

    private String requireApiKey() throws IOException {
        if (apiKey == null || apiKey.isBlank()) {
            throw new IOException("WUNDERGROUND_API_KEY is not configured");
        }
        return apiKey.trim();
    }
}
