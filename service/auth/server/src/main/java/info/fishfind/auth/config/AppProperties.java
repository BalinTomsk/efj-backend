package info.fishfind.auth.config;

import jakarta.validation.constraints.NotBlank;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties(prefix = "app")
public record AppProperties(
        @NotBlank String frontendBaseUrl,
        Jwt jwt,
        Mail mail,
        RateLimit rateLimit
) {
    public record Jwt(
            @NotBlank String secret,
            long expirationHours
    ) {
    }

    public record Mail(
            @NotBlank String from
    ) {
    }

    public record RateLimit(
            int maxRequests,
            long windowMinutes
    ) {
    }
}
