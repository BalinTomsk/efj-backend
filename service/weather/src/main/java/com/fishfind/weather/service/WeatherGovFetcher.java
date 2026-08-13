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
import java.util.regex.Matcher;
import java.util.regex.Pattern;
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
    private static final Pattern STATION_IDENTIFIER =
            Pattern.compile("\"stationIdentifier\"\s*:\s*\"([^\"]+)\"");

    /** {@code "forecast": "https://api.weather.gov/gridpoints/BOU/62,61/forecast"} in a /points reply. */
    private static final Pattern FORECAST_URL =
            Pattern.compile("\"forecast\"\s*:\s*\"([^\"]+)\"");

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

    /**
     * Resolves a coordinate to the nearest NWS observation station, or {@code null} when Weather.gov
     * reports none.
     *
     * <p>This exists because {@code WaterStation.MLI} is a water-gauge id (a USGS site number), never
     * an NWS call sign — fetching observations by {@code mli} 404s for every US station. The answer is
     * cached in the database, so this runs once per station, not once per cycle.
     *
     * <p>Two API quirks: Weather.gov rejects more than 4 decimal places on a point with an
     * {@code AdjustPointPrecision} error, and answers {@code /points} with a 301 redirect that must be
     * followed ({@link HttpURLConnection} does that for GET by default).
     */
    @Retry(name = "weatherGov")
    @CircuitBreaker(name = "weatherGov")
    @RateLimiter(name = "weatherGov")
    public String findNearestStation(double latitude, double longitude) throws IOException {
        String point = String.format(Locale.ROOT, "%.4f,%.4f", latitude, longitude);
        String url = baseUrl.replaceAll("/+$", "") + "/points/" + point + "/stations";

        HttpURLConnection connection = open(url);
        try {
            int status = connection.getResponseCode();
            if (status == HttpURLConnection.HTTP_NOT_FOUND) {
                // Outside NWS coverage entirely (e.g. a non-US coordinate). A permanent answer.
                return null;
            }
            if (status != HttpURLConnection.HTTP_OK) {
                throw new IOException("Weather.gov returned HTTP " + status + " for point " + point);
            }

            try (InputStream inputStream = connection.getInputStream()) {
                byte[] body = inputStream.readNBytes(maxResponseBytes + 1);
                if (body.length > maxResponseBytes) {
                    throw new IOException("Weather.gov response exceeded " + maxResponseBytes
                            + " bytes for point " + point);
                }
                return firstStationIdentifier(new String(body, StandardCharsets.UTF_8));
            }
        } finally {
            connection.disconnect();
        }
    }

    /**
     * Pulls the first {@code stationIdentifier} out of the GeoJSON feature collection. Deliberately a
     * regex rather than a JSON parse: this class stores payloads verbatim and has no parser wired in,
     * and the field is a simple quoted string in a well-known government schema.
     */
    static String firstStationIdentifier(String json) {
        Matcher matcher = STATION_IDENTIFIER.matcher(json);
        return matcher.find() ? matcher.group(1) : null;
    }

    /**
     * Fetches the GRIDPOINT FORECAST for a coordinate: the actual multi-day forecast, not the latest
     * observation.
     *
     * <p>Two calls, because the forecast URL is not derivable from a coordinate: {@code /points/{lat,lon}}
     * answers with the gauge's grid cell and, in {@code properties.forecast}, the URL of that cell's
     * forecast. The same two API quirks as {@link #findNearestStation} apply -- coordinates must be
     * rounded to 4 decimal places, and {@code /points} answers with a 301 that must be followed.
     *
     * <p>Requested with {@code units=si}, so the periods come back in degC and km/h and the converter
     * has no unit conversion to do at all.
     *
     * <p>Returns {@code null} when the coordinate is outside NWS coverage, which the caller turns into
     * a skip rather than a failure -- the same treatment an unpublished feed gets.
     */
    @Retry(name = "weatherGov")
    @CircuitBreaker(name = "weatherGov")
    @RateLimiter(name = "weatherGov")
    public String fetchGridpointForecast(double latitude, double longitude) throws IOException {
        String point = String.format(Locale.ROOT, "%.4f,%.4f", latitude, longitude);
        String forecastUrl = findForecastUrl(point);
        if (forecastUrl == null) {
            return null;
        }

        String url = forecastUrl + (forecastUrl.contains("?") ? "&" : "?") + "units=si";
        HttpURLConnection connection = open(url);
        try {
            int status = connection.getResponseCode();
            if (status == HttpURLConnection.HTTP_NOT_FOUND) {
                return null;
            }
            if (status != HttpURLConnection.HTTP_OK) {
                throw new IOException("Weather.gov returned HTTP " + status + " for forecast " + url);
            }
            return readBody(connection, "forecast " + point);
        } finally {
            connection.disconnect();
        }
    }

    /** Reads {@code properties.forecast} out of a {@code /points} response, or null outside coverage. */
    private String findForecastUrl(String point) throws IOException {
        String url = baseUrl.replaceAll("/+$", "") + "/points/" + point;
        HttpURLConnection connection = open(url);
        try {
            int status = connection.getResponseCode();
            if (status == HttpURLConnection.HTTP_NOT_FOUND) {
                // Outside NWS coverage entirely (e.g. a non-US coordinate). A permanent answer.
                return null;
            }
            if (status != HttpURLConnection.HTTP_OK) {
                throw new IOException("Weather.gov returned HTTP " + status + " for point " + point);
            }
            return forecastUrlOf(readBody(connection, "point " + point));
        } finally {
            connection.disconnect();
        }
    }

    /**
     * Pulls {@code properties.forecast} from a {@code /points} document. Regex for the same reason
     * {@link #firstStationIdentifier} uses one: a single quoted string in a stable government schema.
     */
    static String forecastUrlOf(String json) {
        Matcher matcher = FORECAST_URL.matcher(json);
        return matcher.find() ? matcher.group(1) : null;
    }

    /** Reads a response body, enforcing the same size ceiling every other call here uses. */
    private String readBody(HttpURLConnection connection, String what) throws IOException {
        try (InputStream inputStream = connection.getInputStream()) {
            byte[] body = inputStream.readNBytes(maxResponseBytes + 1);
            if (body.length > maxResponseBytes) {
                throw new IOException("Weather.gov response exceeded " + maxResponseBytes
                        + " bytes for " + what);
            }
            return new String(body, StandardCharsets.UTF_8);
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
