package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.repo.CatchLog;
import com.fishfind.docapi.repo.CatchLogCommandRepository;
import com.fishfind.docapi.service.ApiProblemException;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.concurrent.TimeUnit;

/**
 * The signed-in user's own catch log (1.36.0, envfish-droid's Me tab), on the portal's tables and procedures.
 * <ul>
 *   <li>{@code GET /api/v1/catch/mine?limit=} — the caller's logs on every water body, newest catch first
 *       ({@code dbo.fn_catch_memo_mine_json}), each with its visible photo ids.</li>
 *   <li>{@code POST /api/v1/catch} — a new log (JSON: {@code lakeId} plus the fields {@code add_catch_log} takes);
 *       weather left out is filled from the water body's station forecast for {@code catchDate}.</li>
 *   <li>{@code PATCH /api/v1/catch/{id}} (1.43.0) — corrects one of the caller's logs: only the fields given change, a
 *       JSON null clears one ({@code angler} cannot be cleared to nothing it did not have); the water body and the
 *       author never change and nothing is filled from the station. The MCP tool {@code update_catch_log} (mcp-env).</li>
 *   <li>{@code POST /api/v1/catch/{id}/photo?caption=&credit=} — one image (raw body, at most
 *       {@value #MAX_PHOTO_BYTES} bytes), up to {@value CatchLogCommandRepository#MAX_PHOTOS} per log. A JPEG is stored
 *       as sent; since 1.43.0 a PNG or WebP ({@code image/png}, {@code image/webp}) is converted to JPEG first
 *       ({@link CatchPhotoImage}), which is what the MCP tool {@code add_catch_log_photo} sends for news-site images.</li>
 *   <li>{@code GET /api/v1/catch/photo/{id}/{photoId}} — the JPEG of one of the caller's photos.</li>
 * </ul>
 * <strong>Who:</strong> the account cproxy names in {@value Caller#USER_HEADER} (0.30.0) for a verified,
 * signed-in token; cproxy drops any inbound copy, so it is a fact here. Without it every route is
 * {@code 401 sign_in_required}. A log that is not the caller's reads as {@code 404}, never as someone else's; a
 * photo can be added only while the portal's 60-day edit window is open ({@code 403 locked}).
 */
@RestController
@RequestMapping("/api/v1/catch")
public class CatchLogController {

    static final int DEFAULT_LIMIT = 50;
    static final int MAX_LIMIT = 200;
    static final int MAX_PHOTO_BYTES = 5_000_000;

    private static final CacheControl PRIVATE_DAY = CacheControl.maxAge(1, TimeUnit.DAYS).cachePrivate();

    private final CatchLogCommandRepository repository;
    private final CatchLogWriter writer;

    public CatchLogController(CatchLogCommandRepository repository) {
        this.repository = repository;
        this.writer = new CatchLogWriter(repository);
    }

    /** @return the caller's logs: a JSON array, empty when they have none */
    @GetMapping("/mine")
    public ResponseEntity<ApiResponse<JsonNode>> mine(@RequestHeader(value = Caller.USER_HEADER, required = false) String user,
                                                      @RequestParam(required = false) String limit) {
        String userId = signedIn(user);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(ApiResponse.ok(repository.mine(userId, clamp(limit))));
    }

    /**
     * @param body {@code lakeId} (required) and any of species, fishId, title, notes, catchDate, weight + weightUnit,
     *             length + lengthUnit, method, tackle, lure, airTemp, weather, waterTemp, released, lat + lon, private,
     *             stationWeather
     * @return the stored log ({@code catch_memo_*} columns) with {@code catchLogId} and {@code stationWeather}
     */
    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<ApiResponse<JsonNode>> add(@RequestHeader(value = Caller.USER_HEADER, required = false) String user,
                                                     @RequestBody JsonNode body) {
        String userId = signedIn(user);
        if (body == null || !body.isObject()) {
            throw new InvalidDocumentException("The body must be a JSON object");
        }
        return ResponseEntity.ok(ApiResponse.ok(writer.add(userId, body)));
    }

