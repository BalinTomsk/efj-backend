package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.repo.SpotRepository;
import com.fishfind.docapi.service.ApiProblemException;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * The signed-in user's own saved spots (1.37.0, envfish-droid P2-02) on {@code dbo.user_spot}.
 * <ul>
 *   <li>{@code GET /api/v1/spot/mine} — the caller's spots, newest first, each with its water body when it has one.</li>
 *   <li>{@code POST /api/v1/spot} — JSON {@code {spotId?, name, lat, lon, lakeId?, note?}}: a new spot, or a change to
 *       one of the caller's (same {@code spotId}). The client may send its own id so a retry cannot duplicate.</li>
 *   <li>{@code POST /api/v1/spot/{id}/delete} — POST, because the gateway forwards only GET, POST and PATCH.</li>
 * </ul>
 * The caller is {@value Caller#USER_HEADER} from cproxy 0.30.0 (401 without). Another account's spot is a 404;
 * a 501st spot is {@code 409 too_many_spots}.
 */
@RestController
@RequestMapping("/api/v1/spot")
public class SpotController {

    static final int MAX_NAME = 128;
    static final int MAX_NOTE = 1000;

    private final SpotRepository repository;

    public SpotController(SpotRepository repository) {
        this.repository = repository;
    }

    /** @return the caller's spots as a JSON array, empty when none */
    @GetMapping("/mine")
    public ResponseEntity<ApiResponse<JsonNode>> mine(@RequestHeader(value = Caller.USER_HEADER, required = false) String user) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(ApiResponse.ok(repository.mine(signedIn(user))));
    }

    /** @return {@code {spotId, created}}: created is false when an existing spot was changed */
    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<ApiResponse<Map<String, Object>>> save(
            @RequestHeader(value = Caller.USER_HEADER, required = false) String user, @RequestBody JsonNode body) {
        String userId = signedIn(user);
        if (body == null || !body.isObject()) {
            throw new InvalidDocumentException("The body must be a JSON object");
        }
        String id = text(body, "spotId", 64);
        id = id == null ? CatchLogArgs.uuidV7() : RiverController.normalizeGuid(id);
        String name = text(body, "name", MAX_NAME);
        if (name == null) {
            throw new InvalidDocumentException("name is required");
        }
        double lat = coordinate(body, "lat", 90);
        double lon = coordinate(body, "lon", 180);
        String lakeId = text(body, "lakeId", 64);
        if (lakeId != null) {
            lakeId = RiverController.normalizeGuid(lakeId);
        }
        String note = text(body, "note", MAX_NOTE);
        int result = repository.save(id, userId, name, lat, lon, lakeId, note);
        return switch (result) {
            case SpotRepository.INSERTED, SpotRepository.UPDATED ->
                    ResponseEntity.ok(ApiResponse.ok(Map.of("spotId", id, "created", result == SpotRepository.INSERTED)));
            case SpotRepository.NOT_OWNER -> throw notFound(id);
            case SpotRepository.TOO_MANY -> throw new ApiProblemException(HttpStatus.CONFLICT, "too_many_spots",
                    "An account keeps at most 500 saved spots");
            default -> throw new InvalidDocumentException("The spot needs a name and coordinates on the globe");
        };
    }

    /** @return {@code {spotId, deleted: true}}; 404 when it is not one of the caller's spots */
    @PostMapping("/{id}/delete")
    public ResponseEntity<ApiResponse<Map<String, Object>>> delete(
            @RequestHeader(value = Caller.USER_HEADER, required = false) String user, @PathVariable String id) {
        String userId = signedIn(user);
        String spotId = RiverController.normalizeGuid(id);
        if (!repository.delete(spotId, userId)) {
            throw notFound(spotId);
        }
        return ResponseEntity.ok(ApiResponse.ok(Map.of("spotId", spotId, "deleted", true)));
    }

    private static String signedIn(String header) {
        String userId = Caller.fromHeaders(null, header).userId();
        if (userId == null) {
            throw new ApiProblemException(HttpStatus.UNAUTHORIZED, "sign_in_required", "Sign in to use saved spots");
        }
        return userId;
    }

    private static ApiProblemException notFound(String id) {
        return new ApiProblemException(HttpStatus.NOT_FOUND, "not_found", "No saved spot " + id);
    }

    private static String text(JsonNode body, String key, int max) {
        JsonNode v = body.get(key);
        if (v == null || v.isNull()) return null;
        if (!v.isTextual()) throw new InvalidDocumentException(key + " must be a string");
        String t = v.asText().trim();
        if (t.isEmpty()) return null;
        if (t.length() > max) throw new InvalidDocumentException(key + " must not exceed " + max + " characters");
        return t;
    }

    private static double coordinate(JsonNode body, String key, double limit) {
        JsonNode v = body.get(key);
        if (v == null || !v.isNumber()) throw new InvalidDocumentException(key + " is required (a number)");
        double d = v.asDouble();
        if (Double.isNaN(d) || d < -limit || d > limit) {
            throw new InvalidDocumentException(key + " must be between -" + (int) limit + " and " + (int) limit);
        }
        return d;
    }
}
