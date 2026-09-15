package com.fishfind.docapi.web;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.DocumentStore;
import com.fishfind.docapi.repo.NewsAdminCommandRepository;
import com.fishfind.docapi.repo.NewsAdminCommandRepository.NewsAdminPublishRequest;
import com.fishfind.docapi.repo.NewsAdminCommandRepository.PhotoUpdateResult;
import com.fishfind.docapi.repo.NewsAdminCommandRepository.PublishResult;
import com.fishfind.docapi.repo.NewsDocumentCache;
import com.fishfind.docapi.repo.NewsQueryCache;
import com.fishfind.docapi.repo.NewsQueryRepository;
import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.Base64;
import java.util.Locale;
import java.util.regex.Pattern;

/**
 * News-admin write endpoints under {@code /api/v1/news/admin}, backing {@code fishfind-frontend}'s
 * {@code Editor/AddNews.aspx} authoring page now that it no longer talks to SQL Server's
 * {@code dbo.news} directly (that table is being dropped -- see
 * {@code fishfind-frontend/Editor/CLAUDE.md}, 2026-09-14 session).
 *
 * <p>Deliberately a separate controller from {@link NewsController}: these three operations mutate
 * the flat {@code news} row (title, author, paragraphs, photo slots, …), a different shape from both
 * {@link NewsController}'s read queries and the generic JSON-document CRUD
 * {@link AbstractDocumentController} exposes on the same base path (which stays SQL-Server-backed --
 * see {@code NewsDocumentService}). The {@code /admin} prefix keeps this surface visually and
 * structurally separate from both.
 *
 * <p>No admin check happens here. The frontend page is already admin-gated server-side
 * ({@code Page_Load} redirects a non-admin before rendering), and every other write endpoint on this
 * service (river-fish upsert, description/source/mouth patch, regulation upsert) follows the same
 * rule: the gateway's signed JWT proves the caller is a genuine, signed-in site session, and the
 * frontend decides who is allowed to reach the page that calls it. Adding a second admin check here
 * would duplicate a decision this service has no independent way to make correctly.
 *
 * <ul>
 *   <li>{@code POST /api/v1/news/admin/draft} — purge stale drafts, create a fresh one;</li>
 *   <li>{@code PATCH /api/v1/news/admin/{id}} — save the article's fields and publish it;</li>
 *   <li>{@code PATCH /api/v1/news/admin/{id}/photo/{index}} — replace one paragraph photo slot.</li>
 * </ul>
 */
@RestController
@RequestMapping(value = "/api/v1/news/admin", produces = MediaType.APPLICATION_JSON_VALUE)
public class NewsAdminController {

