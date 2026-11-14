package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.FishQueryRepository;
import com.fishfind.docapi.repo.NewsQueryRepository;
import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.FishDocumentService;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import jakarta.servlet.http.HttpServletRequest;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

/**
 * Fish endpoints under {@code /api/v1/fish}. Inherits the generic JSON-document writes
 * ({@code POST/PUT /{id}}) from {@link AbstractDocumentController} and adds:
 *
 * <ul>
 *   <li>{@code GET /api/v1/fish/{guid}} — one species, everything but images (1.28.0; also the MCP tool
 *       {@code get_fish}).</li>
 *   <li>{@code GET /api/v1/fish/page/{guid}} — the app's fish page in one call: species document, photo list,
 *       water bodies and the latest 5 news (1.32.0).</li>
 *   <li>{@code GET /api/v1/fish/photo/{guid}/{imageId}} — one photo's bytes (1.32.0).</li>
 *   <li>{@code GET /api/v1/fish/search} — relevance-ranked species search by name / Latin / synonym.</li>
 *   <li>{@code GET /api/v1/fish?province=&codes=} — regional fish code to Latin name, per province.</li>
 *   <li>{@code GET /api/v1/fish?fishes=} — batch common name to Latin name, one result per name.</li>
 * </ul>
 *
 * <p>The two lookups share the base path and are told apart by which parameter is present, mirroring the
 * portal's {@code /WebService/Fish/} endpoint. They sit on {@code GET} of the base path, which no other
 * handler claims — {@code /{id}} and {@code /search} are both more specific.
 *
 * <p>The query is delegated to {@link FishQueryRepository}, which handles DB access via
 * {@code dbo.SearchFishList} and provides an in-memory implementation for the no-database profile. The
 * literal {@code /search} path is matched ahead of the templated {@code /{id}} handler, so it never
 * collides with a document fetch.
 */
@RestController
@RequestMapping(value = "/api/v1/fish", produces = MediaType.APPLICATION_JSON_VALUE)
public class FishController extends AbstractDocumentController {

    /**
     * One species, everything recorded about it except images ({@code dbo.fn_fish_info_json}, 1.28.0).
     * Replaces the inherited document read, whose {@code dbo.fn_fish_doc} does not exist (every call was a 500).
     * POST/PUT on this path are still the inherited document writes.
     *
     * @param id the species GUID, any case, braces allowed
     * @return the species document in the response envelope
     * @throws InvalidDocumentException if {@code id} is not a GUID (→ 400, no SQL)
     * @throws DocumentNotFoundException for an unknown species (→ 404)
     */
    @Override
    @GetMapping("/{id}")
    public ApiResponse<JsonNode> get(@PathVariable String id) {
        return ApiResponse.ok(species(queryRepository, id));
    }

    /**
     * The species document behind {@code GET /api/v1/fish/{guid}} and the MCP tool {@code get_fish}: the GUID is
     * validated and normalized before any SQL, an unknown species is a not-found.
     */
    static JsonNode species(FishQueryRepository repository, String guid) {
        String fishId = RiverController.normalizeGuid(guid);
        JsonNode doc = repository.info(fishId);
        if (doc == null) {
            throw new DocumentNotFoundException(DocumentType.FISH, fishId);
        }
        return doc;
    }

    /** Upper bound on the search term ({@code dbo.SearchFishList} takes a {@code varchar(64)}). */
    static final int MAX_TERM = 64;

    private static final Logger log = LoggerFactory.getLogger(FishController.class);

    /** Water bodies on a fish page unless {@code waters} says otherwise, and the most it may ask for. */
    static final int PAGE_WATERS_DEFAULT = 20;
    static final int PAGE_WATERS_MAX = 50;

    /** Latest news on a fish page (user decision 2026-11-14: the last 5). */
    static final int PAGE_NEWS = 5;

    /** Days a photo may be cached, as {@code /news/photo/{id}}. */
    static final int PHOTO_CACHE_DAYS = 7;

    private final FishQueryRepository queryRepository;
    private final NewsQueryRepository newsRepository;
    private final ObjectMapper mapper;

