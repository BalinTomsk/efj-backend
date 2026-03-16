package info.fishfind.auth.web;

import info.fishfind.auth.api.AuthPaths;
import info.fishfind.auth.api.dto.AuthDtos;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.OffsetDateTime;

/**
 * Exposes lightweight public endpoints used for service liveness checks and access probing.
 */
@RestController
public class HealthController {
    /**
     * Returns the current service health status and timestamp.
     *
     * @return health response payload
     */
    @GetMapping(AuthPaths.HEALTH)
    public AuthDtos.HealthResponse health() {
        return new AuthDtos.HealthResponse("OK", OffsetDateTime.now());
    }

    /**
     * Returns a no-content response for simple connectivity and access checks.
     *
     * @return empty 204 response
     */
    @GetMapping(AuthPaths.ACCESS_CHECK)
    public ResponseEntity<Void> accessCheck() {
        return ResponseEntity.noContent().build();
    }
}
