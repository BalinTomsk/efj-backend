package com.fishfind.docapi.web;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.NewsQueryRepository;
import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.InvalidDocumentException;
import com.fishfind.docapi.service.NewsDocumentService;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Locale;

/**
 * News endpoints under {@code /api/v1/news}. Inherits the generic JSON-document CRUD
 * ({@code GET/POST/PUT /{id}}) from {@link AbstractDocumentController} and adds the two News-page read
 * queries:
 *
 * <ul>
 *   <li>{@code GET /api/v1/news/list} — one page of the latest news (country filter + pagination);</li>
 *   <li>{@code GET /api/v1/news/default} — the assembled home page;</li>
 *   <li>{@code GET /api/v1/news/featured} — just the two lead articles (with their photos);</li>
 *   <li>{@code GET /api/v1/news/more} — just the "More News" column, in its compact shape.</li>
 * </ul>
 *
 * <p>{@code /featured} and {@code /more} are the two halves of {@code /default}, split because their
 * weights differ by three orders of magnitude (~1 MB of base64 lead photos versus a couple of KB).
 * All three are projections of the <em>same</em> cached assembly, so offering them costs no extra
 * database read.
 *
 * <p>Both queries are delegated to {@link NewsQueryRepository}, which handles DB access via SQL
 * functions and provides in-memory implementations for the no-database profile. The literal
 * {@code /list}, {@code /default}, {@code /featured} and {@code /more} paths are matched ahead of the
 * templated {@code /{id}} handler, so they never collide with a document fetch.
 */
@RestController
@RequestMapping(value = "/api/v1/news", produces = MediaType.APPLICATION_JSON_VALUE)
public class NewsController extends AbstractDocumentController {

    /** Default page size (matches News.aspx {@code nPage}). */
    static final int DEFAULT_LIMIT = 25;
    /** Upper bound on page size. */
    static final int MAX_LIMIT = 200;

    private final NewsQueryRepository queryRepository;
    private final ObjectMapper objectMapper;

    public NewsController(NewsDocumentService service, ObjectMapper objectMapper,
                          NewsQueryRepository queryRepository) {
        super(service, objectMapper);
        this.objectMapper = objectMapper;
        this.queryRepository = queryRepository;
    }

    /**
     * Exports one article as the {@code fn_news_json} interchange document — every field needed to
     * re-create it, with the 3 paragraph photos embedded as base64 (the same format the News.aspx
     * "Save JSON" link and the AddNews "Import from JSON" round-trip use).
     *
     * <p>The literal {@code /export/...} prefix is matched ahead of the templated {@code /{id}} handler,
     * so it never collides with a plain document fetch.
     *
     * @param id the article id
     * @return the interchange JSON nested inside the response envelope
     * @throws DocumentNotFoundException if no article exists for the id (→ 404)
     */
    @GetMapping("/export/{id}")
    public ApiResponse<JsonNode> export(@PathVariable String id) {
        JsonNode document = queryRepository.exportNews(id);
        if (document == null) {
            throw new DocumentNotFoundException(DocumentType.NEWS, id);
        }
        return ApiResponse.ok(document);
    }

