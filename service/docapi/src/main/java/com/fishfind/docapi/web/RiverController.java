package com.fishfind.docapi.web;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.RiverDescriptionCommandRepository;
import com.fishfind.docapi.repo.RiverFishCommandRepository;
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
import java.util.Set;

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

    private final RiverQueryRepository queryRepository;
    private final RiverFishCommandRepository fishCommandRepository;
    private final RiverDescriptionCommandRepository descriptionCommandRepository;
    private final ObjectMapper objectMapper;

    public RiverController(RiverQueryRepository queryRepository,
                            RiverFishCommandRepository fishCommandRepository,
                            RiverDescriptionCommandRepository descriptionCommandRepository,
                            ObjectMapper objectMapper) {
        this.queryRepository = queryRepository;
        this.fishCommandRepository = fishCommandRepository;
        this.descriptionCommandRepository = descriptionCommandRepository;
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
        JsonNode patch = requireDescriptionPatch(body);
        JsonNode document = descriptionCommandRepository.patchDescription(guid, patch.toString());
        if (document == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, guid);
        }
        return ApiResponse.ok(document);
    }

    /** Validates the description PATCH body is a non-empty, size-capped JSON object. */
    private JsonNode requireDescriptionPatch(String body) {
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
