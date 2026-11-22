package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.repo.FollowRepository;
import com.fishfind.docapi.service.ApiProblemException;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Locale;
import java.util.Map;

/**
 * What the signed-in user follows (1.39.0, envfish-droid P2-06) on {@code dbo.user_follow}.
 * <ul>
 *   <li>{@code GET /api/v1/follow/mine} — {@code {waters:[{lakeId, lakeName, locType, state, country, since}],
 *       fish:[{fishId, fishName, latin, since}]}}, newest first.</li>
 *   <li>{@code POST /api/v1/follow} — JSON {@code {kind: "water" | "fish", id, follow: true | false}}; repeating
 *       either is harmless. Answers {@code {kind, id, following}}.</li>
 * </ul>
 * The caller is {@value Caller#USER_HEADER} from cproxy 0.30.0 (401 without). An unknown water body or fish is 404;
 * a 501st follow is {@code 409 too_many_follows}.
 */
@RestController
@RequestMapping("/api/v1/follow")
public class FollowController {

    private final FollowRepository repository;

    public FollowController(FollowRepository repository) {
        this.repository = repository;
    }

    /** @return the caller's follows, both lists, uncached */
    @GetMapping("/mine")
    public ResponseEntity<ApiResponse<JsonNode>> mine(@RequestHeader(value = Caller.USER_HEADER, required = false) String user) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(ApiResponse.ok(repository.mine(signedIn(user))));
    }

    /** @return {@code {kind, id, following}} */
    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<ApiResponse<Map<String, Object>>> set(
            @RequestHeader(value = Caller.USER_HEADER, required = false) String user, @RequestBody JsonNode body) {
        String userId = signedIn(user);
        if (body == null || !body.isObject()) {
            throw new InvalidDocumentException("The body must be a JSON object");
        }
        JsonNode k = body.get("kind");
        String kindName = k != null && k.isTextual() ? k.asText().trim().toLowerCase(Locale.ROOT) : "";
        int kind = switch (kindName) {
            case "water" -> FollowRepository.WATER;
            case "fish" -> FollowRepository.FISH;
            default -> throw new InvalidDocumentException("kind must be \"water\" or \"fish\"");
        };
        JsonNode i = body.get("id");
        if (i == null || !i.isTextual()) {
            throw new InvalidDocumentException("id is required (a GUID)");
        }
        String id = RiverController.normalizeGuid(i.asText().trim());
        JsonNode f = body.get("follow");
        if (f == null || !f.isBoolean()) {
            throw new InvalidDocumentException("follow is required (true or false)");
        }
        int result = repository.set(userId, kind, id, f.asBoolean());
        return switch (result) {
            case FollowRepository.FOLLOWED, FollowRepository.NOT_FOLLOWED -> ResponseEntity.ok(ApiResponse.ok(
                    Map.of("kind", kindName, "id", id, "following", result == FollowRepository.FOLLOWED)));
            case FollowRepository.TOO_MANY -> throw new ApiProblemException(HttpStatus.CONFLICT, "too_many_follows",
                    "An account follows at most 500 water bodies and fish");
            default -> throw new ApiProblemException(HttpStatus.NOT_FOUND, "not_found", "No " + kindName + " " + id);
        };
    }

    private static String signedIn(String header) {
        String userId = Caller.fromHeaders(null, header).userId();
        if (userId == null) {
            throw new ApiProblemException(HttpStatus.UNAUTHORIZED, "sign_in_required", "Sign in to follow");
        }
        return userId;
    }
}
