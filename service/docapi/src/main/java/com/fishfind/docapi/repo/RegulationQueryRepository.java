package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Query repository for fishing-regulation reads, backed by SQL functions in the DB. Covers two of the
 * three scopes {@code Editor/LakeRegulation.aspx}'s single "regulation dialog" edits (see
 * {@link RegulationCommandRepository} for how a rule's scope is inferred) — water-body rules and
 * region (country/state) rules. Zone-scoped rules have no dedicated read endpoint yet.
 */
public interface RegulationQueryRepository {

    /**
     * This water body's OWN regulation rows (never the region/zone rules that also apply to it — those
     * have their own scope-specific read via {@link #region}). Backed by
     * {@code dbo.fn_lake_regulation_json}, the same function behind the admin "Save JSON" export on
     * {@code LakeRegulation.aspx}.
     *
     * @param lakeId the water body's GUID
     * @return the document as a JSON tree, or {@code null} if no water body exists for the id
     */
    JsonNode lakeRegulation(String lakeId);

    /**
     * Region-scoped regulation rows for one country, or one country+state — two different,
     * non-overlapping sets, not a country-wide roll-up of every province's rules. Backed by
     * {@code dbo.fn_region_regulation_json}.
     *
     * @param country ISO-2 country code
     * @param state   ISO-2 province/state code, or {@code null} for the whole-country rule set
     *                (rows with no specific state — never a roll-up across every state)
     * @return the document as a JSON tree ({@code {country, state, regulations:[...]}}); never
     *         {@code null} — an unknown country/state combination simply yields an empty array
     */
    JsonNode region(String country, String state);
}
