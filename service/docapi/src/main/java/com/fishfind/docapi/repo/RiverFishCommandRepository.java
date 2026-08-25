package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Write-side companion to {@link RiverQueryRepository}: batch upsert of species assignments for one
 * water body, backed by {@code dbo.sp_lake_fish_upsert_batch}. Kept as its own repository (rather than
 * a method on the query interface) because it mutates {@code lake_fish}, unlike everything else that
 * interface exposes.
 */
public interface RiverFishCommandRepository {

    /**
     * Upserts a batch of species assignments for one water body. Each element of {@code fishJsonArray}
     * may add a species not yet assigned to the lake, or fill in the source link on one that is
     * assigned but still missing it — a fish already assigned <strong>with</strong> a link is left
     * untouched (never silently overwritten).
     *
     * @param lakeId       the water body's GUID
     * @param fishJsonArray a JSON array: {@code [{"fishId","link","trustLevel","year","status"}, …]}
     * @return one result per input item, in order — {@code [{"fishId","fishName","action"}, …]}, where
     *         {@code action} is one of {@code inserted}/{@code updated}/{@code skipped}/
     *         {@code unknown_fish}/{@code invalid_fish_id} — or {@code null} if no water body exists
     *         for {@code lakeId}
     */
    JsonNode upsertFish(String lakeId, String fishJsonArray);
}
