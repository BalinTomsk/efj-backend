package info.fishfind.auth.api.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;

public final class AuthDtos {
    /**
     * Prevents instantiation of the DTO container.
     */
    private AuthDtos() {
    }

    public record RegisterRequest(
            @NotBlank(message = "Username is required")
            String username,
            @NotBlank(message = "Email is required")
            @Email(message = "Email format is invalid")@Email
            String email,
            @NotBlank(message = "Password is required")
            @Size(min = 6, message = "Password must be at least 6 characters")
            String password,
            String titul,
            String question,
            String answer,
            String cell
    ) {
    }

    public record LoginRequest(
            @JsonAlias({"email", "username"})
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
            String titul,
            String cell,
            String question,
            String answer,
            OffsetDateTime lastVisit,
            boolean suspended,
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
