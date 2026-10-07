package com.fishfind.docapi.web;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.RiverDescriptionCommandRepository;
import com.fishfind.docapi.repo.RiverFishCommandRepository;
import com.fishfind.docapi.repo.RiverLinkCommandRepository;
import com.fishfind.docapi.repo.RiverQueryRepository;
import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * River / water-body endpoints under {@code /api/v1/river}.
 *
 * <p>{@code GET /api/v1/river/unfished?country=&state=&river=} returns the next un-processed water
 * body of a given type in a state (no fish assigned, not flagged "No Fish") — a native docapi
 * duplicate of the frontend {@code Resources/wbUnFish.aspx} endpoint the add-fish tooling uses, backed
 * by {@code dbo.fn_river_unfished_json}. Parameter handling mirrors that page: a bad {@code country}/
 * {@code state} falls back to the default and a bad {@code river} to {@code 2} (no 400s), so the
 * endpoint always answers with a result for the effective parameters.
 *
 * <p>{@code GET /api/v1/river/description/{guid}} returns the full description document for one water
 * body — a native docapi duplicate of the admin "Save JSON" View-tab export
 * ({@code Editor/HandlerImage.ashx?lakejson=&tab=view}), backed by the already-live
 * {@code dbo.fn_lake_view_json}. The underlying content (name, description, stats, source/mouth) is
 * the same public data shown on {@code Resources/wfRiverViewer.aspx} to anonymous visitors — the
 * admin gate on the frontend export path is about that download convenience, not data sensitivity.
 *
 * <p>{@code GET /api/v1/river/fish/{guid}} returns the assigned-species document for one water body —
 * a native docapi duplicate of the admin "Save JSON" Fishing-tab export
 * ({@code Editor/EditLakeFish.aspx} → {@code HandlerImage.ashx?lakejson=&tab=fishing}), backed by the
 * already-live {@code dbo.fn_lake_fishing_json}. Same public-data reasoning as {@code description}: the
 * assigned species list is shown publicly on {@code Resources/wfRiverViewer.aspx}.
 *
 * <p>{@code PATCH /api/v1/river/fish/{guid}} is the write counterpart, duplicating the "Add" form on
 * that same {@code EditLakeFish.aspx} page ({@code AddFishToLake}): a JSON array body of
 * {@code {fishId, link, trustLevel, year, status}} entries, upserted in one batch via
 * {@code dbo.sp_lake_fish_upsert_batch}. Deliberately narrow — a species already assigned to the lake
 * <strong>with</strong> a source link is left untouched ({@code action: "skipped"}) rather than
 * overwritten, so callers should only send species that are new or still missing a link.
 *
 * <p>{@code PATCH /api/v1/river/description/{guid}} is a second, independent write — a JSON merge
 * patch of the {@code Editor/LakeEditor.aspx} "General" tab's editable fields, via
 * {@code dbo.sp_lake_description_update}. Only keys present in the body are touched. Deliberately
 * protects the identity/linkage fields that page shows read-only in this exact spot —
 * {@code lakeName}, {@code source}/{@code sourceId}, {@code mouth}/{@code mouthId} — reporting them
 * back as {@code protectedFields} rather than silently dropping or applying them.
 *
 * <p>{@code GET /api/v1/river/source/{guid}} and {@code GET /api/v1/river/mouth/{guid}} return the
 * Source/Mouth tab documents — native docapi duplicates of the admin "Save JSON" export on
 * {@code Editor/EditLakeLink.aspx?Type=16} / {@code ?Type=32} (the same "Save JSON" button, which
 * downloads {@code HandlerImage.ashx?lakejson=&tab=source|mouth}), backed by the already-live
 * {@code dbo.fn_lake_source_json} / {@code dbo.fn_lake_mouth_json}.
 *
 * <p>{@code PATCH /api/v1/river/source/{guid}} and {@code PATCH /api/v1/river/mouth/{guid}} are the
 * write counterparts — a JSON merge patch of that tab's editable fields (lat/lon/elevation/country/
 * state/county/city/district/municipality/region/zone/coast/location/description), via the new
 * {@code dbo.sp_lake_source_update} / {@code dbo.sp_lake_mouth_update}. Deliberately protects every
 * identity/linkage field {@code EditLakeLink.aspx} shows read-only in that exact spot — the main water
 * body's own {@code lakeName}/{@code guid}, and the linked point's {@code pointName}/{@code pointId} —
 * reporting them back as {@code protectedFields} rather than silently dropping or applying them, same
 * as {@code description}.
 *
 * <p>{@code GET /api/v1/river/search?name=&guid=&cgndb=&stateId=&mli=&limit=} finds water bodies by part of a
 * name, either GUID ({@code lake_id} / {@code secondary_id}), either CGNDB code ({@code CGNDB} /
 * {@code CGNDM}), the province's/state's own id ({@code state_id}, 1.23.0) or the MLI of a linked water
 * station, via {@code dbo.fn_river_search_json}. Every supplied criterion must match; parameter names are
 * case-insensitive ({@code CGNDB=}, {@code MLI=}, {@code stateid=}).
 *
 * <p>{@code GET /api/v1/river/tributaries/{guid}?limit=} (1.22.0) lists the water bodies that flow INTO one
 * water body — the reverse of {@code /source} and {@code /mouth} — via {@code dbo.fn_lake_inflows_json}.
 */
