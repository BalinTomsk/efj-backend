package com.fishfind.weather.service;

import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.ratelimiter.annotation.RateLimiter;
import io.github.resilience4j.retry.annotation.Retry;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Fetches raw SWOB real-time observation GeoJSON from Environment Canada MSC GeoMet.
 */
@Service
public class WeatherCanadaFetcher {
    private static final Logger log = LoggerFactory.getLogger(WeatherCanadaFetcher.class);
    private static final int HTTP_TOO_MANY_REQUESTS = 429;

    @Value("${weather.worker.connect-timeout-ms:15000}")
    private int connectTimeoutMs;

    @Value("${weather.worker.read-timeout-ms:30000}")
    private int readTimeoutMs;

    @Value("${weather.worker.weather-canada-base-url:https://api.weather.gc.ca}")
    private String baseUrl;

    @Value("${weather.worker.weather-canada-user-agent:${WEATHER_CANADA_USER_AGENT:efj-backend-weather/1.0 (ops@fishfind.com)}}")
    private String userAgent;

    @Value("${weather.worker.weather-canada-bbox-radius-degrees:0.05}")
    private double bboxRadiusDegrees;

    @Value("${weather.worker.rate-limit.max-retries:2}")
    private int rateLimitMaxRetries;

    @Value("${weather.worker.rate-limit.default-wait-ms:5000}")
    private long rateLimitDefaultWaitMs;

    @Value("${weather.worker.rate-limit.max-wait-ms:60000}")
    private long rateLimitMaxWaitMs;

    @Value("${weather.worker.max-response-bytes:5242880}")
    private int maxResponseBytes;

    @Retry(name = "weatherCanada")
    @CircuitBreaker(name = "weatherCanada")
    @RateLimiter(name = "weatherCanada")
    public String fetchLatestObservation(double latitude, double longitude) throws IOException {
        String url = buildUrl(latitude, longitude);

        int rateLimitWaits = 0;
        while (true) {
            HttpURLConnection connection = open(url);
            try {
                int status = connection.getResponseCode();

                if (status == HttpURLConnection.HTTP_NOT_FOUND) {
                    throw new FileNotFoundException("Weather Canada observation not published for URL " + url);
                }
                if (status == HTTP_TOO_MANY_REQUESTS) {
                    if (rateLimitWaits >= rateLimitMaxRetries) {
                        throw new RateLimitedException(
                                "Weather Canada rate limited (429) after " + rateLimitWaits + " waits for URL " + url);
                    }
                    long waitMs = retryAfterMillis(connection);
                    rateLimitWaits++;
                    log.warn("Weather Canada rate limited (429). Honouring Retry-After. waitMs={} attempt={}",
                            waitMs, rateLimitWaits);
                    honourRetryAfter(waitMs);
                    continue;
                }
                if (status != HttpURLConnection.HTTP_OK) {
                    throw new IOException("Weather Canada returned HTTP " + status + " for URL " + url);
                }

                try (InputStream inputStream = connection.getInputStream()) {
                    byte[] body = inputStream.readNBytes(maxResponseBytes + 1);
                    if (body.length > maxResponseBytes) {
                        throw new IOException("Weather Canada response exceeded " + maxResponseBytes
                                + " bytes for URL " + url);
                    }
                    String json = new String(body, StandardCharsets.UTF_8);
                    requireJsonObjectWithFeatures(json, url);
                    log.debug("Weather Canada fetch succeeded. latitude={} longitude={}", latitude, longitude);
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
        connection.setRequestProperty("Accept", "application/geo+json");
        connection.setRequestProperty("User-Agent", userAgent);
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
            throw new RateLimitedException("Interrupted while waiting out Weather Canada Retry-After", ex);
        }
    }

    private static void requireJsonObjectWithFeatures(String body, String url) throws IOException {
        String trimmed = body.stripLeading();
        if (trimmed.isEmpty() || trimmed.charAt(0) != '{') {
            throw new IOException("Weather Canada returned a non-JSON body for URL " + url);
        }
        if (trimmed.replaceAll("\\s+", "").contains("\"features\":[]")) {
            throw new FileNotFoundException("Weather Canada returned no SWOB features for URL " + url);
        }
    }

    private String buildUrl(double latitude, double longitude) {
        double minLon = longitude - bboxRadiusDegrees;
        double minLat = latitude - bboxRadiusDegrees;
        double maxLon = longitude + bboxRadiusDegrees;
        double maxLat = latitude + bboxRadiusDegrees;
        String bbox = String.format(Locale.ROOT, "%.6f,%.6f,%.6f,%.6f", minLon, minLat, maxLon, maxLat);
        return baseUrl.replaceAll("/+$", "")
                + "/collections/swob-realtime/items"
                + "?lang=en"
                + "&f=json"
                + "&limit=1"
                + "&sortby=-date_tm-value"
                + "&bbox=" + bbox;
    }
}