    /**
     * Corrects one of the caller's logs (1.43.0): {@code 404} when it is not theirs, {@code 403 locked} after the
     * 60-day edit window, a field rule broken is a {@code 400} before any SQL.
     *
     * @return the log as stored
     */
    @PatchMapping(value = "/{id}", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<ApiResponse<JsonNode>> update(@RequestHeader(value = Caller.USER_HEADER, required = false) String user,
                                                        @PathVariable String id, @RequestBody JsonNode body) {
        String userId = signedIn(user);
        String catchLogId = RiverController.normalizeGuid(id);
        if (body == null || !body.isObject()) {
            throw new InvalidDocumentException("The body must be a JSON object");
        }
        for (String fixed : new String[] {"lakeId", "userId"}) {
            if (body.has(fixed)) {
                throw new InvalidDocumentException(fixed + " cannot be changed");
            }
        }
        CatchLog current = repository.find(catchLogId);
        if (current == null || !userId.equalsIgnoreCase(current.userId())) {
            throw notFound(catchLogId);
        }
        if (!Boolean.TRUE.equals(repository.canEdit(catchLogId, userId))) {
            throw new ApiProblemException(HttpStatus.FORBIDDEN, "locked",
                    "A catch log can be changed for 60 days after it is logged");
        }
        JsonNode stored = repository.add(writer.merge(current, body));
        if (stored == null) {
            throw notFound(catchLogId);
        }
        return ResponseEntity.ok(ApiResponse.ok(stored));
    }

    /** @return the log as stored, with {@code imageCount} */
    @PostMapping(value = "/{id}/photo", consumes = {MediaType.IMAGE_JPEG_VALUE, MediaType.IMAGE_PNG_VALUE, "image/webp"})
    public ResponseEntity<ApiResponse<JsonNode>> addPhoto(@RequestHeader(value = Caller.USER_HEADER, required = false) String user,
                                                          @PathVariable String id,
                                                          @RequestParam(required = false) String caption,
                                                          @RequestParam(required = false) String credit,
                                                          @RequestBody byte[] jpeg) {
        String userId = signedIn(user);
        String catchLogId = RiverController.normalizeGuid(id);
        String description = bounded(caption, "caption", 500);
        String author = bounded(credit, "credit", 200);
        if (jpeg == null || jpeg.length == 0) {
            throw new InvalidDocumentException("The body must be the image");
        }
        if (jpeg.length > MAX_PHOTO_BYTES) {
            throw new InvalidDocumentException("The photo is larger than " + MAX_PHOTO_BYTES / 1_000_000 + " MB");
        }
        jpeg = CatchPhotoImage.asJpeg(jpeg);   // a PNG/WebP becomes a JPEG; anything else is a 400
        Boolean editable = repository.canEdit(catchLogId, userId);
        if (editable == null || !editable && !isAuthor(catchLogId, userId)) {
            throw notFound(catchLogId);
        }
        if (!editable) {
            throw new ApiProblemException(HttpStatus.FORBIDDEN, "locked",
                    "A catch log can be changed for 60 days after it is logged");
        }
        int photos = repository.photoCount(catchLogId);
        if (photos >= CatchLogCommandRepository.MAX_PHOTOS) {
            throw new ApiProblemException(HttpStatus.CONFLICT, "too_many_photos",
                    "A catch log has at most " + CatchLogCommandRepository.MAX_PHOTOS + " photos");
        }
        var stored = repository.addPhoto(catchLogId, userId, jpeg, Math.max(photos, 0), description, author);
        if (stored == null) {
            throw notFound(catchLogId);
        }
        return ResponseEntity.ok(ApiResponse.ok(CatchLogArgs.stripPhotos(stored)));
    }

    /** One of the caller's photos as {@code image/jpeg}. */
    @GetMapping("/photo/{id}/{photoId}")
    public ResponseEntity<byte[]> photo(@RequestHeader(value = Caller.USER_HEADER, required = false) String user,
                                        @PathVariable String id, @PathVariable String photoId) {
        String userId = signedIn(user);
        String catchLogId = RiverController.normalizeGuid(id);
        String photo = RiverController.normalizeGuid(photoId);
        if (!isAuthor(catchLogId, userId)) {
            throw notFound(catchLogId);
        }
        byte[] jpeg = repository.photo(catchLogId, photo);
        if (jpeg == null) {
            throw new ApiProblemException(HttpStatus.NOT_FOUND, "not_found", "No photo " + photo);
        }
        return ResponseEntity.ok().cacheControl(PRIVATE_DAY).contentType(MediaType.IMAGE_JPEG).body(jpeg);
    }

    private boolean isAuthor(String catchLogId, String userId) {
        CatchLog log = repository.find(catchLogId);
        return log != null && userId.equalsIgnoreCase(log.userId());
    }

    /** The account cproxy named, as a canonical GUID; 401 when there is none. */
    private static String signedIn(String header) {
        String userId = Caller.fromHeaders(null, header).userId();
        if (userId == null) {
            throw new ApiProblemException(HttpStatus.UNAUTHORIZED, "sign_in_required", "Sign in to use the catch log");
        }
        return userId;
    }

    private static ApiProblemException notFound(String catchLogId) {
        return new ApiProblemException(HttpStatus.NOT_FOUND, "not_found", "No catch log " + catchLogId);
    }

    private static String bounded(String value, String name, int max) {
        if (value == null || value.isBlank()) return null;
        String v = value.trim();
        if (v.length() > max) throw new InvalidDocumentException(name + " must not exceed " + max + " characters");
        return v;
    }

    static int clamp(String raw) {
        try {
            int n = Integer.parseInt(raw.trim());
            return n < 1 ? DEFAULT_LIMIT : Math.min(n, MAX_LIMIT);
        } catch (RuntimeException ex) {
            return DEFAULT_LIMIT;
        }
    }
}