@RestController
@RequestMapping(value = "/api/v1/river", produces = MediaType.APPLICATION_JSON_VALUE)
public class RiverController {

    static final String DEFAULT_COUNTRY = "CA";
    static final String DEFAULT_STATE = "ON";
    static final int DEFAULT_RIVER = 2;

    /** Refuses a batch this large rather than looping unboundedly (mirrors the {@code ?fishes=} cap). */
    static final int MAX_FISH_BATCH = 500;

    /** Valid locType values (water-body type bitmask; see the frontend RscRiverList / wbUnFish). */
    private static final Set<Integer> VALID_RIVER =
            Set.of(1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192);

    /** Refuses a patch this large; a single water body's editable fields never come close. */
    static final int MAX_PATCH_FIELDS = 100;

    static final int SEARCH_DEFAULT_LIMIT = 50;
    static final int SEARCH_MAX_LIMIT = 200;

    /** A name part shorter than this would match a large share of ~196k water bodies. */
    static final int SEARCH_MIN_NAME = 2;

    /** {@code lake_name} is {@code nvarchar(64)}; so is {@code WaterStation.MLI}'s {@code varchar(64)}. */
    static final int SEARCH_MAX_TERM = 64;

    /** CGNDB / CGNDM are {@code char(5)} alphanumeric codes. */
    private static final Pattern CGNDB_PATTERN = Pattern.compile("[A-Z0-9]{1,5}");

    /**
     * {@code lake.state_id} is {@code varchar(32)}: a province's/state's own id (BC GNIS id {@code 39325},
     * Alberta FWMIS id {@code 4309}; other jurisdictions use letters and separators, e.g. {@code 27-0133-00}).
     */
    static final Pattern STATE_ID_PATTERN = Pattern.compile("[A-Za-z0-9._/-]{1,32}");

    /** A GUID in 32-hex form once braces, dashes and whitespace are stripped. */
    private static final Pattern HEX32_PATTERN = Pattern.compile("[0-9a-f]{32}");

    private final RiverQueryRepository queryRepository;
    private final RiverFishCommandRepository fishCommandRepository;
    private final RiverDescriptionCommandRepository descriptionCommandRepository;
    private final RiverLinkCommandRepository linkCommandRepository;
    private final ObjectMapper objectMapper;

    public RiverController(RiverQueryRepository queryRepository,
                            RiverFishCommandRepository fishCommandRepository,
                            RiverDescriptionCommandRepository descriptionCommandRepository,
                            RiverLinkCommandRepository linkCommandRepository,
                            ObjectMapper objectMapper) {
        this.queryRepository = queryRepository;
        this.fishCommandRepository = fishCommandRepository;
        this.descriptionCommandRepository = descriptionCommandRepository;
        this.linkCommandRepository = linkCommandRepository;
        this.objectMapper = objectMapper;
    }

