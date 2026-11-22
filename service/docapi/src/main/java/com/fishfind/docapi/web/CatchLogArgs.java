package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.service.InvalidDocumentException;

import java.security.SecureRandom;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeParseException;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.UUID;

/**
 * Argument rules for a catch log written as JSON ({@code POST /api/v1/catch}, {@code PATCH /api/v1/catch/{id}}):
 * trimmed bounded strings, numbers in range, booleans, units, the catch date. Every check raises an
 * {@link InvalidDocumentException} (400) before any SQL. Moved here from the retired {@code McpToolCatalog} in
 * 1.43.0, unchanged; the MCP server (mcp-env) calls these routes and relays their 400 messages to the model.
 */
final class CatchLogArgs {

    /**
     * The portal form's conditions ({@code ddlWeatherCondition}, {@code icon:text}): a {@code weather} value
     * naming one of them (any case) is stored with its icon, anything else as free text with none.
     */
    static final Map<String, String> WEATHER_ICONS = Map.of(
            "clear", "01d", "partly cloudy", "02d", "cloudy", "03d", "overcast", "04d",
            "rain", "10d", "thunderstorm", "11d", "snow", "13d", "fog", "50d");

    private static final SecureRandom RANDOM = new SecureRandom();

    private CatchLogArgs() {
    }

    /** A trimmed string argument, or {@code null} when absent/blank; a non-string is a caller error. */
    static String optionalText(JsonNode args, String key) {
        JsonNode node = args.get(key);
        if (node == null || node.isNull()) return null;
        if (!node.isTextual()) {
            throw new InvalidDocumentException(key + " must be a string");
        }
        String v = node.asText().trim();
        return v.isEmpty() ? null : v;
    }

    /** A trimmed string of at most {@code max} characters, or null; longer is a caller error, never cut. */
    static String boundedText(JsonNode args, String key, int max) {
        String v = optionalText(args, key);
        if (v != null && v.length() > max) {
            throw new InvalidDocumentException(key + " must not exceed " + max + " characters");
        }
        return v;
    }

    /** A text field: {@code fallback} when the key is absent, else the bounded value (null clears it). */
    static String text(JsonNode args, String key, int max, String fallback) {
        return args.has(key) ? boundedText(args, key, max) : fallback;
    }

    /** A number in (min, max] for 0 minimums, [min, max] otherwise; null when absent. */
    static Double optionalNumber(JsonNode args, String key, double min, double max) {
        JsonNode node = args.get(key);
        if (node == null || node.isNull()) return null;
        if (!node.isNumber()) {
            throw new InvalidDocumentException(key + " must be a number");
        }
        double v = node.asDouble();
        boolean low = min == 0 ? v <= 0 : v < min;
        if (low || v > max || Double.isNaN(v)) {
            throw new InvalidDocumentException(key + " must be " + (min == 0 ? "above 0" : "at least " + min)
                    + " and at most " + max);
        }
        return v;
    }

    static Boolean optionalBoolean(JsonNode args, String key) {
        JsonNode node = args.get(key);
        if (node == null || node.isNull()) return null;
        if (!node.isBoolean()) {
            throw new InvalidDocumentException(key + " must be true or false");
        }
        return node.asBoolean();
    }

    /** A unit argument, lower-cased and checked against {@code allowed}; null when absent or JSON null. */
    static String unitValue(JsonNode args, String key, Set<String> allowed) {
        String unit = optionalText(args, key);
        if (unit == null) return null;
        unit = unit.toLowerCase(Locale.ROOT);
        if (!allowed.contains(unit)) {
            throw new InvalidDocumentException(key + " must be one of " + String.join(", ", new TreeSet<>(allowed)));
        }
        return unit;
    }

    /** A unit must come with its value and only with it. */
    static void pair(Double value, String unit, String valueKey, String unitKey) {
        if (value != null && unit == null) throw new InvalidDocumentException(unitKey + " is required with " + valueKey);
        if (value == null && unit != null) throw new InvalidDocumentException(unitKey + " given without " + valueKey);
    }

    /** YYYY-MM-DD (stored as midnight) or YYYY-MM-DDTHH:MM[:SS]; null when absent; never in the future. */
    static LocalDateTime catchDate(String value) {
        if (value == null) return null;
        LocalDateTime parsed;
        try {
            parsed = value.length() <= 10 ? LocalDate.parse(value).atStartOfDay() : LocalDateTime.parse(value);
        } catch (DateTimeParseException ex) {
            throw new InvalidDocumentException("catchDate must be YYYY-MM-DD or YYYY-MM-DDTHH:MM");
        }
        if (parsed.isAfter(LocalDateTime.now(ZoneOffset.UTC).plusDays(1))) {
            throw new InvalidDocumentException("catchDate is in the future");
        }
        return parsed;
    }

    /** A time-ordered (version 7) UUID, like the portal's {@code Guid.CreateVersion7()} for catch logs and spots. */
    static String uuidV7() {
        long millis = System.currentTimeMillis();
        long rand = RANDOM.nextLong();
        long msb = (millis << 16) | 0x7000L | (RANDOM.nextInt() & 0x0fffL);
        long lsb = (rand & 0x3fffffffffffffffL) | 0x8000000000000000L;
        return new UUID(msb, lsb).toString();
    }

    /** Output keys that hold a photo or a gallery, at any depth (matched case-insensitively). */
    private static final Set<String> PHOTO_KEYS = Set.of("pic", "pics", "img", "imgs", "image", "images", "picture", "pictures");

    /**
     * Removes every photo field from a stored log, in place, at any depth: a key in {@link #PHOTO_KEYS}, or any key
     * starting with {@code photo}. The photo routes answer with a count, never bytes.
     */
    static JsonNode stripPhotos(JsonNode node) {
        if (node instanceof com.fasterxml.jackson.databind.node.ObjectNode object) {
            object.properties().removeIf(e -> {
                String k = e.getKey().toLowerCase(Locale.ROOT);
                return PHOTO_KEYS.contains(k) || k.startsWith("photo");
            });
            object.forEach(CatchLogArgs::stripPhotos);
        } else if (node != null && node.isArray()) {
            node.forEach(CatchLogArgs::stripPhotos);
        }
        return node;
    }
}
