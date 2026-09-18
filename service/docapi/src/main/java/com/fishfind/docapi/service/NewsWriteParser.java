package com.fishfind.docapi.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.repo.NewsWrite;

import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeParseException;
import java.util.Base64;
import java.util.Locale;
import java.util.regex.Pattern;

/**
 * Turns a news request body into a validated {@link NewsWrite}. Two body shapes, the same two the
 * SQL Server procedures accepted, so no caller has to change:
 *
 * <ul>
 *   <li>{@link #fromDocument} -- {@code POST /api/v1/news} and {@code PUT /api/v1/news/{id}}: the
 *       snake_case article document ({@code author_link}, {@code credit}, {@code photo_alt},
 *       {@code lake_id}, one base64 {@code photo}), as {@code dbo.sp_news_doc_add}/{@code _update}
 *       read it.</li>
 *   <li>{@link #fromInterchange} -- {@code POST /api/v1/news/import}: the camelCase interchange
 *       document {@code GET /news/export/{id}} produces ({@code authorLink}, {@code fish1Id},
 *       {@code photo0..2}), as {@code dbo.sp_news_import} read it.</li>
 * </ul>
 *
 * <p><strong>Every client error is a 400 from here, before any database call.</strong> Under SQL
 * Server a blank title was a {@code RAISERROR} and bad base64 an XML-cast failure -- both 500s, and
 * both counted against the shared {@code sqlBreaker}. Over-long values were silently truncated by
 * {@code OPENJSON ... WITH (nvarchar(n))}; MySQL in strict mode would reject them as a 500 instead, so
 * they are rejected here, naming the field and its limit. Limits are the MySQL column sizes
 * ({@code envfish-db/mysql/script01_createTable.sql}), counted in code points as MySQL counts them.
 *
 * <p>Kept deliberately lenient, as {@code TRY_CONVERT} was: a {@code lake_id}/fish id that is not a
 * GUID is dropped rather than rejected, and an unparseable date is treated as absent (now on insert,
 * the stored stamp on update).
 */
public final class NewsWriteParser {

    static final int TITLE_MAX = 128;
    static final int AUTHOR_MAX = 500;
    static final int LINK_MAX = 1024;
    static final int SOURCE_MAX = 255;
    static final int VIDEO_LINK_MAX = 255;
    static final int PHOTO_AUTHOR_MAX = 64;
    static final int PHOTO_ALT_MAX = 128;

    /** How many species ids an article carries -- the fish1/fish2/fish3 columns. */
    static final int MAX_FISH = 3;

