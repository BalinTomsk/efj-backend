package info.fishfind.auth.api.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;

public final class AuthDtos {
    private AuthDtos() {
    }

    public record RegisterRequest(
            @NotBlank String username,
            @NotBlank @Email String email,
            @NotBlank @Size(min = 6) String password
    ) {
    }

    public record LoginRequest(
            @NotBlank String login,
            @NotBlank String password
    ) {
    }

    public record UpdateProfileRequest(
            @NotBlank String username,
            @NotBlank @Email String email
    ) {
    }

    public record ChangePasswordRequest(
            @NotBlank String currentPassword,
            @NotBlank @Size(min = 6) String newPassword
    ) {
    }

    public record UserResponse(
            Long id,
            String username,
            String email,
            OffsetDateTime createdAt,
            OffsetDateTime updatedAt
    ) {
    }

    public record MessageResponse(String message) {
    }

    public record LoginResponse(String message, String token, UserResponse user) {
    }

    public record UserWrapper(UserResponse user) {
    }

    public record ErrorResponse(String error) {
    }

    public record HealthResponse(String status, OffsetDateTime timestamp) {
    }
}
