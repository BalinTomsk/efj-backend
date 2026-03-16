package info.fishfind.auth.domain;

import java.time.OffsetDateTime;

public record User(
        Long id,
        String username,
        String email,
        String password,
        String ip4,
        String ip6,
        String titul,
        OffsetDateTime lastVisit,
        String question,
        String answer,
        String cell,
        boolean suspended,
        String agent,
        boolean confirmed,
        String confirmationToken,
        OffsetDateTime createdAt,
        OffsetDateTime updatedAt
) {
}