    public FishController(FishDocumentService service, ObjectMapper objectMapper,
                          FishQueryRepository queryRepository, NewsQueryRepository newsRepository) {
        super(service, objectMapper);
        this.queryRepository = queryRepository;
        this.newsRepository = newsRepository;
        this.mapper = objectMapper;
    }

    /**
     * Everything the app's fish page shows, in one call (docapi 1.32.0, envfish-droid P0-09):
     * {@code {fish, photos, waters, news}}.
     *
     * <ul>
     *   <li>{@code fish}: the species document of {@code GET /api/v1/fish/{guid}} (names, Latin name, description,
     *       habitat, zoology, spawning, food, ...).</li>
     *   <li>{@code photos}: {@code [{imageId, isDefault, male, juvenile, author, source, link, label, url}]}, the
     *       default picture first; {@code url} is the gateway path of the bytes ({@link #photo}).</li>
     *   <li>{@code waters}: {@code {total, limit, items}} from {@code dbo.fn_fish_water_bodies_json}, highest
     *       probability first, every country and type.</li>
     *   <li>{@code news}: the latest {@value #PAGE_NEWS} articles naming the species, as {@code /news/fish/{guid}}.
     *       News lives in another database (MySQL); if it fails, {@code news} is {@code null} and the page still
     *       answers, the rule the website's fish viewer follows.</li>
     * </ul>
     *
     * <p>Not role-gated here; on the gateway's HTTPS port only a signed-in account reaches it (cproxy 0.29.0).
     *
     * @param guid   the species GUID, any case, braces allowed
     * @param waters how many water bodies (default {@value #PAGE_WATERS_DEFAULT}, 1..{@value #PAGE_WATERS_MAX})
     * @throws InvalidDocumentException if {@code guid} is not a GUID (→ 400, no SQL)
     * @throws DocumentNotFoundException for an unknown species (→ 404)
     */
    @GetMapping("/page/{guid}")
    public ApiResponse<JsonNode> page(@PathVariable String guid,
                                      @RequestParam(required = false) Integer waters) {
        JsonNode fish = species(queryRepository, guid);
        String fishId = RiverController.normalizeGuid(guid);
        int limit = (waters == null || waters < 1) ? PAGE_WATERS_DEFAULT : Math.min(waters, PAGE_WATERS_MAX);

        ObjectNode out = mapper.createObjectNode();
        out.set("fish", fish);
        ArrayNode photos = out.putArray("photos");
        for (JsonNode photo : queryRepository.photos(fishId)) {
            ObjectNode item = photo.deepCopy();
            item.put("url", "/api/v1/fish/photo/" + fishId + "/" + photo.path("imageId").asInt());
            photos.add(item);
        }
        out.set("waters", queryRepository.waterBodies(fishId, null, null, null, 0, limit));
        try {
            out.set("news", mapper.valueToTree(newsRepository.fishNews(fishId, PAGE_NEWS)));
        } catch (RuntimeException ex) {
            log.warn("fish page {}: news unavailable, served without it: {}", fishId, ex.toString());
            out.putNull("news");
        }
        return ApiResponse.ok(out);
    }

    /**
     * One photo of one species, the bytes behind a {@code photos[].url} of {@link #page} (docapi 1.32.0). Cached
     * like {@code /news/photo/{id}}: public {@code max-age}, an ETag of {@code "<fish>-<image>-<length>"},
     * {@code If-None-Match} answered with 304.
     *
     * @return 200 with the image, 304, or 404 when the species has no photo with that id
     * @throws InvalidDocumentException if {@code guid} is not a GUID (→ 400, no SQL)
     */
    @GetMapping(value = "/photo/{guid}/{imageId}", produces = MediaType.ALL_VALUE)
    public ResponseEntity<byte[]> photo(@PathVariable String guid, @PathVariable int imageId,
                                        @RequestHeader(value = "If-None-Match", required = false) String ifNoneMatch) {
        String fishId = RiverController.normalizeGuid(guid);
        byte[] bytes = queryRepository.photo(fishId, imageId);
        if (bytes == null || bytes.length == 0) {
            return ResponseEntity.notFound().build();
        }
        String etag = "\"" + fishId + "-" + imageId + "-" + bytes.length + "\"";
        CacheControl cache = CacheControl.maxAge(Duration.ofDays(PHOTO_CACHE_DAYS)).cachePublic();
        if (ifNoneMatch != null && ifNoneMatch.contains(etag)) {
            return ResponseEntity.status(HttpStatus.NOT_MODIFIED).eTag(etag).cacheControl(cache).build();
        }
        return ResponseEntity.ok()
                .eTag(etag)
                .cacheControl(cache)
                .contentType(MediaType.parseMediaType(NewsController.sniffContentType(bytes)))
                .contentLength(bytes.length)
                .body(bytes);
    }

