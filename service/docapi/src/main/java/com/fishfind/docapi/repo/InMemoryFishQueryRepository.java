package com.fishfind.docapi.repo;

import com.fishfind.docapi.web.FishController.FishSearchPage;

import java.util.List;

/**
 * In-memory fish query repository (default, no-database profile).
 * Returns empty results so the service runs end-to-end with no DB.
 */
public class InMemoryFishQueryRepository implements FishQueryRepository {

    /** No database: no matches, so the search endpoint runs end-to-end returning an empty result. */
    @Override
    public FishSearchPage search(String query) {
        return new FishSearchPage(List.of(), 0, query);
    }
}
