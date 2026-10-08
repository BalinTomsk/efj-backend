package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.web.FishController.FishSearchPage;

import java.util.List;

/**
 * Query repository for fish-page read operations, backed by SQL functions in the DB.
 * Separates HTTP/controller concerns from DB access logic, mirroring {@link NewsQueryRepository}.
 */
public interface FishQueryRepository {

    /**
     * Searches the species catalogue for a term, matching against the primary name, the Latin name, and
     * every alternative/common name — the same relevance-ranked lookup the Editor
     * {@code FishList.aspx} search box uses ({@code dbo.SearchFishList}). Results are ordered best match
     * first.
     *
     * @param query the (trimmed, non-blank) search term
     * @return the matching species list
     */
    FishSearchPage search(String query);

    /**
     * Resolves regional fish codes to Latin names for one province, backed by
     * {@code dbo.fn_fish_code_latin_json}.
     *
     * <p>Returns <b>one element per match, not per requested code</b>: {@code dbo.fish_code} is keyed on
     * (fish_id, country, state, code), so a code may legitimately name several species — on the live
     * database BC {@code RB} is both Rock Bass and Rainbow Trout. A code matching nothing still yields
     * exactly one element with a null {@code latin}, so the array never silently shrinks relative to the
     * request.
     *
     * @param country ISO-2 country code, or {@code null} for any (country is part of the key, but only
     *                {@code CA} exists today)
     * @param province the province/state code; required — a bare code has no meaning without it
     * @param codes the requested codes in caller order, or {@code null} for every code in the province
     * @return a JSON array of {@code {code, latin}} objects; never {@code null}
     */
    JsonNode codesToLatin(String country, String province, List<String> codes);

    /**
     * Resolves common fish names to their Latin names, backed by {@code dbo.fn_fish_latin_json}.
     *
     * <p>One element per requested name, <b>in the requested order</b>, each {@code {query, name, latin}}.
     * {@code query} echoes the caller's spelling so the response can be zipped back against the request;
     * a name that resolves to nothing keeps its slot with null {@code name}/{@code latin}, because
     * dropping it would shift every later element and mis-pair everything after the first miss.
     * Matching is a substring of the common or Latin name, so {@code "Walley"} resolves to
     * {@code "Walleye"}.
     *
     * @param names the requested names in caller order
     * @return a JSON array of {@code {query, name, latin}} objects; never {@code null}
     */
    JsonNode namesToLatin(List<String> names);

    /**
     * The water bodies where one species is recorded, each counted once, backed by
     * {@code dbo.fn_fish_water_bodies_json}. Used by the MCP tool {@code find_water_bodies_by_fish}.
     * The caller validates every argument; this passes them straight through.
     *
     * @param fishId         canonical species GUID
     * @param country        ISO-2 country code, or {@code null} for any
     * @param state          ISO-2 province/state code, or {@code null} for any
     * @param locType        water-body type bitmask (1 lake, 2 river, 64 creek, ...), or {@code null} for any
     * @param minProbability 0..100, applied to each water body's highest-probability record
     * @param limit          1..200 items to return; {@code total} still counts every match
     * @return {@code {total, limit, items:[{lakeId, lakeName, altName, frenchName, locType, CGNDB, CGNDM, country,
     *         state, probability}]}}, highest probability first; never {@code null}
     */
    JsonNode waterBodies(String fishId, String country, String state, Integer locType, int minProbability, int limit);
}