    /**
     * Relevance-ranked search over the species catalogue: matches the term against a fish's primary
     * name, Latin name, and alternative/common names (so "rosefish" or "ling" resolves to the right
     * species even when it isn't the primary name), best match first. Backed by
     * {@code dbo.SearchFishList} — the same lookup the Editor {@code FishList.aspx} search box uses.
     *
     * <p>The literal {@code /search} path is matched ahead of the templated {@code /{id}} handler.
     *
     * @param q the search term (required, non-blank; trimmed and capped at {@value #MAX_TERM} chars)
     * @return the matching species list in the response envelope
     * @throws InvalidDocumentException if {@code q} is missing or blank (→ 400)
     */
    @GetMapping("/search")
    public ApiResponse<FishSearchPage> search(@RequestParam(required = false) String q) {
        if (q == null || q.isBlank()) {
            throw new InvalidDocumentException("q (search term) is required");
        }
        String term = q.trim();
        if (term.length() > MAX_TERM) {
            term = term.substring(0, MAX_TERM);
        }
        return ApiResponse.ok(queryRepository.search(term));
    }

    /** Most codes or names one batch may ask for; beyond this the request is refused rather than cut. */
    static final int MAX_BATCH = 100;

    /**
     * Two lookups on the base path, told apart by the parameter supplied.
     *
     * <p><b>{@code ?province=AB&codes=BURB,WALL}</b> — regional code → Latin name, returning
     * {@code [{"code","latin"}]} in the requested order. {@code province} is <b>required</b> whenever
     * codes are given: {@code dbo.fish_code} is keyed on country+state+code, so a bare code has no
     * meaning and the same code names different species in different provinces. With no {@code codes}
     * the whole province is published. An <em>unknown</em> province is deliberately not an error — the
     * codes come back unresolved with a null {@code latin}, which cannot be mistaken for a larger
     * result set. {@code country} is optional and defaults to any.
     *
     * <p><b>{@code ?fishes=Walleye,Burbot}</b> — batch common name → Latin name, returning
     * {@code [{"query","name","latin"}]}, one element per requested name in the requested order, with
     * {@code query} echoing the caller's spelling so the response can be zipped back against the request.
     *
     * <p>Both lists accept the same forms (see {@link #parseList}): <code>{…}</code>/<code>[…]</code>
     * wrappers, comma or semicolon separators, quoted items, and repeated parameters.
     *
     * @param request the raw request, read for repeated parameters — see {@link #rawValues}
     * @return the lookup array nested in the response envelope
     * @throws InvalidDocumentException if codes are supplied without a province, if neither parameter is
     *                                  present, or if a batch exceeds {@value #MAX_BATCH} entries (→ 400)
     */
    @GetMapping
    public ApiResponse<JsonNode> lookup(HttpServletRequest request) {
        List<String> fishes = parseList(rawValues(request, "fishes"));
        List<String> codes = parseList(rawValues(request, "codes"));
        String province = trimToNull(request.getParameter("province"));
        String country = trimToNull(request.getParameter("country"));

        if (fishes != null) {
            requireWithinBatchLimit(fishes, "fishes");
            return ApiResponse.ok(queryRepository.namesToLatin(fishes));
        }

        if (province == null && codes == null) {
            throw new InvalidDocumentException("Supply either province (with optional codes) or fishes");
        }
        // A code without its jurisdiction cannot be resolved, so this is a 400 rather than an empty result.
        if (province == null) {
            throw new InvalidDocumentException("province is required when codes are supplied");
        }
        if (codes != null) {
            requireWithinBatchLimit(codes, "codes");
        }
        return ApiResponse.ok(queryRepository.codesToLatin(country, province, codes));
    }