    /**
     * Imports one article from an {@code fn_news_json} interchange document, creating a new published
     * article (base64 photos decoded to binary). Returns the new id.
     *
     * @param body the interchange JSON document
     * @return an envelope carrying {@code { "id": <newId> }}
     * @throws InvalidDocumentException if the body is missing or not well-formed JSON (→ 400)
     */
    @PostMapping(value = "/import", consumes = MediaType.APPLICATION_JSON_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<JsonNode> importNews(@RequestBody(required = false) String body) {
        if (body == null || body.isBlank()) {
            throw new InvalidDocumentException("Request body must be a non-empty JSON document");
        }
        try {
            objectMapper.readTree(body);
        } catch (JsonProcessingException ex) {
            throw new InvalidDocumentException("Request body is not well-formed JSON: " + ex.getOriginalMessage(), ex);
        }
        String newId = queryRepository.importNews(body);
        ObjectNode idNode = objectMapper.createObjectNode();
        idNode.put("id", newId);
        return ApiResponse.ok(idNode);
    }

    /**
     * One page of the latest news with optional country filter and pagination.
     *
     * @param country ISO-2 code to filter by, or omitted/blank for all countries (a thin non-CA country
     *                is padded with Canadian news up to 100)
     * @param offset rows to skip (null/negative → 0)
     * @param limit page size (null/&lt;1 → {@value #DEFAULT_LIMIT}; capped at {@value #MAX_LIMIT})
     * @return the page rows plus the grand total, in the response envelope
     * @throws InvalidDocumentException if {@code country} is present but not a 2-letter code (→ 400)
     */
    @GetMapping("/list")
    public ApiResponse<NewsListPage> list(
            @RequestParam(required = false) String country,
            @RequestParam(required = false) Integer offset,
            @RequestParam(required = false) Integer limit) {
        String normalizedCountry = normalizeCountry(country);
        int safeOffset = (offset == null || offset < 0) ? 0 : offset;
        int safeLimit = (limit == null || limit < 1) ? DEFAULT_LIMIT : Math.min(limit, MAX_LIMIT);

        return ApiResponse.ok(queryRepository.list(normalizedCountry, safeOffset, safeLimit));
    }

    /**
     * The assembled home page in display order (lead articles first, then right-column items).
     *
     * @return {@code { "items": [ <news>, ... ] }} in the response envelope
     */
    @GetMapping("/default")
    public ApiResponse<JsonNode> defaultNews() {
        return ApiResponse.ok(queryRepository.defaultNews());
    }

    /**
     * The home page's <strong>featured articles</strong> — the two big lead items, each with its lead
     * photo, byline, both paragraphs and its lake/species tag row. The full per-article document,
     * unchanged from {@code /default}.
     *
     * <p>Split out from {@code /default} because the two halves of that page have wildly different
     * weights: these two items carry the base64 lead photos and are ~1 MB together, while the
     * right-hand column is a couple of kilobytes. A caller rendering only the sidebar should not have
     * to download a megabyte of photos to get it.
     *
     * <p>Served from the same cached assembly as {@code /default} and {@code /more} — all three share
     * one database read, so splitting the endpoint costs no extra query.
     *
     * @return {@code { "items": [ <article>, … ] }} — the lead items in display order
     */
    @GetMapping("/featured")
    public ApiResponse<JsonNode> featuredNews() {
        ArrayNode items = objectMapper.createArrayNode();
        for (JsonNode item : homePageItems()) {
            if (isLead(item)) {
                items.add(item);
            }
        }
        return ApiResponse.ok(wrap(items));
    }

    /**
     * The home page's <strong>"More News"</strong> column — the right-hand items, in the compact shape
     * that section actually renders: headline, source, date, a one-line teaser and the outbound link.
     * No photos, no paragraphs, so the whole response is a couple of kilobytes.
     *
     * <p>Two things are resolved here rather than left to the caller, so this response is sufficient on
     * its own — both mirroring what the page itself does:
     * <ul>
     *   <li>{@code source} falls back to the article's author when the source label is blank;</li>
     *   <li>{@code snippet} is the first line of the body — taken from the database when it supplies
     *       one, otherwise derived here from {@code paragraph0} (falling back to {@code paragraph1}).
     *       Deriving it as a fallback is what lets this endpoint work against a database that has not
     *       had the {@code snippet}-producing view applied.</li>
     * </ul>
     *
     * @return {@code { "items": [ { news_id, date, title, source, link, snippet }, … ] }} in display order
     */
    @GetMapping("/more")
    public ApiResponse<JsonNode> moreNews() {
        ArrayNode items = objectMapper.createArrayNode();
        for (JsonNode item : homePageItems()) {
            if (!isLead(item)) {
                items.add(toMoreItem(item));
            }
        }
        return ApiResponse.ok(wrap(items));
    }

    /** The assembled home page's items, or an empty array if the payload is not the expected shape. */
    private JsonNode homePageItems() {
        JsonNode items = queryRepository.defaultNews().path("items");
        return items.isArray() ? items : objectMapper.createArrayNode();
    }

    /**
     * Whether this item is one of the two big lead articles. {@code with_photo} arrives as a JSON
     * boolean from the SQL Server backing but as a JSON integer 1/0 from MySQL's {@code JSON_OBJECT},
     * and {@code asBoolean} reads both (a non-zero int is true), so neither backing needs special-casing.
     */
    private static boolean isLead(JsonNode item) {
        return item.path("with_photo").asBoolean(false);
    }

    /** Projects a full article document down to what the "More News" column renders. */
    private ObjectNode toMoreItem(JsonNode item) {
        ObjectNode out = objectMapper.createObjectNode();
        out.put("news_id", text(item, "news_id"));
        out.put("date", text(item, "date"));
        out.put("title", text(item, "title"));
        String source = text(item, "source");
        out.put("source", source != null ? source : text(item, "author"));
        out.put("link", text(item, "source_link"));
        out.put("snippet", snippetOf(item));
        return out;
    }

    /**
     * The one-line teaser: whatever the database supplied, else the first line of {@code paragraph0}
     * (falling back to {@code paragraph1}). CR is stripped first so a CRLF body does not leave a
     * trailing carriage return, and a body with no newline yields the whole trimmed text.
     */
    private static String snippetOf(JsonNode item) {
        String supplied = text(item, "snippet");
        if (supplied != null) {
            return supplied;
        }
        String body = text(item, "paragraph0");
        if (body == null) {
            body = text(item, "paragraph1");
        }
        if (body == null) {
            return "";
        }
        String cleaned = body.replace("\r", "");
        int newline = cleaned.indexOf('\n');
        return (newline >= 0 ? cleaned.substring(0, newline) : cleaned).trim();
    }

    /** A non-blank text field, or null — JSON null, a missing field and an empty string all collapse. */
    private static String text(JsonNode item, String field) {
        JsonNode value = item.path(field);
        if (value.isMissingNode() || value.isNull()) {
            return null;
        }
        String s = value.asText("");
        return s.isBlank() ? null : s;
    }

    /** The standard {@code { "items": [...] }} envelope body both split endpoints return. */
    private ObjectNode wrap(ArrayNode items) {
        ObjectNode root = objectMapper.createObjectNode();
        root.set("items", items);
        return root;
    }

    /**
     * Full-text-ish search over published news: matches the term against the headline, source,
     * paragraphs, photo alts, and the names of the up-to-3 mentioned fishes (so "walleye" finds an
     * article tagged with walleye even when the headline doesn't say it). Up to 100 matches, newest
     * first. Backed by {@code dbo.fn_news_search}.
     *
     * <p>The literal {@code /search} path is matched ahead of the templated {@code /{id}} handler.
     *
     * @param q the search term (required, non-blank; trimmed and capped at 100 chars)
     * @return the matching news list in the response envelope
     * @throws InvalidDocumentException if {@code q} is missing or blank (→ 400)
     */
    @GetMapping("/search")
    public ApiResponse<NewsSearchPage> search(@RequestParam(required = false) String q) {
        if (q == null || q.isBlank()) {
            throw new InvalidDocumentException("q (search term) is required");
        }
        String term = q.trim();
        if (term.length() > 100) {
            term = term.substring(0, 100);
        }
        return ApiResponse.ok(queryRepository.search(term));
    }

    private String normalizeCountry(String country) {
        if (country == null) {
            return null;
        }
        String trimmed = country.trim();
        if (trimmed.isEmpty()) {
            return null;
        }
        if (trimmed.length() != 2 || !trimmed.chars().allMatch(Character::isLetter)) {
            throw new InvalidDocumentException("country must be a 2-letter ISO code (e.g. 'CA', 'US')");
        }
        return trimmed.toUpperCase(Locale.ROOT);
    }

    /**
     * One row of the paged latest-news list ({@code dbo.fn_news_list}).
     *
     * @param rn 1-based global position in the ordered+padded list
     * @param newsId the article id
     * @param title the headline
     * @param source the publication/source label
     * @param stamp the publish date as an ISO {@code yyyy-MM-dd} string
     * @param flag the ISO-2 country code of the article
     * @param hasPhoto whether the article carries a real (&gt; 100-byte) lead photo
     * @param blockOrd 0 = the requested country's own news; 1 = Canadian padding to fill up to 100
     */
    public record NewsListItem(
            long rn,
            String newsId,
            String title,
            String source,
            String stamp,
            String flag,
            boolean hasPhoto,
            int blockOrd) {
    }

    /**
     * One page of the latest-news list plus the grand total, so a numbered pager can be rendered from a
     * single call.
     *
     * @param items the rows on this page (newest first; country block then any CA padding)
     * @param total the full row count of the filtered+padded list
     * @param offset the (clamped) row offset this page started at
     * @param limit the (clamped) page size used
     */
    public record NewsListPage(
            List<NewsListItem> items,
            long total,
            int offset,
            int limit) {
    }

    /**
     * One hit from {@code dbo.fn_news_search}: the compact fields needed to render a result row. The
     * paragraphs, photo alts and fish latin/alt names are searched but not returned, keeping the
     * response token-cheap.
     *
     * @param newsId the article id
     * @param title the headline
     * @param source the publication/source label
     * @param stamp the publish date as an ISO {@code yyyy-MM-dd} string
     * @param country the ISO-2 country of the article
     * @param fishes distinct common names of the mentioned fishes (0–3), in slot order
     */
    public record NewsSearchItem(
            String newsId,
            String title,
            String source,
            String stamp,
            String country,
            List<String> fishes) {
    }

    /**
     * The result of a news search.
     *
     * @param items the matching rows (newest first; up to 100)
     * @param total the number of rows returned (capped at 100 by {@code fn_news_search})
     * @param query the (trimmed) term that was searched, echoed back
     */
    public record NewsSearchPage(
            List<NewsSearchItem> items,
            int total,
            String query) {
    }
}
