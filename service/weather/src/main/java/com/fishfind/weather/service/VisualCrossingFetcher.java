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
import java.util.Locale;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Fetches raw current-conditions JSON from the Visual Crossing Timeline API.
 */
@Service
public class VisualCrossingFetcher {
    private static final Logger log = LoggerFactory.getLogger(VisualCrossingFetcher.class);
    private static final int HTTP_TOO_MANY_REQUESTS = 429;

    @Value("${weather.worker.connect-timeout-ms:15000}")
    private int connectTimeoutMs;

    @Value("${weather.worker.read-timeout-ms:30000}")
    private int readTimeoutMs;

    @Value("${weather.worker.visual-crossing-base-url:"
            + "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline}")
    private String baseUrl;

    @Value("${weather.worker.visual-crossing-api-key:${VISUAL_CROSSING_API_KEY:}}")
    private String apiKey;

    @Value("${weather.worker.rate-limit.max-retries:2}")
    private int rateLimitMaxRetries;

    @Value("${weather.worker.rate-limit.default-wait-ms:5000}")
    private long rateLimitDefaultWaitMs;

    @Value("${weather.worker.rate-limit.max-wait-ms:60000}")
    private long rateLimitMaxWaitMs;

    @Value("${weather.worker.max-response-bytes:5242880}")
    private int maxResponseBytes;

    @Retry(name = "visualCrossing")
    @CircuitBreaker(name = "visualCrossing")
    @RateLimiter(name = "visualCrossing")
    public String fetchCurrent(double latitude, double longitude) throws IOException {
        String url = buildUrl(latitude, longitude);

        int rateLimitWaits = 0;
        while (true) {
            HttpURLConnection connection = open(url);
            try {
                int status = connection.getResponseCode();

                if (status == HttpURLConnection.HTTP_NOT_FOUND) {
                    throw new FileNotFoundException("Visual Crossing feed not published for latitude="
                            + latitude + " longitude=" + longitude);
                }
                if (status == HttpURLConnection.HTTP_UNAUTHORIZED || status == HttpURLConnection.HTTP_FORBIDDEN) {
                    throw new IOException("Visual Crossing authentication failed with HTTP " + status);
                }
                if (status == HTTP_TOO_MANY_REQUESTS) {
                    if (rateLimitWaits >= rateLimitMaxRetries) {
                        throw new RateLimitedException(
                                "Visual Crossing rate limited (429) after " + rateLimitWaits + " waits");
                    }
                    long waitMs = retryAfterMillis(connection);
                    rateLimitWaits++;
                    log.warn("Visual Crossing rate limited (429). Honouring Retry-After. waitMs={} attempt={}",
                            waitMs, rateLimitWaits);
                    honourRetryAfter(waitMs);
                    continue;
                }
                if (status != HttpURLConnection.HTTP_OK) {
                    throw new IOException("Visual Crossing returned HTTP " + status);
                }

                try (InputStream inputStream = connection.getInputStream()) {
                    byte[] body = inputStream.readNBytes(maxResponseBytes + 1);
                    if (body.length > maxResponseBytes) {
                        throw new IOException("Visual Crossing response exceeded " + maxResponseBytes + " bytes");
                    }
                    String json = new String(body, StandardCharsets.UTF_8);
                    requireJsonObjectShape(json);
                    log.debug("Visual Crossing fetch succeeded. latitude={} longitude={}", latitude, longitude);
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

    private void honourRetryAfter(long ms) throws IOException {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new RateLimitedException("Interrupted while waiting out Visual Crossing Retry-After", ex);
        }
    }

    private static void requireJsonObjectShape(String body) throws IOException {
        String trimmed = body.stripLeading();
        if (trimmed.isEmpty() || trimmed.charAt(0) != '{') {
            throw new IOException("Visual Crossing returned a non-JSON body");
        }
    }

    private String buildUrl(double latitude, double longitude) throws IOException {
        String key = requireApiKey();
        String location = URLEncoder.encode(String.format(Locale.ROOT, "%s,%s", latitude, longitude),
                StandardCharsets.UTF_8).replace("+", "%20");
        return baseUrl.replaceAll("/+$", "") + "/" + location
                + "?unitGroup=us"
                + "&include=current"
                + "&contentType=json"
                + "&key=" + URLEncoder.encode(key, StandardCharsets.UTF_8).replace("+", "%20");
    }

    private String requireApiKey() throws IOException {
        if (apiKey == null || apiKey.isBlank()) {
            throw new IOException("VISUAL_CROSSING_API_KEY is not configured");
        }
        return apiKey.trim();
    }
}
