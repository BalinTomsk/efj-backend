package com.fishfind.weather.service;

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
 * Fetches raw latest-observation JSON from the National Weather Service API.
 */
@Service
public class WeatherGovFetcher {
    private static final Logger log = LoggerFactory.getLogger(WeatherGovFetcher.class);
    private static final int HTTP_TOO_MANY_REQUESTS = 429;

    @Value("${weather.worker.connect-timeout-ms:15000}")
    private int connectTimeoutMs;

    @Value("${weather.worker.read-timeout-ms:30000}")
    private int readTimeoutMs;

    @Value("${weather.worker.weather-gov-base-url:https://api.weather.gov}")
    private String baseUrl;

    @Value("${weather.worker.weather-gov-user-agent:efj-backend-weather/1.0 (ops@fishfind.com)}")
    private String userAgent;

    @Value("${weather.worker.rate-limit.max-retries:2}")
    private int rateLimitMaxRetries;

    @Value("${weather.worker.rate-limit.default-wait-ms:5000}")
    private long rateLimitDefaultWaitMs;

    @Value("${weather.worker.rate-limit.max-wait-ms:60000}")
    private long rateLimitMaxWaitMs;

    @Value("${weather.worker.max-response-bytes:5242880}")
    private int maxResponseBytes;

    @Retry(name = "weatherGov")
    @CircuitBreaker(name = "weatherGov")
    @RateLimiter(name = "weatherGov")
    public String fetchLatestObservation(String stationId) throws IOException {
        String normalizedStationId = requireStationId(stationId);
        String url = buildUrl(normalizedStationId);

        int rateLimitWaits = 0;
        while (true) {
            HttpURLConnection connection = open(url);
            try {
                int status = connection.getResponseCode();

                if (status == HttpURLConnection.HTTP_NOT_FOUND) {
                    throw new FileNotFoundException("Weather.gov observation not published for station "
                            + normalizedStationId);
                }
                if (status == HTTP_TOO_MANY_REQUESTS) {
                    if (rateLimitWaits >= rateLimitMaxRetries) {
                        throw new RateLimitedException(
                                "Weather.gov rate limited (429) after " + rateLimitWaits
                                        + " waits for station " + normalizedStationId);
                    }
                    long waitMs = retryAfterMillis(connection);
                    rateLimitWaits++;
                    log.warn("Weather.gov rate limited (429). Honouring Retry-After. station={} waitMs={} attempt={}",
                            normalizedStationId, waitMs, rateLimitWaits);
                    honourRetryAfter(waitMs);
                    continue;
                }
                if (status != HttpURLConnection.HTTP_OK) {
                    throw new IOException("Weather.gov returned HTTP " + status + " for station "
                            + normalizedStationId);
                }

                try (InputStream inputStream = connection.getInputStream()) {
                    byte[] body = inputStream.readNBytes(maxResponseBytes + 1);
                    if (body.length > maxResponseBytes) {
                        throw new IOException("Weather.gov response exceeded " + maxResponseBytes
                                + " bytes for station " + normalizedStationId);
                    }
                    String json = new String(body, StandardCharsets.UTF_8);
                    requireJsonObjectShape(json, normalizedStationId);
                    log.debug("Weather.gov fetch succeeded. station={}", normalizedStationId);
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
        connection.setRequestProperty("User-Agent", userAgent);
        connection.setRequestProperty("Accept", "application/geo+json");
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

    private void honourRetryAfter(long ms) throws IOException {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new RateLimitedException("Interrupted while waiting out Weather.gov Retry-After", ex);
        }
    }

    private static void requireJsonObjectShape(String body, String stationId) throws IOException {
        String trimmed = body.stripLeading();
        if (trimmed.isEmpty() || trimmed.charAt(0) != '{') {
            throw new IOException("Weather.gov returned a non-JSON body for station " + stationId);
        }
    }

    private static String requireStationId(String stationId) {
        if (stationId == null || stationId.isBlank()) {
            throw new IllegalArgumentException("stationId must not be null or blank");
        }
        return stationId.trim().toUpperCase();
    }

    private String buildUrl(String stationId) {
        String encodedStation = URLEncoder.encode(stationId, StandardCharsets.UTF_8).replace("+", "%20");
        return baseUrl.replaceAll("/+$", "") + "/stations/" + encodedStation + "/observations/latest";
    }
}
