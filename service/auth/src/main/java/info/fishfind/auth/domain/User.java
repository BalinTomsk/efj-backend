package info.fishfind.auth.domain;

import java.time.OffsetDateTime;

public record User(
        Long id,
        String username,
        String email,
        String password,
        boolean confirmed,
        String confirmationToken,
        OffsetDateTime createdAt,
        OffsetDateTime updatedAt
) {
}
