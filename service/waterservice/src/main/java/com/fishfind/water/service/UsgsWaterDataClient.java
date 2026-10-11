package com.fishfind.water.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.water.domain.UsgsObservation;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

/**
 * Reads US readings from the USGS Water Data API ({@code api.waterdata.usgs.gov/ogcapi}), which replaces the
 * legacy WaterServices {@code nwis/iv} feed (decommissioned 2027-02-22).
 *
 * <p>The legacy feed was called once per station — about 9,500 calls per hourly cycle. The new API is
 * rate-limited per key, so a cycle instead pages through the whole {@code latest-continuous} collection (the
 * newest value of every US series, ~2-3 requests of up to 50,000 rows) and the processor picks its stations
 * out of that snapshot.
 *
 * <p>Transient failures are retried via {@code httpRetry}; sustained failures open the {@code usFeed}
 * breaker. A failed snapshot fails the whole US pass; the next cycle (and the redundant C# service) covers it.
 */
@Service
public class UsgsWaterDataClient {
    private static final Logger log = LoggerFactory.getLogger(UsgsWaterDataClient.class);

    private static final String API_KEY_HEADER = "X-Api-Key";
    private static final String SITE_PREFIX = "USGS-";
    private static final int PAGE_LIMIT = 50000;
    private static final int MAX_PAGES = 20;
    private static final int TIME_ZONE_BATCH_SIZE = 200;
    private static final String INSTANT_PROPERTIES = "monitoring_location_id,parameter_code,statistic_id,time,value";

    private final RestClient restClient;
    private final String baseUrl;
    private final String apiKey;

    // Site time zones never change, so they are looked up once per process and kept.
    private final Map<String, ZoneId> timeZones = new ConcurrentHashMap<>();

    public UsgsWaterDataClient(
            RestClient waterSourceRestClient,
            @Value("${water.worker.usgs-base-url:https://api.waterdata.usgs.gov/ogcapi/v1/collections}") String baseUrl,
            @Value("${USGS_API_KEY:}") String apiKey) {
        this.restClient = waterSourceRestClient;
        this.baseUrl = baseUrl.replaceAll("/+$", "");
        this.apiKey = apiKey;
    }

    /**
     * Fetches the latest value of every current USGS series, keyed by bare site number (the
     * {@code vwWaterStation} MLI, without the {@code USGS-} prefix).
     *
     * @param mli restrict the snapshot to one site (startup verification); {@code null} for all
     * @return observations per site
     */
    @Retry(name = "httpRetry")
    @CircuitBreaker(name = "usFeed")
    public Map<String, List<UsgsObservation>> fetchLatest(String mli) throws IOException {
        String url = baseUrl + "/latest-continuous/items?f=json&skipGeometry=true&limit=" + PAGE_LIMIT
                + "&properties=" + INSTANT_PROPERTIES;
        if (mli != null && !mli.isBlank()) {
            url += "&monitoring_location_id=" + encode(SITE_PREFIX + mli.trim());
        }

        Map<String, List<UsgsObservation>> snapshot = new HashMap<>();
        int pages = 0;
        int rows = 0;
        for (String next = url; next != null; pages++) {
            if (pages == MAX_PAGES) {
                throw new IllegalStateException(
                        "USGS latest-continuous snapshot did not end after " + MAX_PAGES + " pages; refusing to continue.");
            }

            JsonNode page = getPage(next);
            JsonNode features = page.path("features");
            if (!features.isArray() || features.isEmpty()) {
                break;
            }

            for (JsonNode feature : features) {
                JsonNode p = feature.path("properties");
                String site = stripPrefix(text(p, "monitoring_location_id"));
                UsgsObservation observation = toObservation(p);
                if (site != null && observation != null) {
                    snapshot.computeIfAbsent(site, k -> new ArrayList<>()).add(observation);
                    rows++;
                }
            }

            next = null;
            for (JsonNode link : page.path("links")) {
                if ("next".equals(text(link, "rel"))) {
                    next = text(link, "href");
                }
            }
        }

        log.info("Fetched USGS latest-continuous snapshot. pages={} series={} sites={}", pages, rows, snapshot.size());
        return snapshot;
    }

