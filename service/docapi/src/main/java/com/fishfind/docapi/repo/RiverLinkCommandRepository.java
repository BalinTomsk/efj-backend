package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Write-side companion to {@link RiverQueryRepository#source(String)} / {@link
 * RiverQueryRepository#mouth(String)}: a JSON merge-patch of one water body's Source or Mouth link
 * row, backed by {@code dbo.sp_lake_source_update} / {@code dbo.sp_lake_mouth_update}. Kept as its own
 * repository (rather than methods on the query interface) because it mutates {@code dbo.Tributaries},
 * unlike everything else that interface exposes — same reasoning as {@link
 * RiverDescriptionCommandRepository}. Both tabs share one repository, not two, since they are the same
 * merge-patch mechanism against the same table, differing only in which {@code side} row it targets.
 */
public interface RiverLinkCommandRepository {

    /**
     * Applies a JSON merge-patch to one water body's Source-tab fields (the same set {@code
     * dbo.fn_lake_source_json} exports, minus the identity/linkage fields — see the stored procedure).
     * Only keys present in {@code patchJson} are touched; a key with a JSON {@code null} value clears
     * that field.
     *
     * @param lakeId    the water body's GUID
     * @param patchJson a JSON object of field-name → new value
     * @return {@code {lakeId, updated:[{field}], ignored:[{field,reason}], protectedFields:[{field,reason}]}},
     *         or {@code null} if no water body exists for {@code lakeId}
     */
    JsonNode patchSource(String lakeId, String patchJson);

    /** Same contract as {@link #patchSource}, but for the Mouth-tab fields. */
    JsonNode patchMouth(String lakeId, String patchJson);
}
