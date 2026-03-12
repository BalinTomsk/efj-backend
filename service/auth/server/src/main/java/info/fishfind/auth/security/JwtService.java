package info.fishfind.auth.security;

import info.fishfind.auth.api.model.AuthUser;
import info.fishfind.auth.config.AppProperties;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.Map;

@Service
public class JwtService {
    private final AppProperties appProperties;

    /**
     * Creates the JWT service using application security properties.
     *
     * @param appProperties application properties
     */
    public JwtService(AppProperties appProperties) {
        this.appProperties = appProperties;
    }

    /**
     * Generates a signed JWT for the supplied authenticated user.
     *
     * @param user authenticated user payload
     * @return signed JWT string
     */
    public String generateToken(AuthUser user) {
        Instant now = Instant.now();
        Instant expiry = now.plus(appProperties.jwt().expirationHours(), ChronoUnit.HOURS);
        return Jwts.builder()
                .claims(Map.of(
                        "id", user.id(),
                        "username", user.username(),
                        "email", user.email()
                ))
                .subject(String.valueOf(user.id()))
                .issuedAt(Date.from(now))
                .expiration(Date.from(expiry))
                .signWith(secretKey())
                .compact();
    }

    /**
     * Parses a signed JWT and converts its claims into an {@link AuthUser}.
     *
     * @param token signed JWT string
     * @return authenticated user payload
     */
    public AuthUser parseToken(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(secretKey())
                .build()
                .parseSignedClaims(token)
                .getPayload();

        return new AuthUser(
                ((Number) claims.get("id")).longValue(),
                claims.get("username", String.class),
                claims.get("email", String.class)
        );
    }

    /**
     * Resolves the HMAC secret key used for signing and verifying JWTs.
     *
     * @return JWT secret key
     */
    private SecretKey secretKey() {
        return Keys.hmacShaKeyFor(Decoders.BASE64.decode(appProperties.jwt().secret()));
    }
}
