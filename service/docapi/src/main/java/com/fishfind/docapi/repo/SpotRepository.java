package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

/** A signed-in user's own saved spots ({@code dbo.user_spot}, 1.37.0): the app's "Saved spots". */
public interface SpotRepository {

    /** {@code sp_user_spot_save} results. */
    int INSERTED = 1;
    int UPDATED = 2;
    int NOT_OWNER = 0;
    int TOO_MANY = -1;
    int INVALID = -2;

    /** {@code userId}'s spots, newest first ({@code dbo.fn_user_spot_list_json}); an empty array when none. */
    JsonNode mine(String userId);

    /** Creates or changes spot {@code id} of {@code userId}; one of the result constants above. */
    int save(String id, String userId, String name, double lat, double lon, String lakeId, String note);

    /** Deletes spot {@code id} when it is {@code userId}'s; false when there is no such spot of theirs. */
    boolean delete(String id, String userId);
}