    /** Canonical 8-4-4-4-12 hex GUID -- same shape {@link NewsController} requires for its guid paths. */
    private static final Pattern GUID = Pattern.compile(
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");

    private static final DateTimeFormatter STAMP_FORMAT = DateTimeFormatter.ISO_LOCAL_DATE_TIME;

    private static final Logger log = LoggerFactory.getLogger(NewsAdminController.class);

    private final NewsAdminCommandRepository commandRepository;
    private final ObjectMapper objectMapper;
    private final NewsQueryRepository queryRepository;
    private final DocumentStore newsStore;

    /**
     * {@code queryRepository}/{@code newsStore} are the same beans {@code NewsController}/
     * {@code NewsDocumentService} inject -- under the default (no-DB) profile they are plain,
     * uncached implementations, and under {@code jdbc} they are {@link NewsQueryCache}/
     * {@link NewsDocumentCache}. Injected by interface/base type (not the concrete cache classes
     * directly, unlike {@code NewsCacheEvictor}) so this controller works in both profiles; the
     * cache clear after a successful write is a no-op instanceof-check when there is no cache to
     * clear.
     */
    public NewsAdminController(NewsAdminCommandRepository commandRepository, ObjectMapper objectMapper,
                               NewsQueryRepository queryRepository,
                               @Qualifier("newsStore") DocumentStore newsStore) {
        this.commandRepository = commandRepository;
        this.objectMapper = objectMapper;
        this.queryRepository = queryRepository;
        this.newsStore = newsStore;
    }

    /**
     * Confirmed live 2026-09-15: an article published through {@code PATCH /{id}} did not appear on
     * {@code /news/list} because nothing here ever told {@link NewsQueryCache} its cached list/
     * home-page rows were stale -- only {@code POST /news/import} did that. Called after a
     * successful {@link #publish}/{@link #updatePhoto}, so the next read repopulates from the
     * database instead of serving the pre-write snapshot. Also drops {@link NewsDocumentCache} for
     * the same reason (a document positively cached before this write, or a remembered 404 for an
     * id this write just created, both go stale) -- harmless to clear in full for a low-frequency
     * admin write path, and this controller has no way to target just one id in that cache.
     */
    private void evictNewsCaches() {
        if (queryRepository instanceof NewsQueryCache) {
            ((NewsQueryCache) queryRepository).clear();
        }
        if (newsStore instanceof NewsDocumentCache) {
            ((NewsDocumentCache) newsStore).clear();
        }
        log.info("News caches evicted after an admin write");
    }

    /**
     * Purges every unpublished draft and creates a fresh one -- the gateway equivalent of
     * {@code AddNews.aspx.cs}'s old {@code Page_Load}, which ran the same purge-then-insert every
     * time the page was opened (not new behaviour introduced here).
     *
     * @return {@code {id}} in the response envelope
     */
    @PostMapping("/draft")
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<JsonNode> createDraft() {
        String id = commandRepository.createDraft();
        ObjectNode node = objectMapper.createObjectNode();
        node.put("id", id);
        return ApiResponse.ok(node);
    }

    /**
     * Saves an article's editable fields and marks it published. An id with no existing row creates
     * one rather than failing, mirroring the page's own recovery when its draft has been purged out
     * from under it (see the 2026-07-07 fix noted in {@code Editor/CLAUDE.md}).
     *
     * @param id   the article id being saved
     * @param body a JSON object: {@code title} (required, non-blank), plus {@code author},
     *             {@code source}, {@code sourceLink}, {@code authorLink}, {@code stamp}
     *             ({@code yyyy-MM-ddTHH:mm:ss}, defaulting to now and clamped to the last year — the
     *             same rule {@code ButtonSubmitAddNews_Click} applied), {@code videoLink},
     *             {@code paragraph0/1/2}, {@code country}, {@code lakeId}, {@code fish1Id/2Id/3Id}
     *             (each a bare GUID or omitted)
     * @return {@code {id, action}} in the response envelope
     * @throws InvalidDocumentException if the body is missing/malformed or {@code title} is blank (→ 400)
     */
    @PatchMapping(value = "/{id}", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ApiResponse<JsonNode> publish(@PathVariable String id, @RequestBody(required = false) String body) {
        String newsId = requireGuid(id);
        JsonNode fields = requireObject(body);

        String title = text(fields, "title");
        if (title == null) {
            throw new InvalidDocumentException("title is required and must not be blank");
        }

        NewsAdminPublishRequest request = new NewsAdminPublishRequest(
                newsId,
                title,
                text(fields, "author"),
                text(fields, "source"),
                text(fields, "sourceLink"),
                text(fields, "authorLink"),
                parseStamp(text(fields, "stamp")),
                text(fields, "videoLink"),
                text(fields, "paragraph0"),
                text(fields, "paragraph1"),
                text(fields, "paragraph2"),
                text(fields, "country"),
                guidOrNull(text(fields, "lakeId")),
                guidOrNull(text(fields, "fish1Id")),
                guidOrNull(text(fields, "fish2Id")),
                guidOrNull(text(fields, "fish3Id")));

        PublishResult result = commandRepository.publish(request);
        evictNewsCaches();

        ObjectNode out = objectMapper.createObjectNode();
        out.put("id", result.newsId());
        out.put("action", result.action());
        return ApiResponse.ok(out);
    }

    /**
     * Replaces one paragraph-photo slot on an existing article/draft.
     *
     * @param id    the article id
     * @param index 0, 1, or 2
     * @param body  a JSON object: {@code photoBase64} (required), plus optional {@code author}/
     *              {@code alt} — either omitted (or {@code null}) leaves that column's current value
     *              in place, matching {@code GetPicture}/{@code ImportPhoto} (bytes only) vs.
     *              {@code btnBriefUpload_Click} (bytes + author + alt) in the original page
     * @return {@code {id, index, updated:true}} in the response envelope
     * @throws InvalidDocumentException  if {@code index} is not 0/1/2, the body is missing/malformed,
     *                                    or {@code photoBase64} is missing or not valid base64 (→ 400)
     * @throws DocumentNotFoundException if no article/draft exists for {@code id} (→ 404)
     */
    @PatchMapping(value = "/{id}/photo/{index}", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ApiResponse<JsonNode> updatePhoto(@PathVariable String id, @PathVariable int index,
                                             @RequestBody(required = false) String body) {
        String newsId = requireGuid(id);
        if (index < 0 || index > 2) {
            throw new InvalidDocumentException("index must be 0, 1, or 2");
        }
        JsonNode fields = requireObject(body);

        String photoBase64 = text(fields, "photoBase64");
        if (photoBase64 == null) {
            throw new InvalidDocumentException("photoBase64 is required and must not be blank");
        }
        byte[] photo;
        try {
            // MIME decoder, not the strict basic one: tolerates embedded newlines, which is exactly
            // the shape MySQL's TO_BASE64() emits (76-char line wraps, confirmed live 2026-09-15
            // re-applying a photo fetched from GET /news/{id}) -- a caller round-tripping that output
            // straight back through this endpoint must not be rejected for whitespace the source
            // itself put there. Still correctly decodes an unwrapped single-line value.
            photo = Base64.getMimeDecoder().decode(photoBase64);
        } catch (IllegalArgumentException ex) {
            throw new InvalidDocumentException("photoBase64 is not valid base64", ex);
        }

        PhotoUpdateResult result = commandRepository.updatePhoto(
                newsId, index, photo, text(fields, "author"), text(fields, "alt"));

        if (!result.found()) {
            throw new DocumentNotFoundException(DocumentType.NEWS, newsId);
        }
        evictNewsCaches();

        ObjectNode out = objectMapper.createObjectNode();
        out.put("id", newsId);
        out.put("index", index);
        out.put("updated", result.updated());
        return ApiResponse.ok(out);
    }

    /** Validates a path id is a canonical 8-4-4-4-12 hex GUID, lower-cased for a stable key. */
    private static String requireGuid(String id) {
        String trimmed = id == null ? "" : id.trim();
        if (!GUID.matcher(trimmed).matches()) {
            throw new InvalidDocumentException("id must be a GUID (8-4-4-4-12 hex)");
        }
        return trimmed.toLowerCase(Locale.ROOT);
    }

    /** {@code null} unless {@code value} is itself a canonical GUID -- an invalid tag is dropped, not stored. */
    private static String guidOrNull(String value) {
        return (value != null && GUID.matcher(value).matches()) ? value.toLowerCase(Locale.ROOT) : null;
    }

    /**
     * Parses {@code yyyy-MM-ddTHH:mm:ss[.fff]}, defaulting to now on a missing/blank/unparseable
     * value and clamping to now when the result is in the future or more than a year in the past --
     * the exact rule {@code ButtonSubmitAddNews_Click} applied to its date textbox.
     */
    private static Timestamp parseStamp(String value) {
        LocalDateTime now = LocalDateTime.now();
        LocalDateTime parsed = now;

        if (value != null) {
            try {
                parsed = LocalDateTime.parse(value, STAMP_FORMAT);
            } catch (DateTimeParseException ex) {
                parsed = now;
            }
        }
        if (parsed.isAfter(now) || parsed.isBefore(now.minusYears(1))) {
            parsed = now;
        }
        return Timestamp.valueOf(parsed);
    }

    /** Validates a PATCH body is a non-empty, well-formed JSON object. */
    private JsonNode requireObject(String body) {
        if (body == null || body.isBlank()) {
            throw new InvalidDocumentException("Request body must be a non-empty JSON object");
        }
        JsonNode node;
        try {
            node = objectMapper.readTree(body);
        } catch (JsonProcessingException ex) {
            throw new InvalidDocumentException("Request body is not well-formed JSON: " + ex.getOriginalMessage(), ex);
        }
        if (!node.isObject()) {
            throw new InvalidDocumentException("Request body must be a JSON object");
        }
        return node;
    }

    /** A non-blank text field, or null -- JSON null, a missing field and an empty/blank string all collapse. */
    private static String text(JsonNode node, String field) {
        JsonNode value = node.path(field);
        if (value.isMissingNode() || value.isNull()) {
            return null;
        }
        String s = value.asText("");
        return s.isBlank() ? null : s;
    }
}
