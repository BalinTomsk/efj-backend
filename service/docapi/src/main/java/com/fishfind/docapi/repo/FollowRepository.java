package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

/** What a signed-in user follows ({@code dbo.user_follow}, 1.39.0): the app's Follow buttons and "Following". */
public interface FollowRepository {

    /** {@code dbo.user_follow.user_follow_kind}. */
    int WATER = 1;
    int FISH = 2;

    /** {@code sp_user_follow_set} results. */
    int FOLLOWED = 1;
    int NOT_FOLLOWED = 0;
    int TOO_MANY = -1;
    int INVALID = -2;

    /** {@code {waters:[...], fish:[...]}}, newest first ({@code dbo.fn_user_follow_list_json}). */
    JsonNode mine(String userId);

    /** Starts or stops following {@code targetId} of {@code kind}; one of the result constants above. */
    int set(String userId, int kind, String targetId, boolean follow);
}
