package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Write-side companion to {@link RegulationQueryRepository}: upserts one row of {@code dbo.regulations},
 * backed by {@code dbo.sp_regulation_upsert} — the write counterpart of
 * {@code Editor/LakeRegulation.aspx} (ButtonSubmit_Click / FindExistingRegId).
 *
 * <p>Unlike {@link RiverDescriptionCommandRepository#patchDescription}, this is not a partial merge
 * patch of an existing, known row: {@code country}/{@code state}/{@code zoneId}/{@code lakeId}/
 * {@code fishId}/{@code year}/{@code part}/{@code residentType} together identify WHICH row (the same
 * columns behind {@code dbo.regulations}' two filtered unique indexes), and every other supported field
 * is replaced outright on that row. A body whose identity matches nothing existing inserts a new row
 * ({@code action: "inserted"}); a body whose identity matches an existing row updates it in place
 * ({@code action: "updated"}) — so this one call covers both "add" and "update", matching the ASPX
 * page's own Add/Update button, which is really the same upsert.
 *
 * <p>Scope is inferred from which of {@code lakeId} / {@code zoneId} are present in the body:
 * {@code lakeId} set → water-body rule; {@code zoneId} set (no {@code lakeId}) → zone rule; neither →
 * region rule (whole-country when {@code state} is omitted, else province/state-wide). The two are
 * mutually exclusive.
 */
public interface RegulationCommandRepository {

    /**
     * Upserts one regulation row.
     *
     * @param bodyJson a JSON object describing the rule — see the class Javadoc for the identity
     *                 fields, plus whichever of the season/limit/size/method fields apply
     * @return {@code {id, action, scope}} on success, or {@code {id:null, action:null, error}} when the
     *         body fails validation (missing year, an unknown lakeId/fishId, or lakeId+zoneId both set)
     *         — never {@code null}, and never throws for a validation failure (see the stored
     *         procedure's graceful-error contract, matching {@code sp_lake_description_update})
     */
    JsonNode upsert(String bodyJson);
}
