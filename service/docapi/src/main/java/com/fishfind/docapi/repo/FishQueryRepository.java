package com.fishfind.docapi.repo;

import com.fishfind.docapi.web.FishController.FishSearchPage;

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
}
