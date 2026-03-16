package info.fishfind.auth.service;

import info.fishfind.auth.api.dto.AuthDtos;
import info.fishfind.auth.api.model.AuthUser;
import info.fishfind.auth.domain.User;
import info.fishfind.auth.exception.ApiException;
import info.fishfind.auth.repository.UserRepository;
import info.fishfind.auth.security.JwtService;
import info.fishfind.auth.web.RequestMetadata;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.OffsetDateTime;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class AuthServiceTest {

    private UserRepository userRepository;
    private PasswordEncoder passwordEncoder;
    private JwtService jwtService;
    private EmailService emailService;
    private AuthService authService;
    private RequestMetadata requestMetadata;

    @BeforeEach
    void setUp() {
        userRepository = mock(UserRepository.class);
        passwordEncoder = mock(PasswordEncoder.class);
        jwtService = mock(JwtService.class);
        emailService = mock(EmailService.class);
        authService = new AuthService(userRepository, passwordEncoder, jwtService, emailService);
        requestMetadata = new RequestMetadata("127.0.0.1", "127.0.0.1", "", "JUnit");
    }

    @Test
    void registerCreatesAccountAndSendsActivationEmail() {
        AuthDtos.RegisterRequest request = new AuthDtos.RegisterRequest(
                "alice", "alice@example.com", "password", "Captain", "River?", "Salmon", "555-0100");

        when(passwordEncoder.encode("password")).thenReturn("encoded-password");

        AuthDtos.MessageResponse response = authService.register(request, requestMetadata);

        assertThat(response.message()).isEqualTo("Account created. Please check your email and activate your account.");
        verify(userRepository).insert(
                eq("alice"),
                eq("alice@example.com"),
                eq("encoded-password"),
                eq("127.0.0.1"),
                eq(""),
                eq("Captain"),
                eq("River?"),
                eq("Salmon"),
                eq("555-0100"),
                eq("JUnit"),
                anyString()
        );
        verify(emailService).sendActivationEmail(eq("alice@example.com"), eq("alice"), anyString());
    }

    @Test
    void registerReturnsConflictWhenInsertViolatesUniqueness() {
        AuthDtos.RegisterRequest request = new AuthDtos.RegisterRequest("alice", "alice@example.com", "password", null, null, null, null);

        when(passwordEncoder.encode("password")).thenReturn("encoded-password");
        doThrow(new DataIntegrityViolationException("duplicate"))
                .when(userRepository).insert(
                        eq("alice"), eq("alice@example.com"), eq("encoded-password"),
                        eq("127.0.0.1"), eq(""), eq(""), eq(""), eq(""), eq(""), eq("JUnit"), anyString());

        assertApiException(
                () -> authService.register(request, requestMetadata),
                HttpStatus.CONFLICT,
                "Username or email already exists"
        );

        verifyNoInteractions(emailService);
    }

    @Test
    void registerReturnsServerErrorWhenActivationEmailFails() {
        AuthDtos.RegisterRequest request = new AuthDtos.RegisterRequest("alice", "alice@example.com", "password", null, null, null, null);

        when(passwordEncoder.encode("password")).thenReturn("encoded-password");
        doThrow(new IllegalStateException("mail down"))
                .when(emailService).sendActivationEmail(eq("alice@example.com"), eq("alice"), anyString());

        assertApiException(
                () -> authService.register(request, requestMetadata),
                HttpStatus.INTERNAL_SERVER_ERROR,
                "Account created in database, but sending activation email failed"
        );
    }

    @Test
    void registerRejectsDuplicateNetwork() {
        AuthDtos.RegisterRequest request = new AuthDtos.RegisterRequest("alice", "alice@example.com", "password", null, null, null, null);
        when(userRepository.findByNetwork("127.0.0.1", "")).thenReturn(Optional.of(sampleUser(true)));

        assertApiException(
                () -> authService.register(request, requestMetadata),
                HttpStatus.FORBIDDEN,
                "registration ignored due to network issues, please write a letter for manual registration"
        );

        verifyNoInteractions(passwordEncoder, emailService);
    }

    @Test
    void activateRejectsBlankToken() {
        assertApiException(
                () -> authService.activate(" "),
                HttpStatus.BAD_REQUEST,
                "Activation token is required"
        );
    }

    @Test
    void activateRejectsUnknownToken() {
        when(userRepository.findByConfirmationToken("missing")).thenReturn(Optional.empty());

        assertApiException(
                () -> authService.activate("missing"),
                HttpStatus.BAD_REQUEST,
                "Invalid activation link"
        );
    }

    @Test
    void activateReturnsAlreadyActivatedMessageForConfirmedUser() {
        when(userRepository.findByConfirmationToken("token-123")).thenReturn(Optional.of(sampleUser(true)));

        AuthDtos.MessageResponse response = authService.activate("token-123");

        assertThat(response.message()).isEqualTo("Account is already activated. You can log in now.");
    }

    @Test
    void activateConfirmsUnconfirmedUser() {
        when(userRepository.findByConfirmationToken("token-123")).thenReturn(Optional.of(sampleUser(false)));

        AuthDtos.MessageResponse response = authService.activate("token-123");

        assertThat(response.message()).isEqualTo("Account activated successfully. You can now log in.");
        verify(userRepository).activateUser(7L);
    }

    @Test
    void loginRejectsUnknownUser() {
        when(userRepository.findByEmailOrUsername("alice")).thenReturn(Optional.empty());

        assertApiException(
                () -> authService.login(new AuthDtos.LoginRequest("alice", "password")),
                HttpStatus.UNAUTHORIZED,
                "Invalid credentials"
        );
    }

    @Test
    void loginRejectsUnconfirmedUser() {
        when(userRepository.findByEmailOrUsername("alice")).thenReturn(Optional.of(sampleUser(false)));

        assertApiException(
                () -> authService.login(new AuthDtos.LoginRequest("alice", "password")),
                HttpStatus.UNAUTHORIZED,
                "Please activate your email before logging in"
        );
    }

    @Test
    void loginRejectsSuspendedUser() {
        when(userRepository.findByEmailOrUsername("alice")).thenReturn(Optional.of(suspendedUser()));

        assertApiException(
                () -> authService.login(new AuthDtos.LoginRequest("alice", "password")),
                HttpStatus.NOT_FOUND,
                "Endpoint not found"
        );
    }

    @Test
    void loginRejectsWrongPassword() {
        User user = sampleUser(true);
        when(userRepository.findByEmailOrUsername("alice")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("wrong-password", "stored-password")).thenReturn(false);

        assertApiException(
                () -> authService.login(new AuthDtos.LoginRequest("alice", "wrong-password")),
                HttpStatus.UNAUTHORIZED,
                "Invalid credentials"
        );
    }

    @Test
    void loginReturnsTokenAndUserForValidCredentials() {
        User user = sampleUser(true);
        when(userRepository.findByEmailOrUsername("alice")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("password", "stored-password")).thenReturn(true);
        when(userRepository.findById(7L)).thenReturn(Optional.of(sampleUserWithLastVisit()));
        when(jwtService.generateToken(new AuthUser(7L, "alice", "alice@example.com"))).thenReturn("jwt-token");

        AuthDtos.LoginResponse response = authService.login(new AuthDtos.LoginRequest("alice", "password"));

        assertThat(response.message()).isEqualTo("Login successful");
        assertThat(response.token()).isEqualTo("jwt-token");
        assertThat(response.user().id()).isEqualTo(7L);
        assertThat(response.user().username()).isEqualTo("alice");
        assertThat(response.user().email()).isEqualTo("alice@example.com");
        assertThat(response.user().lastVisit()).isEqualTo(OffsetDateTime.parse("2026-03-12T03:00:00Z"));
        verify(userRepository).updateLastVisit(eq(7L), any());
    }

    @Test
    void validateReturnsCurrentUser() {
        when(userRepository.findById(7L)).thenReturn(Optional.of(sampleUser(true)));

        AuthDtos.UserWrapper response = authService.validate(authentication());

        assertThat(response.user().id()).isEqualTo(7L);
        assertThat(response.user().username()).isEqualTo("alice");
    }

    @Test
    void profileRejectsMissingAuthentication() {
        assertApiException(
                () -> authService.profile(null),
                HttpStatus.UNAUTHORIZED,
                "Access token required"
        );
    }

    @Test
    void updateProfileReturnsUpdatedUser() {
        when(userRepository.updateProfile(7L, "alice2", "alice2@example.com")).thenReturn(1);
        when(userRepository.findById(7L)).thenReturn(Optional.of(updatedUser()));

        AuthDtos.UserWrapper response = authService.updateProfile(
                authentication(),
                new AuthDtos.UpdateProfileRequest("alice2", "alice2@example.com")
        );

        assertThat(response.user().username()).isEqualTo("alice2");
        assertThat(response.user().email()).isEqualTo("alice2@example.com");
    }

    @Test
    void updateProfileReturnsConflictOnDuplicateFields() {
        when(userRepository.findById(7L)).thenReturn(Optional.of(sampleUser(true)));
        doThrow(new DataIntegrityViolationException("duplicate"))
                .when(userRepository).updateProfile(7L, "alice2", "alice2@example.com");

        assertApiException(
                () -> authService.updateProfile(
                        authentication(),
                        new AuthDtos.UpdateProfileRequest("alice2", "alice2@example.com")
                ),
                HttpStatus.CONFLICT,
                "Username or email already exists"
        );
    }

    @Test
    void changePasswordRejectsIncorrectCurrentPassword() {
        when(userRepository.findById(7L)).thenReturn(Optional.of(sampleUser(true)));
        when(passwordEncoder.matches("wrong-password", "stored-password")).thenReturn(false);

        assertApiException(
                () -> authService.changePassword(
                        authentication(),
                        new AuthDtos.ChangePasswordRequest("wrong-password", "new-password")
                ),
                HttpStatus.UNAUTHORIZED,
                "Current password is incorrect"
        );
    }

    @Test
    void changePasswordUpdatesStoredPassword() {
        when(userRepository.findById(7L)).thenReturn(Optional.of(sampleUser(true)));
        when(passwordEncoder.matches("current-password", "stored-password")).thenReturn(true);
        when(passwordEncoder.encode("new-password")).thenReturn("encoded-new-password");

        AuthDtos.MessageResponse response = authService.changePassword(
                authentication(),
                new AuthDtos.ChangePasswordRequest("current-password", "new-password")
        );

        assertThat(response.message()).isEqualTo("Password changed successfully");
        verify(userRepository).updatePassword(7L, "encoded-new-password");
    }

    @Test
    void deleteAccountRejectsMissingUser() {
        when(userRepository.findById(7L)).thenReturn(Optional.of(sampleUser(true)));
        when(userRepository.deleteById(7L)).thenReturn(0);

        assertApiException(
                () -> authService.deleteAccount(authentication()),
                HttpStatus.NOT_FOUND,
                "User not found"
        );
    }

    @Test
    void deleteAccountDeletesCurrentUser() {
        when(userRepository.findById(7L)).thenReturn(Optional.of(sampleUser(true)));
        when(userRepository.deleteById(7L)).thenReturn(1);

        AuthDtos.MessageResponse response = authService.deleteAccount(authentication());

        assertThat(response.message()).isEqualTo("Account deleted successfully");
    }

    private static Authentication authentication() {
        return new UsernamePasswordAuthenticationToken(
                new AuthUser(7L, "alice", "alice@example.com"),
                null
        );
    }

    private static User sampleUser(boolean confirmed) {
        OffsetDateTime createdAt = OffsetDateTime.parse("2026-03-12T00:00:00Z");
        OffsetDateTime updatedAt = OffsetDateTime.parse("2026-03-12T01:00:00Z");
        return new User(
                7L,
                "alice",
                "alice@example.com",
                "stored-password",
                "127.0.0.1",
                "",
                "Captain",
                null,
                "River?",
                "Salmon",
                "555-0100",
                false,
                "JUnit",
                confirmed,
                "token-123",
                createdAt,
                updatedAt
        );
    }

    private static User updatedUser() {
        OffsetDateTime createdAt = OffsetDateTime.parse("2026-03-12T00:00:00Z");
        OffsetDateTime updatedAt = OffsetDateTime.parse("2026-03-12T02:00:00Z");
        return new User(
                7L,
                "alice2",
                "alice2@example.com",
                "stored-password",
                "127.0.0.1",
                "",
                "Captain",
                OffsetDateTime.parse("2026-03-12T03:00:00Z"),
                "River?",
                "Salmon",
                "555-0100",
                false,
                "JUnit",
                true,
                null,
                createdAt,
                updatedAt
        );
    }

    private static User sampleUserWithLastVisit() {
        OffsetDateTime createdAt = OffsetDateTime.parse("2026-03-12T00:00:00Z");
        OffsetDateTime updatedAt = OffsetDateTime.parse("2026-03-12T03:00:00Z");
        return new User(
                7L,
                "alice",
                "alice@example.com",
                "stored-password",
                "127.0.0.1",
                "",
                "Captain",
                OffsetDateTime.parse("2026-03-12T03:00:00Z"),
                "River?",
                "Salmon",
                "555-0100",
                false,
                "JUnit",
                true,
                null,
                createdAt,
                updatedAt
        );
    }

    private static User suspendedUser() {
        OffsetDateTime createdAt = OffsetDateTime.parse("2026-03-12T00:00:00Z");
        OffsetDateTime updatedAt = OffsetDateTime.parse("2026-03-12T01:00:00Z");
        return new User(
                7L,
                "alice",
                "alice@example.com",
                "stored-password",
                "127.0.0.1",
                "",
                "Captain",
                null,
                "River?",
                "Salmon",
                "555-0100",
                true,
                "JUnit",
                true,
                null,
                createdAt,
                updatedAt
        );
    }

    private static void assertApiException(ThrowingCall call, HttpStatus status, String message) {
        assertThatThrownBy(call::run)
                .isInstanceOfSatisfying(ApiException.class, ex -> {
                    assertThat(ex.getStatus()).isEqualTo(status);
                    assertThat(ex.getMessage()).isEqualTo(message);
                });
    }

    @FunctionalInterface
    private interface ThrowingCall {
        void run();
    }
}