    private static final Pattern GUID = Pattern.compile(
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");
    private static final Pattern COUNTRY = Pattern.compile("[A-Za-z]{2}");
    private static final Pattern WHITESPACE = Pattern.compile("\\s+");

    private NewsWriteParser() {
    }

    /**
     * Parses the snake_case article document of {@code POST}/{@code PUT /api/v1/news}.
     *
     * <p>Species come from {@code fishes: [{id}, ...]} (the first three, by position -- the shape
     * {@code dbo.sp_news_doc_add} read) when that key is present, and otherwise from
     * {@code fish1_id}/{@code fish2_id}/{@code fish3_id} -- the shape {@code GET /api/v1/news/{id}}
     * returns, so a GET body can be edited and PUT straight back without losing its species. Without
     * that fallback such a round trip would null all three, because a PUT is a full replace.
     */
    public static NewsWrite fromDocument(JsonNode doc) {
        requireObject(doc);
        String[] fish = doc.has("fishes") ? fishesArray(doc.get("fishes"))
                : new String[] {guid(doc, "fish1_id"), guid(doc, "fish2_id"), guid(doc, "fish3_id")};
        return new NewsWrite(
                title(doc, "title"),
                text(doc, "author", AUTHOR_MAX),
                text(doc, "author_link", LINK_MAX),
                text(doc, "source", SOURCE_MAX),
                text(doc, "source_link", LINK_MAX),
                text(doc, "video_link", VIDEO_LINK_MAX),
                text(doc, "paragraph0", Integer.MAX_VALUE),
                text(doc, "paragraph1", Integer.MAX_VALUE),
                text(doc, "paragraph2", Integer.MAX_VALUE),
                country(doc, "country"),
                stamp(doc, "date"),
                guid(doc, "lake_id"),
                fish[0], fish[1], fish[2],
                new NewsWrite.Photo(base64(doc, "photo"),
                        text(doc, "credit", PHOTO_AUTHOR_MAX),
                        text(doc, "photo_alt", PHOTO_ALT_MAX)),
                NewsWrite.Photo.NONE,
                NewsWrite.Photo.NONE);
    }

    /** Parses the camelCase interchange document of {@code POST /api/v1/news/import}. */
    public static NewsWrite fromInterchange(JsonNode doc) {
        requireObject(doc);
        return new NewsWrite(
                title(doc, "title"),
                text(doc, "author", AUTHOR_MAX),
                text(doc, "authorLink", LINK_MAX),
                text(doc, "source", SOURCE_MAX),
                text(doc, "sourceLink", LINK_MAX),
                text(doc, "videoLink", VIDEO_LINK_MAX),
                text(doc, "paragraph0", Integer.MAX_VALUE),
                text(doc, "paragraph1", Integer.MAX_VALUE),
                text(doc, "paragraph2", Integer.MAX_VALUE),
                country(doc, "country"),
                stamp(doc, "date"),
                guid(doc, "lakeId"),
                guid(doc, "fish1Id"), guid(doc, "fish2Id"), guid(doc, "fish3Id"),
                interchangePhoto(doc, 0),
                interchangePhoto(doc, 1),
                interchangePhoto(doc, 2));
    }

    private static NewsWrite.Photo interchangePhoto(JsonNode doc, int slot) {
        return new NewsWrite.Photo(
                base64(doc, "photo" + slot),
                text(doc, "photoAuthor" + slot, PHOTO_AUTHOR_MAX),
                text(doc, "photoAlt" + slot, PHOTO_ALT_MAX));
    }

    private static void requireObject(JsonNode doc) {
        if (doc == null || !doc.isObject()) {
            throw new InvalidDocumentException("Request body must be a JSON object");
        }
    }

    private static String title(JsonNode doc, String field) {
        String title = text(doc, field, TITLE_MAX);
        if (title == null) {
            throw new InvalidDocumentException("\"" + field + "\" is required and must not be blank");
        }
        return title;
    }

    /**
     * A string field, or {@code null} when missing, JSON {@code null} or blank. A number/boolean is
     * accepted as its text; an object or array is a 400. Over {@code max} code points is a 400.
     */
    static String text(JsonNode doc, String field, int max) {
        JsonNode value = doc.get(field);
        if (value == null || value.isNull()) {
            return null;
        }
        if (!value.isValueNode()) {
            throw new InvalidDocumentException("\"" + field + "\" must be a string");
        }
        String s = value.asText();
        if (s.isBlank()) {
            return null;
        }
        if (max != Integer.MAX_VALUE && s.codePointCount(0, s.length()) > max) {
            throw new InvalidDocumentException(
                    "\"" + field + "\" is longer than its " + max + "-character limit");
        }
        return s;
    }

    /** An ISO-2 country code, upper-cased; blank/absent is {@code null}, anything else is a 400. */
    private static String country(JsonNode doc, String field) {
        String value = text(doc, field, Integer.MAX_VALUE);
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        if (!COUNTRY.matcher(trimmed).matches()) {
            throw new InvalidDocumentException("\"" + field + "\" must be a two-letter country code");
        }
        return trimmed.toUpperCase(Locale.ROOT);
    }

    /** A canonical GUID, lower-cased, or {@code null} -- an invalid tag is dropped, not rejected. */
    private static String guid(JsonNode doc, String field) {
        JsonNode value = doc.get(field);
        return value == null ? null : guidOrNull(value.isValueNode() ? value.asText() : null);
    }

    private static String guidOrNull(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return GUID.matcher(trimmed).matches() ? trimmed.toLowerCase(Locale.ROOT) : null;
    }

    /**
     * The first three {@code fishes[].id}, by position: an entry without a valid id leaves its slot
     * empty rather than shifting the rest up, as {@code dbo.sp_news_doc_add}'s {@code ROW_NUMBER()}
     * did. JSON {@code null} or an empty array clears all three.
     */
    private static String[] fishesArray(JsonNode fishes) {
        String[] out = new String[MAX_FISH];
        if (fishes == null || fishes.isNull()) {
            return out;
        }
        if (!fishes.isArray()) {
            throw new InvalidDocumentException("\"fishes\" must be an array of {\"id\": ...} objects");
        }
        for (int i = 0; i < Math.min(MAX_FISH, fishes.size()); i++) {
            JsonNode id = fishes.get(i).get("id");
            out[i] = id == null ? null : guidOrNull(id.isValueNode() ? id.asText() : null);
        }
        return out;
    }

    /**
     * {@code yyyy-MM-dd} (the documents' shape, read as midnight) or an ISO local date-time;
     * anything else is treated as absent, as {@code TRY_CONVERT(datetime2, ...)} did.
     */
    static Timestamp stamp(JsonNode doc, String field) {
        String value = text(doc, field, Integer.MAX_VALUE);
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        try {
            return Timestamp.valueOf(LocalDate.parse(trimmed).atStartOfDay());
        } catch (DateTimeParseException ignored) {
            // not a bare date -- try a date-time
        }
        try {
            return Timestamp.valueOf(LocalDateTime.parse(trimmed));
        } catch (DateTimeParseException ignored) {
            return null;
        }
    }

    /**
     * Decodes a base64 photo. Whitespace is stripped first, because MySQL's {@code TO_BASE64} -- which
     * produces {@code GET /api/v1/news/{id}}'s {@code photo} -- wraps its output every 76 characters, and
     * that body must be PUT-able straight back. After that the decoder is strict: anything that is not
     * base64 is a 400, where the lenient MIME decoder would silently skip it and store garbage.
     */
    static byte[] base64(JsonNode doc, String field) {
        String value = text(doc, field, Integer.MAX_VALUE);
        if (value == null) {
            return null;
        }
        try {
            return Base64.getDecoder().decode(WHITESPACE.matcher(value).replaceAll(""));
        } catch (IllegalArgumentException ex) {
            throw new InvalidDocumentException("\"" + field + "\" is not valid base64", ex);
        }
    }
}