    /**
     * The next un-processed water body for the given country/state/river-type.
     *
     * @param country ISO-2 country (echoed only; the query filters by state) — default {@value #DEFAULT_COUNTRY}
     * @param state   ISO-2 state/province (the filter) — default {@value #DEFAULT_STATE}
     * @param river   locType value — default {@value #DEFAULT_RIVER} (river)
     * @return the water body as JSON in the response envelope ({@code found:false} when none remain)
     */
    @GetMapping("/unfished")
    public ApiResponse<JsonNode> unfished(
            @RequestParam(required = false) String country,
            @RequestParam(required = false) String state,
            @RequestParam(required = false) Integer river) {
        String cleanCountry = cleanCode(country, DEFAULT_COUNTRY);
        String cleanState = cleanCode(state, DEFAULT_STATE);
        int cleanRiver = parseRiver(river);
        return ApiResponse.ok(queryRepository.unfished(cleanCountry, cleanState, cleanRiver));
    }

    /**
     * Finds water bodies by any combination of: part of a name, either GUID, either CGNDB code, or the
     * MLI of a linked water station. Every supplied criterion must match (AND).
     *
     * <p>Parameter names are matched case-insensitively, so {@code ?CGNDB=FEFUL} and {@code ?MLI=02HC024}
     * work as well as the lower-case forms.
     *
     * @param params {@code name} (≥ {@value #SEARCH_MIN_NAME} chars, substring of the primary/alt/French
     *               name), {@code guid} (36-char, 32-hex or braced; matches {@code lake_id} or
     *               {@code secondary_id}), {@code cgndb} (1–5 letters/digits; matches {@code CGNDB} or
     *               {@code CGNDM}), {@code stateId} (1–32 letters/digits/{@code . _ / -}; matches
     *               {@code state_id} exactly), {@code mli} (station id), {@code limit} (null/&lt;1 →
     *               {@value #SEARCH_DEFAULT_LIMIT}; capped at {@value #SEARCH_MAX_LIMIT})
     * @return {@code {items, total, limit, query}} — {@code items} is empty (never 404) when nothing matches
     * @throws InvalidDocumentException if no criterion is given or one is malformed (→ 400)
     */
    @GetMapping("/search")
    public ApiResponse<RiverSearchPage> search(@RequestParam Map<String, String> params) {
        String name = trimToNull(param(params, "name"));
        String guid = trimToNull(param(params, "guid"));
        String cgndb = trimToNull(param(params, "cgndb"));
        String stateId = trimToNull(param(params, "stateId"));
        String mli = trimToNull(param(params, "mli"));
        if (name == null && guid == null && cgndb == null && stateId == null && mli == null) {
            throw new InvalidDocumentException("At least one of name, guid, cgndb, stateId, mli is required");
        }
        if (name != null && (name.length() < SEARCH_MIN_NAME || name.length() > SEARCH_MAX_TERM)) {
            throw new InvalidDocumentException(
                    "name must be " + SEARCH_MIN_NAME + " to " + SEARCH_MAX_TERM + " characters");
        }
        if (guid != null) {
            guid = normalizeGuid(guid);
        }
        if (cgndb != null) {
            cgndb = cgndb.toUpperCase(Locale.ROOT);
            if (!CGNDB_PATTERN.matcher(cgndb).matches()) {
                throw new InvalidDocumentException("cgndb must be 1 to 5 letters or digits");
            }
        }
        if (stateId != null) {
            checkStateId(stateId);
        }
        if (mli != null && mli.length() > SEARCH_MAX_TERM) {
            throw new InvalidDocumentException("mli must not exceed " + SEARCH_MAX_TERM + " characters");
        }
        int limit = parseLimit(param(params, "limit"));

        JsonNode items = queryRepository.search(name, guid, cgndb, stateId, mli, limit);
        return ApiResponse.ok(new RiverSearchPage(items, items.size(), limit,
                new RiverSearchQuery(name, guid, cgndb, stateId, mli)));
    }

