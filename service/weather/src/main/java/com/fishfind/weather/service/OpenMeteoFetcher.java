package com.fishfind.weather.service;

import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.ratelimiter.annotation.RateLimiter;
import io.github.resilience4j.retry.annotation.Retry;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import java.util.Random;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Fetches raw forecast JSON from the Open-Meteo API.
 *
 * <p>Reliability is layered: HTTP 429 responses are handled inline by honouring the
 * {@code Retry-After} header (bounded), while transient failures (timeouts, 5xx) are retried
 * with exponential backoff and a circuit breaker / rate limiter guard the upstream — all via
 * the Resilience4j annotations on {@link #fetch}. HTTP 404 is treated as "no feed" and is not
 * retried.
 */
@Service
public class OpenMeteoFetcher {
    private static final Logger log = LoggerFactory.getLogger(OpenMeteoFetcher.class);
    private static final int HTTP_TOO_MANY_REQUESTS = 429;
    // Chrome-like User-Agent. The two "537.NN" WebKit/Safari build numbers are randomised
    // daily (see currentUserAgent); %d placeholders are filled per calendar day.
    private static final String USER_AGENT_TEMPLATE =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.%d "
                    + "(KHTML, like Gecko) Chrome/124.0 Safari/537.%d";
    private static final int BUILD_MIN = 11;
    private static final int BUILD_MAX = 97;

    @Value("${weather.worker.connect-timeout-ms:15000}")
    private int connectTimeoutMs;

    @Value("${weather.worker.read-timeout-ms:30000}")
    private int readTimeoutMs;

    @Value("${weather.worker.open-meteo-base-url:https://api.open-meteo.com/v1/forecast}")
    private String baseUrl;

    @Value("${weather.worker.rate-limit.max-retries:2}")
    private int rateLimitMaxRetries;

    @Value("${weather.worker.rate-limit.default-wait-ms:5000}")
    private long rateLimitDefaultWaitMs;

    @Value("${weather.worker.rate-limit.max-wait-ms:60000}")
    private long rateLimitMaxWaitMs;

    @Value("${weather.worker.max-response-bytes:5242880}")
    private int maxResponseBytes;

    @Retry(name = "openMeteo")
    @CircuitBreaker(name = "openMeteo")
    @RateLimiter(name = "openMeteo")
    public String fetch(double latitude, double longitude) throws IOException {
        String url = buildUrl(latitude, longitude);

        int rateLimitWaits = 0;
        while (true) {
            HttpURLConnection connection = open(url);
            try {
                int status = connection.getResponseCode();

                if (status == HttpURLConnection.HTTP_NOT_FOUND) {
                    throw new FileNotFoundException("Open-Meteo feed not published for URL " + url);
                }
                if (status == HTTP_TOO_MANY_REQUESTS) {
                    if (rateLimitWaits++ >= rateLimitMaxRetries) {
                        throw new RateLimitedException(
                                "Open-Meteo rate limited (429) after " + rateLimitWaits + " waits for URL " + url);
                    }
                    long waitMs = retryAfterMillis(connection);
                    log.warn("Open-Meteo rate limited (429). Honouring Retry-After. waitMs={} attempt={}",
                            waitMs, rateLimitWaits);
                    honourRetryAfter(waitMs);
                    continue;
                }
                if (status != HttpURLConnection.HTTP_OK) {
                    throw new IOException("Open-Meteo returned HTTP " + status + " for URL " + url);
                }

                try (InputStream inputStream = connection.getInputStream()) {
                    // Store the response body verbatim — the payload must be persisted raw, as-is.
                    byte[] body = inputStream.readNBytes(maxResponseBytes + 1);
                    if (body.length > maxResponseBytes) {
                        throw new IOException("Open-Meteo response exceeded " + maxResponseBytes
                                + " bytes for URL " + url);
                    }
                    String json = new String(body, StandardCharsets.UTF_8);
                    requireJsonObjectShape(json, url);
                    log.info("Open-Meteo fetch succeeded. latitude={} longitude={}", latitude, longitude);
                    return json;
                }
            } finally {
                connection.disconnect();
            }
        }
    }

    private HttpURLConnection open(String url) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setRequestMethod("GET");
        connection.setConnectTimeout(connectTimeoutMs);
        connection.setReadTimeout(readTimeoutMs);
        connection.setRequestProperty("User-Agent", currentUserAgent());
        return connection;
    }

    /** Parses the {@code Retry-After} header (delta-seconds or HTTP-date), clamped to [0, max]. */
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
            // RateLimitedException is excluded from Resilience4j retry, so an interrupt
            // (typically a shutdown) is not followed by further backoff attempts.
            throw new RateLimitedException("Interrupted while waiting out Open-Meteo Retry-After", ex);
        }
    }

    /**
     * Cheap shape guard, not JSON parsing: the body is persisted raw, but a 200 response
     * that is not a JSON object (e.g. an HTML error or captive-portal page) must not
     * reach the database, where downstream procedures would choke on it.
     */
    private static void requireJsonObjectShape(String body, String url) throws IOException {
        String trimmed = body.stripLeading();
        if (trimmed.isEmpty() || trimmed.charAt(0) != '{') {
            throw new IOException("Open-Meteo returned a non-JSON body for URL " + url);
        }
    }

    /** User-Agent for today, with WebKit/Safari build numbers randomised in [11, 97]. */
    static String currentUserAgent() {
        return currentUserAgent(LocalDate.now());
    }

    /**
     * Builds the User-Agent for the given day. The two "537.NN" build numbers are seeded by
     * the calendar day, so they stay stable for a whole day and change from one day to the next.
     */
    static String currentUserAgent(LocalDate date) {
        Random random = new Random(date.toEpochDay());
        int webKitBuild = random.nextInt(BUILD_MIN, BUILD_MAX + 1);
        int safariBuild = random.nextInt(BUILD_MIN, BUILD_MAX + 1);
        return String.format(Locale.ROOT, USER_AGENT_TEMPLATE, webKitBuild, safariBuild);
    }

    private String buildUrl(double latitude, double longitude) {
        return baseUrl + "?latitude=" + latitude
                + "&longitude=" + longitude
                + "&hourly=temperature_2m,relative_humidity_2m,precipitation_probability,pressure_msl,"
                + "wind_speed_10m,wind_direction_10m,weather_code,rain"
                + "&daily=temperature_2m_max,temperature_2m_min&timezone=auto";
    }
}
