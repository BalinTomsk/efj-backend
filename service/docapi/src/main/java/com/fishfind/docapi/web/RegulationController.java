package com.fishfind.docapi.web;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.RegulationCommandRepository;
import com.fishfind.docapi.repo.RegulationQueryRepository;
import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Locale;

/**
 * Fishing-regulation endpoints, the write-enabled counterpart of {@code Editor/LakeRegulation.aspx}'s
 * single "regulation dialog" — which edits all three scopes (province/state, zone, water body) of one
 * {@code dbo.regulations} table through one form. This controller exposes two of those three scopes as
 * their own resource families (zone-scoped rules have no dedicated endpoint yet):
 *
 * <ul>
 *   <li>{@code GET/PATCH /api/v1/river/regulation/{guid}} — water-body-scoped rules.</li>
 *   <li>{@code GET/PATCH /api/v1/region/regulation/{country}} — whole-country rules (no state).</li>
 *   <li>{@code GET/PATCH /api/v1/region/regulation/{country}/{state}} — province/state-wide rules.</li>
 * </ul>
 *
 * <p><strong>There is no separate INSERT verb.</strong> {@code PATCH} on every one of these routes
 * upserts by identity (see {@link RegulationCommandRepository}): a body that doesn't match an existing
 * rule inserts one, a body that does match updates it in place. A dedicated {@code POST} was
 * deliberately not added — cproxy's write surface only admits {@code GET}/{@code PATCH} (the day-key
 * gate is verb-based, not path-based), and reusing the same upsert-on-PATCH pattern already
 * established for {@code /river/fish/{guid}} and {@code /river/description/{guid}} means this ships
 * with no cproxy change at all.
 */
@RestController
@RequestMapping(value = "/api/v1", produces = MediaType.APPLICATION_JSON_VALUE)
public class RegulationController {

    private final RegulationQueryRepository queryRepository;
    private final RegulationCommandRepository commandRepository;
    private final ObjectMapper objectMapper;

    public RegulationController(RegulationQueryRepository queryRepository,
                                 RegulationCommandRepository commandRepository,
                                 ObjectMapper objectMapper) {
        this.queryRepository = queryRepository;
        this.commandRepository = commandRepository;
        this.objectMapper = objectMapper;
    }

