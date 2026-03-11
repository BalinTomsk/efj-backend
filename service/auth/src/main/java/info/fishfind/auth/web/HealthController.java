package info.fishfind.auth.web;

import info.fishfind.auth.dto.AuthDtos;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.OffsetDateTime;

@RestController
public class HealthController {
    @GetMapping("/api/health")
    public AuthDtos.HealthResponse health() {
        return new AuthDtos.HealthResponse("OK", OffsetDateTime.now());
    }
}
