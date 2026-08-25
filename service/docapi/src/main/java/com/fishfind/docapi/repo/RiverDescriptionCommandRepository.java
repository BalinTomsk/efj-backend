package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Write-side companion to {@link RiverQueryRepository}'s description read: a JSON merge-patch of one
 * water body's editable fields, backed by {@code dbo.sp_lake_description_update}. Kept as its own
 * repository (rather than a method on the query interface) because it mutates {@code dbo.lake}, unlike
 * everything else that interface exposes.
 */
public interface RiverDescriptionCommandRepository {

    /**
     * Applies a JSON merge-patch to one water body's editable fields (the same set
     * {@code dbo.fn_lake_description_json} exports, minus the identity/linkage fields — see the
     * stored procedure). Only keys present in {@code patchJson} are touched; a key with a JSON
     * {@code null} value clears that field.
     *
     * @param lakeId    the water body's GUID
     * @param patchJson a JSON object of field-name → new value
     * @return {@code {lakeId, updated:[{field}], ignored:[{field,reason}], protectedFields:[{field,reason}]}},
     *         or {@code null} if no water body exists for {@code lakeId}
     */
    JsonNode patchDescription(String lakeId, String patchJson);
}