    /**
     * Makes sure the local time zone of each site is known, looking up only the ones not seen before.
     * Readings are bucketed by the site's local date, as the legacy WaterML timestamps were.
     *
     * @param mlis sites to resolve
     */
    @Retry(name = "httpRetry")
    @CircuitBreaker(name = "usFeed")
    public void ensureTimeZones(Collection<String> mlis) throws IOException {
        List<String> missing = mlis.stream()
                .filter(m -> !timeZones.containsKey(m))
                .collect(Collectors.toCollection(LinkedHashSet::new))
                .stream().toList();

        for (int from = 0; from < missing.size(); from += TIME_ZONE_BATCH_SIZE) {
            List<String> batch = missing.subList(from, Math.min(from + TIME_ZONE_BATCH_SIZE, missing.size()));
            String ids = batch.stream().map(m -> encode(SITE_PREFIX + m)).collect(Collectors.joining(","));
            String url = baseUrl + "/monitoring-locations/items?f=json&skipGeometry=true&limit=" + TIME_ZONE_BATCH_SIZE
                    + "&properties=time_zone_abbreviation,uses_daylight_savings&id=" + ids;

            for (JsonNode feature : getPage(url).path("features")) {
                String site = stripPrefix(text(feature, "id"));
                if (site != null) {
                    JsonNode p = feature.path("properties");
                    timeZones.put(site, resolveTimeZone(
                            text(p, "time_zone_abbreviation"), text(p, "uses_daylight_savings")));
                }
            }

            // A site USGS does not describe falls back to UTC rather than being looked up every cycle.
            for (String site : batch) {
                if (timeZones.putIfAbsent(site, ZoneOffset.UTC) == null) {
                    log.debug("No time zone published for USGS site; using UTC. station={}", site);
                }
            }
        }

        if (!missing.isEmpty()) {
            log.info("Looked up USGS site time zones. sites={}", missing.size());
        }
    }

    /**
     * Returns the local time zone of a site.
     *
     * @param mli bare site number
     * @return the site's zone; UTC when it was never looked up
     */
    public ZoneId timeZoneFor(String mli) {
        return timeZones.getOrDefault(mli, ZoneOffset.UTC);
    }

    /**
     * Maps a USGS {@code time_zone_abbreviation} (always the standard-time name) plus its daylight-saving flag
     * to a zone. DST-observing zones use the IANA zone so the switch dates are right.
     */
    static ZoneId resolveTimeZone(String abbreviation, String usesDaylightSavings) {
        boolean dst = "Y".equalsIgnoreCase(usesDaylightSavings);
        String key = abbreviation == null ? "" : abbreviation.trim().toUpperCase(Locale.ROOT);
        return switch (key) {
            case "EST" -> dst ? ZoneId.of("America/New_York") : ZoneOffset.ofHours(-5);
            case "CST" -> dst ? ZoneId.of("America/Chicago") : ZoneOffset.ofHours(-6);
            case "MST" -> dst ? ZoneId.of("America/Denver") : ZoneOffset.ofHours(-7);
            case "PST" -> dst ? ZoneId.of("America/Los_Angeles") : ZoneOffset.ofHours(-8);
            case "AKST" -> dst ? ZoneId.of("America/Anchorage") : ZoneOffset.ofHours(-9);
            case "HST" -> ZoneOffset.ofHours(-10);
            case "AST" -> dst ? ZoneId.of("America/Halifax") : ZoneOffset.ofHours(-4);
            case "SST" -> ZoneOffset.ofHours(-11);
            case "CHST", "GST" -> ZoneOffset.ofHours(10);
            default -> ZoneOffset.UTC;
        };
    }

    private JsonNode getPage(String url) throws IOException {
        try {
            JsonNode body = restClient.get()
                    .uri(URI.create(url))
                    .headers(h -> {
                        if (apiKey != null && !apiKey.isBlank()) {
                            h.set(API_KEY_HEADER, apiKey);
                        }
                    })
                    .retrieve()
                    .body(JsonNode.class);
            return body == null ? com.fasterxml.jackson.databind.node.MissingNode.getInstance() : body;
        } catch (HttpClientErrorException.TooManyRequests ex) {
            // Not transient on a retry timescale: the hourly quota is spent. Say so plainly.
            throw new IOException("HTTP 429: USGS Water Data API rate limit reached (check USGS_API_KEY).", ex);
        } catch (RestClientException ex) {
            IOException ioCause = findCause(ex, IOException.class);
            if (ioCause != null && !(ex instanceof ResourceAccessException)) {
                // A body cut off mid-read surfaces after clean headers. Rethrown as a ResourceAccessException
                // so httpRetry retries it like any other transport failure.
                throw new ResourceAccessException("I/O error while reading USGS Water Data API response", ioCause);
            }
            throw ex;
        }
    }

    private static UsgsObservation toObservation(JsonNode p) {
        String code = text(p, "parameter_code");
        String time = text(p, "time");
        JsonNode valueNode = p.path("value");
        String value = valueNode.isTextual() ? valueNode.asText() : valueNode.isNumber() ? valueNode.asText() : null;
        if (code == null || code.isBlank() || time == null || value == null || value.isBlank()) {
            return null;
        }

        try {
            return new UsgsObservation(code, text(p, "statistic_id"), OffsetDateTime.parse(time), value.trim());
        } catch (DateTimeParseException ex) {
            return null;
        }
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node.path(field);
        return value.isNull() || value.isMissingNode() ? null : value.asText();
    }

    private static String stripPrefix(String id) {
        return id != null && id.regionMatches(true, 0, SITE_PREFIX, 0, SITE_PREFIX.length())
                && id.length() > SITE_PREFIX.length()
                ? id.substring(SITE_PREFIX.length())
                : null;
    }

    private static String encode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    private static <T extends Throwable> T findCause(Throwable throwable, Class<T> type) {
        Throwable current = throwable;
        while (current != null) {
            if (type.isInstance(current)) {
                return type.cast(current);
            }
            current = current.getCause();
        }
        return null;
    }
}
