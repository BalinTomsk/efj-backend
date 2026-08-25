package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.repo.RiverQueryRepository;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
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
 */
@RestController
@RequestMapping(value = "/api/v1/river", produces = MediaType.APPLICATION_JSON_VALUE)
public class RiverController {

    static final String DEFAULT_COUNTRY = "CA";
    static final String DEFAULT_STATE = "ON";
    static final int DEFAULT_RIVER = 2;

    /** Valid locType values (water-body type bitmask; see the frontend RscRiverList / wbUnFish). */
    private static final Set<Integer> VALID_RIVER =
            Set.of(1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192);

    private final RiverQueryRepository queryRepository;

    public RiverController(RiverQueryRepository queryRepository) {
        this.queryRepository = queryRepository;
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
