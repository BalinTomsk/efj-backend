package com.fishfind.docapi.web;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.NewsListOrder;
import com.fishfind.docapi.repo.NewsQueryRepository;
import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.InvalidDocumentException;
import com.fishfind.docapi.service.NewsDocumentService;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Pattern;

/**
 * News endpoints under {@code /api/v1/news}. Inherits the generic JSON-document CRUD
 * ({@code GET/POST/PUT /{id}}) from {@link AbstractDocumentController} and adds the two News-page read
 * queries:
 *
 * <ul>
 *   <li>{@code GET /api/v1/news/list} — one page of the latest news (country filter + pagination);</li>
 *   <li>{@code GET /api/v1/news/default} — the assembled home page;</li>
 *   <li>{@code GET /api/v1/news/featured} — just the two lead articles (with their photos);</li>
 *   <li>{@code GET /api/v1/news/more} — just the "More News" column, in its compact shape;</li>
 *   <li>{@code GET /api/v1/news/lake/{guid}} — one water body's latest articles, for the public
 *       water-body page;</li>
 *   <li>{@code GET /api/v1/news/fish/{guid}} — the same, keyed on a species, for the public
 *       species page.</li>
 * </ul>
 *
 * <p>{@code /featured} and {@code /more} are the two halves of {@code /default}, split because their
 * weights differ by three orders of magnitude (~1 MB of base64 lead photos versus a couple of KB).
 * All three are projections of the <em>same</em> cached assembly, so offering them costs no extra
 * database read.
 *
 * <p>Both queries are delegated to {@link NewsQueryRepository}, which handles DB access via SQL
 * functions and provides in-memory implementations for the no-database profile. The literal
 * {@code /list}, {@code /default}, {@code /featured}, {@code /more}, {@code /lake/…} and
 * {@code /fish/…} paths are matched ahead of the templated {@code /{id}} handler, so they never
 * collide with a document fetch.
 */
@RestController
@RequestMapping(value = "/api/v1/news", produces = MediaType.APPLICATION_JSON_VALUE)
public class NewsController extends AbstractDocumentController {

    /** Default page size (matches News.aspx {@code nPage}). */
    static final int DEFAULT_LIMIT = 25;
    /** Upper bound on page size. */
    static final int MAX_LIMIT = 200;
    /** How many rows of {@code /list} a guest can ever reach — the first 100 of their country's news. */
    static final int GUEST_MAX_ROWS = 100;
    /** How long a browser may reuse a lead photo without revalidating. */
    static final int PHOTO_CACHE_DAYS = 7;
    /** Hard cap on the species ids {@code /search?fish=} accepts — see {@link #parseFishIds}. */
    static final int MAX_SEARCH_FISH_IDS = 3;
    /**
     * Default article count for {@code /lake/{guid}} — the twelve {@code dbo.fn_river_view_news}
     * took, so the water-body page's panel is unchanged by the move to this endpoint.
     */
    static final int LAKE_DEFAULT_LIMIT = 12;

    /**
     * Default article count for {@code /fish/{guid}} — the ten {@code dbo.fn_fish_view_news} took.
     * Two short of {@link #LAKE_DEFAULT_LIMIT} because the two functions it replaces chose
     * differently; each panel keeps the size it has always had.
     */
    static final int FISH_DEFAULT_LIMIT = 10;