    private static void requireWithinBatchLimit(List<String> values, String name) {
        if (values.size() > MAX_BATCH) {
            throw new InvalidDocumentException(name + " accepts at most " + MAX_BATCH + " entries per request");
        }
    }

    /**
     * Every value supplied for a query-string key, straight from the servlet request.
     *
     * <p>Deliberately <b>not</b> {@code @RequestParam List<String>}: Spring splits such a parameter on
     * commas, and <b>762 of the 1041 species names contain a comma</b> ("Bass, Guadalupe",
     * "Dace, Longnose"), so binding that way would tear most of the catalogue in half. The servlet API
     * returns one entry per actual occurrence of the parameter, leaving the splitting decision here.
     */
    private static String[] rawValues(HttpServletRequest request, String name) {
        return request.getParameterValues(name);
    }

    /**
     * Turns the raw query-string value(s) into the list to look up.
     *
     * <p><b>More than one value means the parameter was repeated</b> ({@code ?codes=a&codes=b}), and each
     * is taken verbatim as one entry — the only way to pass an entry containing a comma without quoting
     * it. <b>A single value is split</b> on commas and semicolons, honouring quotes around an item, so
     * <code>{"BURB", "WALL"}</code> and <code>"Bass, Guadalupe",Burbot</code> both parse the way they read.
     *
     * @return the parsed entries, or {@code null} when the parameter was absent
     */
    private static List<String> parseList(String[] values) {
        if (values == null || values.length == 0) {
            return null;
        }
        List<String> parsed = new ArrayList<>();
        if (values.length > 1) {
            for (String value : values) {
                addEntry(parsed, stripWrapper(value));
            }
            return parsed;
        }
        for (String item : splitQuoted(stripWrapper(values[0]))) {
            addEntry(parsed, item);
        }
        return parsed;
    }

    /** Removes one layer of <code>{…}</code> or <code>[…]</code> so a literal pasted into the URL parses. */
    private static String stripWrapper(String value) {
        if (value == null) {
            return "";
        }
        String text = value.trim();
        if (text.length() >= 2
                && ((text.charAt(0) == '{' && text.charAt(text.length() - 1) == '}')
                 || (text.charAt(0) == '[' && text.charAt(text.length() - 1) == ']'))) {
            text = text.substring(1, text.length() - 1);
        }
        return text;
    }

    /**
     * Splits on commas and semicolons, treating a quoted run as one item so an entry containing the
     * separator survives. The quotes themselves are structural and never part of the entry.
     */
    private static List<String> splitQuoted(String raw) {
        List<String> items = new ArrayList<>();
        StringBuilder current = new StringBuilder();
        boolean inQuotes = false;
        char quote = 0;
        for (int i = 0; i < raw.length(); i++) {
            char ch = raw.charAt(i);
            if (inQuotes) {
                if (ch == quote) {
                    inQuotes = false;
                } else {
                    current.append(ch);
                }
            } else if (ch == '"' || ch == '\'') {
                inQuotes = true;
                quote = ch;
            } else if (ch == ',' || ch == ';') {
                items.add(current.toString());
                current.setLength(0);
            } else {
                current.append(ch);
            }
        }
        items.add(current.toString());
        return items;
    }

    /** Appends a trimmed entry, dropping the empties a trailing separator leaves behind. */
    private static void addEntry(List<String> entries, String value) {
        String entry = (value == null) ? "" : value.trim();
        if (!entry.isEmpty()) {
            entries.add(entry);
        }
    }

    /** @return the trimmed value, or {@code null} when it is absent or blank. */
    private static String trimToNull(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    /**
     * One hit from {@code dbo.SearchFishList}: the fields needed to render a result row and link to the
     * species.
     *
     * @param fishId the species id (GUID)
     * @param name the primary common name
     * @param latin the Latin (scientific) name
     * @param rank the match rank — lower is a better match (0 = exact); rows are returned best-first
     */
    public record FishSearchItem(
            String fishId,
            String name,
            String latin,
            int rank) {
    }

    /**
     * The result of a fish search.
     *
     * @param items the matching species (best match first)
     * @param total the number of rows returned
     * @param query the (trimmed) term that was searched, echoed back
     */
    public record FishSearchPage(
            List<FishSearchItem> items,
            int total,
            String query) {
    }
}