    /**
     * This water body's own regulation rows (never the region/zone rules that also apply to it).
     *
     * @param guid the water body's GUID
     * @return the document nested as real JSON in the response envelope
     * @throws DocumentNotFoundException if no water body exists for the id (→ 404)
     */
    @GetMapping("/river/regulation/{guid}")
    public ApiResponse<JsonNode> lakeRegulation(@PathVariable String guid) {
        JsonNode document = queryRepository.lakeRegulation(guid);
        if (document == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, guid);
        }
        return ApiResponse.ok(document);
    }

    /**
     * Upserts one water-body-scoped regulation rule for {@code guid}. {@code lakeId} is taken from the
     * path — supplying a different {@code lakeId} in the body is overridden, not honored — so the URL
     * always identifies which water body is being written to.
     *
     * @param guid the water body's GUID
     * @param body a JSON object of regulation fields (see {@link RegulationCommandRepository})
     * @return {@code {id, action, scope}} nested in the response envelope
     * @throws InvalidDocumentException if the body is missing or not a well-formed JSON object (→ 400)
     */
    @PatchMapping(value = "/river/regulation/{guid}", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ApiResponse<JsonNode> patchLakeRegulation(@PathVariable String guid, @RequestBody(required = false) String body) {
        ObjectNode patch = requireObject(body);
        patch.put("lakeId", guid);
        patch.remove("zoneId");
        JsonNode result = commandRepository.upsert(patch.toString());
        return ApiResponse.ok(result);
    }

    /**
     * Whole-country regulation rows (no specific state) for {@code country}.
     *
     * @param country ISO-2 country code
     * @return the document nested as real JSON in the response envelope (an unknown country yields an
     *         empty rule set, never a 404 — there is no "country" row to be missing)
     * @throws InvalidDocumentException if {@code country} is not exactly two letters (→ 400)
     */
    @GetMapping("/region/regulation/{country}")
    public ApiResponse<JsonNode> regionRegulation(@PathVariable String country) {
        return ApiResponse.ok(queryRepository.region(requireCode(country, "country"), null));
    }

    /**
     * Province/state-wide regulation rows for {@code country}/{@code state}.
     *
     * @param country ISO-2 country code
     * @param state   ISO-2 province/state code
     * @return the document nested as real JSON in the response envelope (an unknown country/state
     *         yields an empty rule set, never a 404)
     * @throws InvalidDocumentException if {@code country} or {@code state} is not exactly two letters
     *                                   (→ 400)
     */
    @GetMapping("/region/regulation/{country}/{state}")
    public ApiResponse<JsonNode> regionRegulation(@PathVariable String country, @PathVariable String state) {
        return ApiResponse.ok(queryRepository.region(requireCode(country, "country"), requireCode(state, "state")));
    }

    /**
     * Upserts one whole-country regulation rule (no specific state) for {@code country}. {@code state}/
     * {@code zoneId}/{@code lakeId} are taken out of the body — this route can only ever write the
     * state-less region row.
     *
     * @param country ISO-2 country code
     * @param body    a JSON object of regulation fields (see {@link RegulationCommandRepository})
     * @return {@code {id, action, scope}} nested in the response envelope
     * @throws InvalidDocumentException if {@code country} is not exactly two letters, or the body is
     *                                   missing / not a well-formed JSON object (→ 400)
     */
    @PatchMapping(value = "/region/regulation/{country}", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ApiResponse<JsonNode> patchRegionRegulation(@PathVariable String country, @RequestBody(required = false) String body) {
        ObjectNode patch = requireObject(body);
        patch.put("country", requireCode(country, "country"));
        patch.remove("state");
        patch.remove("zoneId");
        patch.remove("lakeId");
        JsonNode result = commandRepository.upsert(patch.toString());
        return ApiResponse.ok(result);
    }

    /**
     * Upserts one province/state-wide regulation rule for {@code country}/{@code state}. Same
     * body-field overrides as {@link #patchRegionRegulation(String, String)}, except {@code state} is
     * set from the path rather than removed.
     *
     * @param country ISO-2 country code
     * @param state   ISO-2 province/state code
     * @param body    a JSON object of regulation fields (see {@link RegulationCommandRepository})
     * @return {@code {id, action, scope}} nested in the response envelope
     * @throws InvalidDocumentException if {@code country}/{@code state} is not exactly two letters, or
     *                                   the body is missing / not a well-formed JSON object (→ 400)
     */
    @PatchMapping(value = "/region/regulation/{country}/{state}", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ApiResponse<JsonNode> patchRegionRegulation(@PathVariable String country, @PathVariable String state,
                                                        @RequestBody(required = false) String body) {
        ObjectNode patch = requireObject(body);
        patch.put("country", requireCode(country, "country"));
        patch.put("state", requireCode(state, "state"));
        patch.remove("zoneId");
        patch.remove("lakeId");
        JsonNode result = commandRepository.upsert(patch.toString());
        return ApiResponse.ok(result);
    }

    /** Validates the PATCH body is a non-empty, well-formed JSON object, and returns it as a mutable node. */
    private ObjectNode requireObject(String body) {
        if (body == null || body.isBlank()) {
            throw new InvalidDocumentException("Request body must be a non-empty JSON object of regulation fields");
        }
        JsonNode node;
        try {
            node = objectMapper.readTree(body);
        } catch (JsonProcessingException ex) {
            throw new InvalidDocumentException("Request body is not well-formed JSON: " + ex.getOriginalMessage(), ex);
        }
        if (!node.isObject() || node.isEmpty()) {
            throw new InvalidDocumentException("Request body must be a non-empty JSON object of regulation fields");
        }
        return (ObjectNode) node;
    }

    /** Exactly-two A–Z letters, upper-cased; anything else is a 400 (a path segment, not a filter default). */
    private static String requireCode(String value, String paramName) {
        String v = value == null ? "" : value.trim().toUpperCase(Locale.ROOT);
        if (v.length() != 2 || v.charAt(0) < 'A' || v.charAt(0) > 'Z' || v.charAt(1) < 'A' || v.charAt(1) > 'Z') {
            throw new InvalidDocumentException(paramName + " must be a two-letter code");
        }
        return v;
    }
}
