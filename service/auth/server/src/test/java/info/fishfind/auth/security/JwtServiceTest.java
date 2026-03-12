package info.fishfind.auth.security;

import info.fishfind.auth.api.model.AuthUser;
import info.fishfind.auth.config.AppProperties;
import io.jsonwebtoken.JwtException;
import org.junit.jupiter.api.Test;

import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class JwtServiceTest {

    @Test
    void generateTokenCreatesTokenThatCanBeParsedBackToAuthUser() {
        JwtService jwtService = new JwtService(appProperties(base64Secret("01234567890123456789012345678901"), 4));
        AuthUser authUser = new AuthUser(7L, "alice", "alice@example.com");

        String token = jwtService.generateToken(authUser);

        assertThat(token).isNotBlank();
        assertThat(jwtService.parseToken(token)).isEqualTo(authUser);
    }

    @Test
    void parseTokenThrowsWhenTokenWasSignedWithDifferentSecret() {
        JwtService signingService = new JwtService(appProperties(base64Secret("01234567890123456789012345678901"), 4));
        JwtService parsingService = new JwtService(appProperties(base64Secret("abcdefghijklmnopqrstuvwxyz123456"), 4));

        String token = signingService.generateToken(new AuthUser(7L, "alice", "alice@example.com"));

        assertThatThrownBy(() -> parsingService.parseToken(token))
                .isInstanceOf(JwtException.class);
    }

    private static AppProperties appProperties(String secret, long expirationHours) {
        return new AppProperties(
                "http://localhost:3000",
                new AppProperties.Jwt(secret, expirationHours),
                new AppProperties.Mail("noreply@example.com"),
                new AppProperties.RateLimit(100, 1)
        );
    }

    private static String base64Secret(String rawSecret) {
        return Base64.getEncoder().encodeToString(rawSecret.getBytes());
    }
}