    /** Canonical 8-4-4-4-12 hex GUID, the only shape {@code /lake/{guid}} accepts. */
    private static final Pattern GUID = Pattern.compile(
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");

    private final NewsDocumentService newsService;
    private final NewsQueryRepository queryRepository;
    private final ObjectMapper objectMapper;

    public NewsController(NewsDocumentService service, ObjectMapper objectMapper,
                          NewsQueryRepository queryRepository) {
        super(service, objectMapper);
        this.newsService = service;
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
     * Imports one article from an {@code fn_news_json} interchange document -- the shape
     * {@link #export} produces -- creating a new published article in MySQL, all three paragraph
     * photos decoded from base64. Returns the new id.
     *
     * @param body the interchange JSON document
     * @return an envelope carrying {@code { "id": <newId> }}
     * @throws InvalidDocumentException if the body is missing, not a JSON object, or fails validation
     *                                  -- blank title, over-long field, bad country, bad base64 (→ 400)
     */
    @PostMapping(value = "/import", consumes = MediaType.APPLICATION_JSON_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<JsonNode> importNews(@RequestBody(required = false) String body) {
        String newId = newsService.importInterchange(body);
        ObjectNode idNode = objectMapper.createObjectNode();
        idNode.put("id", newId);
        return ApiResponse.ok(idNode);
    }

    /**
     * One page of the news list with optional country filter and pagination. <strong>What the caller
     * gets depends on their role</strong>, which is not a parameter: cproxy verifies the caller and
     * stamps {@value ViewerRole#HEADER}, and docapi trusts it (see {@link ViewerRole}).
     *
     * <table>
     *   <caption>Behaviour by role</caption>
     *   <tr><th>role</th><th>order</th><th>window</th></tr>
     *   <tr><td>{@code admin}</td><td>most recently <em>edited</em> first</td><td>whole list, paged</td></tr>
     *   <tr><td>{@code user}</td><td>newest article <em>date</em> first</td><td>whole list, paged</td></tr>
     *   <tr><td>{@code guest} (also: header missing/unknown)</td><td>newest article date first</td>
     *       <td><strong>the first {@value #GUEST_MAX_ROWS} rows only</strong> — {@code offset+limit} is clamped
     *           to it and {@code total} never exceeds it</td></tr>
     * </table>
     *
     * <p>The guest cap is enforced <em>here</em>, not just by the caller, so a guest's traffic is bounded
     * whatever {@code offset}/{@code limit} are asked for: {@code News.aspx} already asks for exactly the
     * first 100 rows of the visitor's country, and this makes that a rule of the API instead of a habit
     * of one client. The <em>country</em> is still the caller's to pass — docapi never sees the visitor's
     * address (the request arrives from the web server), so the IP-to-country lookup stays in the
     * frontend.
     *
     * @param country ISO-2 code to filter by, or omitted/blank for all countries (a thin non-CA country
     *                is padded with Canadian news up to 100)
     * @param offset rows to skip (null/negative → 0)
     * @param limit page size (null/&lt;1 → {@value #DEFAULT_LIMIT}; capped at {@value #MAX_LIMIT})
     * @param role the caller's role as stamped by cproxy; absent → guest
     * @return the page rows plus the grand total, in the response envelope
     * @throws InvalidDocumentException if {@code country} is present but not a 2-letter code (→ 400)
     */
    @GetMapping("/list")
    public ApiResponse<NewsListPage> list(
            @RequestParam(required = false) String country,
            @RequestParam(required = false) Integer offset,
            @RequestParam(required = false) Integer limit,
            @RequestHeader(value = ViewerRole.HEADER, required = false) String role) {
        String normalizedCountry = normalizeCountry(country);
        int safeOffset = (offset == null || offset < 0) ? 0 : offset;
        int safeLimit = (limit == null || limit < 1) ? DEFAULT_LIMIT : Math.min(limit, MAX_LIMIT);

        switch (ViewerRole.fromHeader(role)) {
            case ADMIN:
                return ApiResponse.ok(queryRepository.list(normalizedCountry, safeOffset, safeLimit, NewsListOrder.EDITED));
            case USER:
                return ApiResponse.ok(queryRepository.list(normalizedCountry, safeOffset, safeLimit, NewsListOrder.DATE));
            default:
                return ApiResponse.ok(guestPage(normalizedCountry, safeOffset, safeLimit));
        }
    }

    /**
     * A guest's page: the requested window clipped to the first {@value #GUEST_MAX_ROWS} rows, with
     * {@code total} clipped to match so a pager built from it never offers a page that would be empty.
     * A window that starts at or past the cap still asks the repository for one row, only to learn the
     * total — the answer is served from the same cache entry the first page uses.
     */
    private NewsListPage guestPage(String country, int offset, int limit) {
        if (offset >= GUEST_MAX_ROWS) {
            NewsListPage first = queryRepository.list(country, 0, 1, NewsListOrder.DATE);
            return new NewsListPage(List.of(), Math.min(first.total(), GUEST_MAX_ROWS), offset, limit);
        }
        int window = Math.min(limit, GUEST_MAX_ROWS - offset);
        NewsListPage page = queryRepository.list(country, offset, window, NewsListOrder.DATE);
        return new NewsListPage(page.items(), Math.min(page.total(), GUEST_MAX_ROWS), offset, limit);
    }

    /**
     * The latest published articles that name one water body, newest first.
     *
     * <p>This is what the public water-body pages ({@code Resources/wfRiverViewer.aspx}) render in
     * their "Last news" panel. It replaces a direct SQL Server read of {@code dbo.fn_river_view_news},
     * so that page — like {@code Default.aspx} and {@code News.aspx} before it — takes its news from
     * the news library rather than from the smaller, soon-to-be-dropped SQL Server copy.
     *
     * <p>{@code fn_river_view_news} splits its rows into two columns ({@code @col = num % 2}) and is
     * called once per column. That split is layout, not data: this returns one ordered list and the
     * page arranges it. A caller wanting the old two-column look alternates rows itself.
     *
     * <p>The literal {@code /lake/…} prefix is matched ahead of the templated {@code /{id}} handler,
     * so it never collides with a document fetch.
     *
     * @param guid the water body's GUID
     * @param limit how many articles at most (null/&lt;1 → {@value #LAKE_DEFAULT_LIMIT}; capped at
     *              {@value #MAX_LIMIT})
     * @return the articles in the response envelope; {@code items} is empty — not a 404 — for a water
     *         body with no news, since "this lake has no news" is an ordinary answer rather than a
     *         missing document
     * @throws InvalidDocumentException if {@code guid} is not a canonical 8-4-4-4-12 GUID (→ 400)
     */
    @GetMapping("/lake/{guid}")
    public ApiResponse<NewsLakePage> lakeNews(@PathVariable String guid,
                                              @RequestParam(required = false) Integer limit) {
        String lakeId = normalizeGuid(guid);
        int safeLimit = (limit == null || limit < 1) ? LAKE_DEFAULT_LIMIT : Math.min(limit, MAX_LIMIT);

        return ApiResponse.ok(queryRepository.lakeNews(lakeId, safeLimit));
    }

    /**
     * The latest published articles that mention one species, newest first.
     *
     * <p>The species counterpart of {@link #lakeNews}, for the public species page
     * ({@code Resources/wfFishViewer.aspx}), which read {@code dbo.fn_fish_view_news} directly.
     * An article carries up to three species tags ({@code fish1_id}/{@code fish2_id}/
     * {@code fish3_id}, set on {@code Editor/AddNews.aspx}) and matching any one of them counts —
     * the same three-slot rule {@code /news/search?fish=} already applies.
     *
     * <p>As everywhere on this API, the species is an <b>id</b>: the MySQL database behind it has no
     * {@code fish} table, so nothing here turns a name into one. The caller holds the name it is
     * rendering already.
     *
     * <p>The literal {@code /fish/…} prefix is matched ahead of the templated {@code /{id}}
     * handler, so it never collides with a document fetch.
     *
     * @param guid the species GUID
     * @param limit how many articles at most (null/&lt;1 → {@value #FISH_DEFAULT_LIMIT}; capped at
     *              {@value #MAX_LIMIT})
     * @return the articles in the response envelope; {@code items} is empty — not a 404 — for a
     *         species with no news
     * @throws InvalidDocumentException if {@code guid} is not a canonical 8-4-4-4-12 GUID (→ 400)
     */
    @GetMapping("/fish/{guid}")
    public ApiResponse<NewsFishPage> fishNews(@PathVariable String guid,
                                              @RequestParam(required = false) Integer limit) {
        String fishId = normalizeGuid(guid);
        int safeLimit = (limit == null || limit < 1) ? FISH_DEFAULT_LIMIT : Math.min(limit, MAX_LIMIT);

        return ApiResponse.ok(queryRepository.fishNews(fishId, safeLimit));
    }

    /**
     * Validates a path GUID and returns it lower-cased, so one water body is one cache/query key
     * whatever case the caller sent.
     *
     * @throws InvalidDocumentException if the value is not a canonical 8-4-4-4-12 hex GUID (→ 400)
     */
    private static String normalizeGuid(String guid) {
        String trimmed = guid == null ? "" : guid.trim();

        if (!GUID.matcher(trimmed).matches()) {
            throw new InvalidDocumentException("guid must be a GUID (8-4-4-4-12 hex)");
        }
        return trimmed.toLowerCase(Locale.ROOT);
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

    /**
     * One article's <strong>lead photo</strong>, as the raw image bytes rather than JSON. This is the
     * by-URL form of the photo {@code /featured} already embeds as base64, and it exists so the
     * frontend never needs a database connection of its own to render a news image: the home page
     * seeds its process cache from the embedded copy while rendering, and the browser's follow-up
     * request for a cache miss lands here instead of on MySQL directly.
     *
     * <p>The literal {@code /photo/...} prefix is matched ahead of the templated {@code /{id}} handler,
     * so it never collides with a plain document fetch.
     *
     * <p><strong>Caching.</strong> The bytes for an id are immutable in practice — replacing an
     * article's photo replaces the bytes but keeps the id — so the response carries a long public
     * {@code max-age} and a weak-free {@code ETag} of {@code "<id>-<length>"}. The ETag is what
     * corrects a stale copy when a photo really is replaced: the length changes, the revalidation
     * misses, and the new bytes are sent. {@code If-None-Match} is honoured with a 304.
     *
     * <p>Content type is sniffed from the file's own magic bytes; the column holds whatever was
     * uploaded, which is mostly JPEG despite the old markup having hard-coded {@code image/png}.
     *
     * @param id the article id
     * @return {@code 200} with the image bytes, {@code 304} when the caller's ETag still matches, or
     *         {@code 404} when the article is missing, unpublished, or carries no photo
     */
    @GetMapping(value = "/photo/{id}", produces = MediaType.ALL_VALUE)
    public ResponseEntity<byte[]> newsPhoto(@PathVariable String id,
                                            @RequestHeader(value = "If-None-Match", required = false) String ifNoneMatch) {
        byte[] photo = queryRepository.newsPhoto(id);

        if (photo == null || photo.length == 0) {
            return ResponseEntity.notFound().build();
        }
        String etag = "\"" + id.toLowerCase(Locale.ROOT) + "-" + photo.length + "\"";
        CacheControl cache = CacheControl.maxAge(Duration.ofDays(PHOTO_CACHE_DAYS)).cachePublic();

        if (ifNoneMatch != null && ifNoneMatch.contains(etag)) {
            return ResponseEntity.status(HttpStatus.NOT_MODIFIED).eTag(etag).cacheControl(cache).build();
        }
        return ResponseEntity.ok()
                .eTag(etag)
                .cacheControl(cache)
                .contentType(MediaType.parseMediaType(sniffContentType(photo)))
                .contentLength(photo.length)
                .body(photo);
    }

    /**
     * Content type from the file's own magic bytes — PNG, JPEG, GIF and WebP, which is everything the
     * library actually holds. Anything unrecognised is served as {@code application/octet-stream}
     * rather than guessed: a wrong image type is worse than an honest unknown one.
     */
    private static String sniffContentType(byte[] bytes) {
        if (bytes.length >= 8 && bytes[0] == (byte) 0x89 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G') {
            return MediaType.IMAGE_PNG_VALUE;
        }
        if (bytes.length >= 3 && bytes[0] == (byte) 0xFF && bytes[1] == (byte) 0xD8 && bytes[2] == (byte) 0xFF) {
            return MediaType.IMAGE_JPEG_VALUE;
        }
        if (bytes.length >= 6 && bytes[0] == 'G' && bytes[1] == 'I' && bytes[2] == 'F') {
            return MediaType.IMAGE_GIF_VALUE;
        }
        if (bytes.length >= 12 && bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F'
                && bytes[8] == 'W' && bytes[9] == 'E' && bytes[10] == 'B' && bytes[11] == 'P') {
            return "image/webp";
        }
        return MediaType.APPLICATION_OCTET_STREAM_VALUE;
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
     * Full-text-ish search over published news: matches the term against the headline, source, the
     * three paragraphs and the three photo alts, and additionally matches any article tagged with one
     * of the species named in {@code fish}. Up to {@value NewsQueryRepository#SEARCH_CAP} matches, newest first, paged
     * with {@code offset}/{@code limit} and carrying the grand {@code total} so a numbered pager can
     * be rendered from a single call.
     *
     * <p><strong>Why {@code fish} is a parameter rather than a join.</strong> The search reads the
     * MySQL {@code news} table, which holds no {@code fish} table — the species an article mentions
     * are bare guids there. So the caller resolves a term like {@code walleye} to species ids against
     * its own catalogue and passes them here, and the article stays a pure {@code news}-table read.
     * That keeps {@code fn_news_search}'s "walleye finds an article tagged with walleye even when the
     * headline doesn't say it" behaviour without making one news read span two databases — the same
     * reason {@code /news/list}, {@code /news/default} and {@code GET /news/{id}} all return lake and
     * species ids and leave the names to the caller (a cross-database lookup for exactly this
     * existed as {@code dbo.fn_news_ref_names_json} in 1.8.0–1.8.1 and was deliberately dropped).
     *
     * <p>The literal {@code /search} path is matched ahead of the templated {@code /{id}} handler.
     *
     * @param q the search term (required, non-blank; trimmed and capped at 100 chars)
     * @param fish comma-separated species ids to match in the article's three species slots, or
     *             omitted for a text-only search; blank entries and anything past
     *             {@value #MAX_SEARCH_FISH_IDS} ids are dropped
     * @param country ISO-2 code to restrict results to, or omitted/blank for all countries
     * @param offset rows to skip (null/negative → 0)
     * @param limit page size (null/&lt;1 → {@value #DEFAULT_LIMIT}; capped at {@value #MAX_LIMIT})
     * @return the matching news page in the response envelope
     * @throws InvalidDocumentException if {@code q} is missing or blank, or {@code country} is present
     *         but not a 2-letter code (→ 400)
     */
    @GetMapping("/search")
    public ApiResponse<NewsSearchPage> search(@RequestParam(required = false) String q,
                                              @RequestParam(required = false) String fish,
                                              @RequestParam(required = false) String country,
                                              @RequestParam(required = false) Integer offset,
                                              @RequestParam(required = false) Integer limit) {
        if (q == null || q.isBlank()) {
            throw new InvalidDocumentException("q (search term) is required");
        }
        String term = q.trim();
        if (term.length() > 100) {
            term = term.substring(0, 100);
        }
        String normalizedCountry = normalizeCountry(country);
        int safeOffset = (offset == null || offset < 0) ? 0 : offset;
        int safeLimit = (limit == null || limit < 1) ? DEFAULT_LIMIT : Math.min(limit, MAX_LIMIT);

        return ApiResponse.ok(queryRepository.search(
                new NewsSearchQuery(term, parseFishIds(fish), normalizedCountry, safeOffset, safeLimit)));
    }

    /**
     * Splits the {@code fish} parameter into at most {@value #MAX_SEARCH_FISH_IDS} non-blank ids.
     *
     * <p>The cap is what keeps the parameter from turning into an unbounded {@code IN} list: a term
     * matching every species in the catalogue would otherwise build a predicate as wide as the
     * catalogue is long. Three is also the most a single article can be tagged with, so a wider list
     * only ever widens the set of articles matched, never the precision of a match.
     *
     * @param fish the raw parameter, possibly null
     * @return the parsed ids, never null (empty for a null/blank parameter)
     */
    private static List<String> parseFishIds(String fish) {
        if (fish == null || fish.isBlank()) {
            return List.of();
        }
        List<String> ids = new ArrayList<>();
        for (String part : fish.split(",")) {
            String trimmed = part.trim();
            if (!trimmed.isEmpty() && !ids.contains(trimmed) && ids.size() < MAX_SEARCH_FISH_IDS) {
                ids.add(trimmed);
            }
        }
        return List.copyOf(ids);
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
     * One article in the news panel of a water-body or species page. Narrower than
     * {@link NewsListItem} on purpose: the panel renders a headline, a source badge and a date, so
     * nothing else is read or sent — in particular no photo column is touched, which is what keeps
     * these queries safe to run on a page view (see {@code MySqlNewsQueryRepository} on the
     * lead-photo BLOB at scale).
     *
     * <p><b>One record, two endpoints.</b> {@code /news/lake/{guid}} and {@code /news/fish/{guid}}
     * render the identical row; a second copy of these five fields would be the duplication this
     * codebase has paid for before.
     *
     * @param newsId the article id — what the page links to as {@code News.aspx?LeadID=<id>}
     * @param title the headline
     * @param source the publication/source label, possibly null
     * @param stamp the publish date as an ISO {@code yyyy-MM-dd} string
     * @param country the ISO-2 country of the article, possibly null
     */
    public record NewsRefItem(
            String newsId,
            String title,
            String source,
            String stamp,
            String country) {
    }

    /**
     * One water body's news panel: the articles plus the id and window they were asked for, so a
     * response is self-describing when it is logged or cached.
     *
     * @param lakeId the water body's guid, lower-cased
     * @param limit the (clamped) maximum asked for
     * @param items the articles, newest first — empty when the water body has no news
     */
    public record NewsLakePage(
            String lakeId,
            int limit,
            List<NewsRefItem> items) {
    }

    /**
     * One species' news panel — {@link NewsLakePage}'s counterpart, differing only in which id it
     * names. Kept as its own record rather than a shared one with a vague {@code refId}, so a
     * response says what it is when it is read or logged.
     *
     * @param fishId the species guid, lower-cased
     * @param limit the (clamped) maximum asked for
     * @param items the articles, newest first — empty when the species has no news
     */
    public record NewsFishPage(
            String fishId,
            int limit,
            List<NewsRefItem> items) {
    }

    /**
     * One news search: everything {@link NewsQueryRepository#search} needs, as one value rather than
     * five positional parameters repeated across every implementation and every circuit-breaker
     * fallback signature.
     *
     * @param query the trimmed, non-blank, &le;100-char search term
     * @param fishIds species ids to match in the article's three species slots; never null, possibly
     *                empty, at most {@value #MAX_SEARCH_FISH_IDS} entries
     * @param country ISO-2 code to restrict to, or null for all countries
     * @param offset rows to skip (non-negative)
     * @param limit page size (already clamped)
     */
    public record NewsSearchQuery(
            String query,
            List<String> fishIds,
            String country,
            int offset,
            int limit) {
    }

    /**
     * One search hit: the compact fields needed to render a result row. The paragraphs and photo alts
     * are searched but not returned, keeping the response token-cheap.
     *
     * @param newsId the article id
     * @param title the headline
     * @param source the publication/source label
     * @param stamp the publish date as an ISO {@code yyyy-MM-dd} string
     * @param country the ISO-2 country of the article
     * @param fishes distinct common names of the mentioned fishes (0–3), in slot order — populated
     *               only by the SQL-Server backing, which has the {@code fish} table to join.
     *               <strong>Empty on the MySQL backing that serves production</strong>, whose
     *               {@code news} table holds species as bare guids; read {@code fishIds} there and
     *               resolve the names against the caller's own catalogue, exactly as
     *               {@code /news/list} and {@code GET /news/{id}} already require
     * @param fishIds ids of the mentioned fishes (0–3), in slot order, blanks dropped
     */
    public record NewsSearchItem(
            String newsId,
            String title,
            String source,
            String stamp,
            String country,
            List<String> fishes,
            List<String> fishIds) {
    }

    /**
     * One page of a news search plus the grand total, so a numbered pager can be rendered from a
     * single call (the same contract as {@link NewsListPage}).
     *
     * @param items the rows on this page (newest first)
     * @param total the full match count, itself capped at {@value NewsQueryRepository#SEARCH_CAP}
     * @param query the (trimmed) term that was searched, echoed back
     * @param offset the (clamped) row offset this page started at
     * @param limit the (clamped) page size used
     */
    public record NewsSearchPage(
            List<NewsSearchItem> items,
            int total,
            String query,
            int offset,
            int limit) {
    }
}