    /** The echoed, normalized criteria of a search ({@code null} for any not supplied). */
    public record RiverSearchQuery(String name, String guid, String cgndb, String stateId, String mli) {
    }

    /** Rejects a {@code stateId} that cannot be a {@code lake.state_id}; shared with the MCP search tool. */
    static void checkStateId(String stateId) {
        if (!STATE_ID_PATTERN.matcher(stateId).matches()) {
            throw new InvalidDocumentException("stateId must be 1 to 32 letters, digits or . _ / -");
        }
    }

    /**
     * The result of a river search.
     *
     * @param items the matches as returned by {@code dbo.fn_river_search_json}, best name match first
     * @param total how many items were returned (not a count beyond {@code limit})
     * @param limit the effective limit
     * @param query the normalized criteria that were searched
     */
    public record RiverSearchPage(JsonNode items, int total, int limit, RiverSearchQuery query) {
    }

    /** Case-insensitive lookup of a query parameter. */
    private static String param(Map<String, String> params, String key) {
        for (Map.Entry<String, String> e : params.entrySet()) {
            if (e.getKey().equalsIgnoreCase(key)) {
                return e.getValue();
            }
        }
        return null;
    }

    private static String trimToNull(String value) {
        if (value == null) return null;
        String v = value.trim();
        return v.isEmpty() ? null : v;
    }

    /** Accepts 36-char, 32-hex and braced forms; returns the canonical lower-case 36-char GUID. */
    static String normalizeGuid(String value) {
        String hex = value.replaceAll("[{}\\s-]", "").toLowerCase(Locale.ROOT);
        if (!HEX32_PATTERN.matcher(hex).matches()) {
            throw new InvalidDocumentException("guid is not a valid GUID");
        }
        return hex.substring(0, 8) + "-" + hex.substring(8, 12) + "-" + hex.substring(12, 16) + "-"
                + hex.substring(16, 20) + "-" + hex.substring(20);
    }

    /** A missing, non-numeric or &lt;1 limit becomes the default; anything larger is capped. */
    private static int parseLimit(String value) {
        if (value == null) return SEARCH_DEFAULT_LIMIT;
        try {
            int n = Integer.parseInt(value.trim());
            return n < 1 ? SEARCH_DEFAULT_LIMIT : Math.min(n, SEARCH_MAX_LIMIT);
        } catch (NumberFormatException ex) {
            return SEARCH_DEFAULT_LIMIT;
        }
    }

    /**
     * The full description document for one water body: name/alt names, description text, physical
     * stats, source/mouth detail, assigned fish, and the photo gallery (base64).
     *
     * <p>The literal {@code /description/…} prefix is matched ahead of any future templated route on
     * this controller.
     *
     * @param guid the water body's GUID
     * @return the document nested as real JSON in the response envelope
     * @throws DocumentNotFoundException if no water body exists for the id (→ 404)
     */
    @GetMapping("/description/{guid}")
    public ApiResponse<JsonNode> description(@PathVariable String guid) {
        JsonNode document = queryRepository.description(guid);
        if (document == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, guid);
        }
        return ApiResponse.ok(document);
    }

    /**
     * The assigned-species document for one water body: name/latin, conservation status, last-catch,
     * and the external link, per species.
     *
     * <p>The literal {@code /fish/…} prefix is matched ahead of any future templated route on this
     * controller, same as {@code /description/…}.
     *
     * @param guid the water body's GUID
     * @return the document nested as real JSON in the response envelope
     * @throws DocumentNotFoundException if no water body exists for the id (→ 404)
     */
    @GetMapping("/fish/{guid}")
    public ApiResponse<JsonNode> fish(@PathVariable String guid) {
        JsonNode document = queryRepository.fish(guid);
        if (document == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, guid);
        }
        return ApiResponse.ok(document);
    }

    /**
     * Upserts a batch of species assignments for one water body.
     *
     * @param guid the water body's GUID
     * @param body a JSON array: {@code [{"fishId","link","trustLevel","year","status"}, …]} — only
     *             {@code fishId} is required per entry; the rest are optional
     * @return one result per input item, in order, nested in the response envelope
     * @throws InvalidDocumentException if the body is missing, not a well-formed JSON array, empty, or
     *                                   over {@value #MAX_FISH_BATCH} entries (→ 400)
     * @throws DocumentNotFoundException if no water body exists for the id (→ 404)
     */
    @PatchMapping(value = "/fish/{guid}", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ApiResponse<JsonNode> patchFish(@PathVariable String guid, @RequestBody(required = false) String body) {
        JsonNode items = requireFishArray(body);
        JsonNode document = fishCommandRepository.upsertFish(guid, items.toString());
        if (document == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, guid);
        }
        return ApiResponse.ok(document);
    }

    /** Validates the PATCH body is a non-empty, size-capped JSON array. */
    private JsonNode requireFishArray(String body) {
        if (body == null || body.isBlank()) {
            throw new InvalidDocumentException("Request body must be a non-empty JSON array of fish entries");
        }
        JsonNode node;
        try {
            node = objectMapper.readTree(body);
        } catch (JsonProcessingException ex) {
            throw new InvalidDocumentException("Request body is not well-formed JSON: " + ex.getOriginalMessage(), ex);
        }
        if (!node.isArray() || node.isEmpty()) {
            throw new InvalidDocumentException("Request body must be a non-empty JSON array of fish entries");
        }
        if (node.size() > MAX_FISH_BATCH) {
            throw new InvalidDocumentException("Request body must not exceed " + MAX_FISH_BATCH + " fish entries");
        }
        return node;
    }

    /**
     * Applies a JSON merge-patch to one water body's editable fields.
     *
     * @param guid the water body's GUID
     * @param body a JSON object of field-name → new value; a JSON {@code null} clears that field
     * @return {@code {lakeId, updated, ignored, protectedFields}} nested in the response envelope —
     *         see {@link RiverDescriptionCommandRepository#patchDescription} for the field names and
     *         what gets protected
     * @throws InvalidDocumentException  if the body is missing, not a well-formed JSON object, empty,
     *                                    or over {@value #MAX_PATCH_FIELDS} keys (→ 400)
     * @throws DocumentNotFoundException if no water body exists for the id (→ 404)
     */
    @PatchMapping(value = "/description/{guid}", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ApiResponse<JsonNode> patchDescription(@PathVariable String guid, @RequestBody(required = false) String body) {
        JsonNode patch = requireMergePatch(body);
        JsonNode document = descriptionCommandRepository.patchDescription(guid, patch.toString());
        if (document == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, guid);
        }
        return ApiResponse.ok(document);
    }

    /**
     * The Source-tab document for one water body: the linked point's name/id and its location fields.
     *
     * @param guid the water body's GUID
     * @return the document nested as real JSON in the response envelope
     * @throws DocumentNotFoundException if no water body exists for the id (→ 404)
     */
    @GetMapping("/source/{guid}")
    public ApiResponse<JsonNode> source(@PathVariable String guid) {
        JsonNode document = queryRepository.source(guid);
        if (document == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, guid);
        }
        return ApiResponse.ok(document);
    }

    /** Same as {@link #source(String)}, for the Mouth tab. */
    @GetMapping("/mouth/{guid}")
    public ApiResponse<JsonNode> mouth(@PathVariable String guid) {
        JsonNode document = queryRepository.mouth(guid);
        if (document == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, guid);
        }
        return ApiResponse.ok(document);
    }

    /**
     * The water bodies that flow into one water body (1.22.0): those whose mouth is this one, plus the
     * inflows recorded on it (a lake), each once, by name.
     *
     * <p>Unlike the older {@code /{guid}} reads here, the GUID is validated before the repository is called:
     * a malformed one would otherwise be a SQL conversion error counted by the shared {@code sqlBreaker}.
     *
     * @param guid  the water body's GUID (36-char, 32-hex or braced)
     * @param limit null/&lt;1/non-numeric → {@value #SEARCH_DEFAULT_LIMIT}; capped at {@value #SEARCH_MAX_LIMIT}
     * @return {@code {guid, lakeName, total, limit, tributaries}} nested in the response envelope; an empty
     *         {@code tributaries} (never 404) when nothing flows in
     * @throws InvalidDocumentException  if {@code guid} is not a GUID (→ 400)
     * @throws DocumentNotFoundException if no water body exists for the id (→ 404)
     */
    @GetMapping("/tributaries/{guid}")
    public ApiResponse<JsonNode> tributaries(@PathVariable String guid,
                                             @RequestParam(required = false) String limit) {
        String id = normalizeGuid(guid);
        JsonNode document = queryRepository.tributaries(id, parseLimit(limit));
        if (document == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, id);
        }
        return ApiResponse.ok(document);
    }

    /**
     * Applies a JSON merge-patch to one water body's Source-tab fields.
     *
     * @param guid the water body's GUID
     * @param body a JSON object of field-name → new value; a JSON {@code null} clears that field
     * @return {@code {lakeId, updated, ignored, protectedFields}} nested in the response envelope —
     *         see {@link RiverLinkCommandRepository#patchSource} for the field names and what gets
     *         protected
     * @throws InvalidDocumentException  if the body is missing, not a well-formed JSON object, empty,
     *                                    or over {@value #MAX_PATCH_FIELDS} keys (→ 400)
     * @throws DocumentNotFoundException if no water body exists for the id (→ 404)
     */
    @PatchMapping(value = "/source/{guid}", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ApiResponse<JsonNode> patchSource(@PathVariable String guid, @RequestBody(required = false) String body) {
        JsonNode patch = requireMergePatch(body);
        JsonNode document = linkCommandRepository.patchSource(guid, patch.toString());
        if (document == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, guid);
        }
        return ApiResponse.ok(document);
    }

    /** Same as {@link #patchSource}, for the Mouth tab. */
    @PatchMapping(value = "/mouth/{guid}", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ApiResponse<JsonNode> patchMouth(@PathVariable String guid, @RequestBody(required = false) String body) {
        JsonNode patch = requireMergePatch(body);
        JsonNode document = linkCommandRepository.patchMouth(guid, patch.toString());
        if (document == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, guid);
        }
        return ApiResponse.ok(document);
    }

    /**
     * Validates a merge-patch PATCH body is a non-empty, size-capped JSON object. Shared by
     * {@code description}/{@code source}/{@code mouth} — all three are the same JSON-merge-patch
     * mechanism against a different table/row.
     */
    private JsonNode requireMergePatch(String body) {
        if (body == null || body.isBlank()) {
            throw new InvalidDocumentException("Request body must be a non-empty JSON object of fields to patch");
        }
        JsonNode node;
        try {
            node = objectMapper.readTree(body);
        } catch (JsonProcessingException ex) {
            throw new InvalidDocumentException("Request body is not well-formed JSON: " + ex.getOriginalMessage(), ex);
        }
        if (!node.isObject() || node.isEmpty()) {
            throw new InvalidDocumentException("Request body must be a non-empty JSON object of fields to patch");
        }
        if (node.size() > MAX_PATCH_FIELDS) {
            throw new InvalidDocumentException("Request body must not exceed " + MAX_PATCH_FIELDS + " fields");
        }
        return node;
    }

    /** Exactly-two A–Z letters, upper-cased; anything else falls back (mirrors wbUnFish CleanCode). */
    private static String cleanCode(String value, String fallback) {
        if (value == null) return fallback;
        String v = value.trim().toUpperCase(Locale.ROOT);
        if (v.length() != 2) return fallback;
        for (int i = 0; i < v.length(); i++) {
            char c = v.charAt(i);
            if (c < 'A' || c > 'Z') return fallback;
        }
        return v;
    }

    /** A valid locType value, else {@value #DEFAULT_RIVER} (mirrors wbUnFish ParseRiver). */
    private static int parseRiver(Integer value) {
        if (value == null || !VALID_RIVER.contains(value)) return DEFAULT_RIVER;
        return value;
    }
}
