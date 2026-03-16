package info.fishfind.auth.service;

import info.fishfind.auth.api.dto.AuthDtos;
import info.fishfind.auth.api.model.AuthUser;
import info.fishfind.auth.domain.User;
import info.fishfind.auth.exception.ApiException;
import info.fishfind.auth.repository.UserRepository;
import info.fishfind.auth.security.JwtService;
import info.fishfind.auth.web.RequestMetadata;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.time.OffsetDateTime;
import java.util.UUID;

@Service
public class AuthService {
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final EmailService emailService;

    /**
     * Creates the auth service with its persistence, security, and email collaborators.
     *
     * @param userRepository user repository
     * @param passwordEncoder password encoder
     * @param jwtService JWT service
     * @param emailService email delivery service
     */
    public AuthService(UserRepository userRepository,
                       PasswordEncoder passwordEncoder,
                       JwtService jwtService,
                       EmailService emailService) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.emailService = emailService;
    }

    /**
     * Registers a new account and sends an activation email.
     *
     * @param request registration payload
     * @return result message
     */
    public AuthDtos.MessageResponse register(AuthDtos.RegisterRequest request, RequestMetadata metadata) {
        if ((!metadata.ip4().isBlank() || !metadata.ip6().isBlank())
                && userRepository.findByNetwork(metadata.ip4(), metadata.ip6()).isPresent()) {
            throw new ApiException(HttpStatus.FORBIDDEN,
                    "registration ignored due to network issues, please write a letter for manual registration");
        }

        String hashedPassword = passwordEncoder.encode(request.password());
        String activationToken = UUID.randomUUID().toString();

        try {
            userRepository.insert(
                    request.username(),
                    request.email(),
                    hashedPassword,
                    metadata.ip4(),
                    metadata.ip6(),
                    trimToEmpty(request.titul()),
                    trimToEmpty(request.question()),
                    trimToEmpty(request.answer()),
                    trimToEmpty(request.cell()),
                    metadata.agent(),
                    activationToken
            );
        } catch (DataIntegrityViolationException ex) {
            throw new ApiException(HttpStatus.CONFLICT, "Username or email already exists");
        }

        try {
            emailService.sendActivationEmail(request.email(), request.username(), activationToken);
        } catch (IllegalStateException ex) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Account created in database, but sending activation email failed");
        }

        return new AuthDtos.MessageResponse("Account created. Please check your email and activate your account.");
    }

    /**
     * Activates a user account by confirmation token.
     *
     * @param activationToken activation token from the email link
     * @return result message
     */
    public AuthDtos.MessageResponse activate(String activationToken) {
        if (activationToken == null || activationToken.isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Activation token is required");
        }

        User user = userRepository.findByConfirmationToken(activationToken)
                .orElseThrow(() -> new ApiException(HttpStatus.BAD_REQUEST, "Invalid activation link"));

        if (user.confirmed()) {
            return new AuthDtos.MessageResponse("Account is already activated. You can log in now.");
        }

        userRepository.activateUser(user.id());
        return new AuthDtos.MessageResponse("Account activated successfully. You can now log in.");
    }

    /**
     * Authenticates a user and issues a JWT.
     *
     * @param request login payload
     * @return login result containing the token and user profile
     */
    public AuthDtos.LoginResponse login(AuthDtos.LoginRequest request) {
        User user = userRepository.findByEmailOrUsername(request.login())
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "Invalid credentials"));

        if (user.suspended()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Endpoint not found");
        }

        if (!user.confirmed()) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Please activate your email before logging in");
        }

        if (!passwordEncoder.matches(request.password(), user.password())) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Invalid credentials");
        }

        OffsetDateTime loginTimestamp = OffsetDateTime.now();
        userRepository.updateLastVisit(user.id(), loginTimestamp);
        User updatedUser = userRepository.findById(user.id())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Endpoint not found"));

        String token = jwtService.generateToken(new AuthUser(user.id(), user.username(), user.email()));
        return new AuthDtos.LoginResponse("Login successful", token, toResponse(updatedUser));
    }

    /**
     * Returns the authenticated user represented by the provided authentication object.
     *
     * @param authentication Spring Security authentication
     * @return wrapped authenticated user
     */
    public AuthDtos.UserWrapper validate(Authentication authentication) {
        return new AuthDtos.UserWrapper(getCurrentUser(authentication));
    }

    /**
     * Returns the current authenticated user's profile.
     *
     * @param authentication Spring Security authentication
     * @return wrapped user profile
     */
    public AuthDtos.UserWrapper profile(Authentication authentication) {
        return new AuthDtos.UserWrapper(getCurrentUser(authentication));
    }

    /**
     * Updates the current authenticated user's profile fields.
     *
     * @param authentication Spring Security authentication
     * @param request profile update payload
     * @return wrapped updated user profile
     */
    public AuthDtos.UserWrapper updateProfile(Authentication authentication, AuthDtos.UpdateProfileRequest request) {
        User currentUser = requireActiveUser(authentication);
        try {
            int changed = userRepository.updateProfile(currentUser.id(), request.username(), request.email());
            if (changed == 0) {
                throw new ApiException(HttpStatus.NOT_FOUND, "User not found");
            }
        } catch (DataIntegrityViolationException ex) {
            throw new ApiException(HttpStatus.CONFLICT, "Username or email already exists");
        }
        User updated = userRepository.findById(currentUser.id())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "User not found"));
        return new AuthDtos.UserWrapper(toResponse(updated));
    }

    /**
     * Changes the current authenticated user's password.
     *
     * @param authentication Spring Security authentication
     * @param request password change payload
     * @return result message
     */
    public AuthDtos.MessageResponse changePassword(Authentication authentication,
                                                   AuthDtos.ChangePasswordRequest request) {
        User user = requireActiveUser(authentication);

        if (!passwordEncoder.matches(request.currentPassword(), user.password())) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Current password is incorrect");
        }

        userRepository.updatePassword(user.id(), passwordEncoder.encode(request.newPassword()));
        return new AuthDtos.MessageResponse("Password changed successfully");
    }

    /**
     * Deletes the current authenticated user's account.
     *
     * @param authentication Spring Security authentication
     * @return result message
     */
    public AuthDtos.MessageResponse deleteAccount(Authentication authentication) {
        User user = requireActiveUser(authentication);
        int changed = userRepository.deleteById(user.id());
        if (changed == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "User not found");
        }
        return new AuthDtos.MessageResponse("Account deleted successfully");
    }

    /**
     * Extracts the authenticated user principal or raises an unauthorized error.
     *
     * @param authentication Spring Security authentication
     * @return authenticated user principal
     */
    private AuthUser requireAuthUser(Authentication authentication) {
        if (authentication == null || !(authentication.getPrincipal() instanceof AuthUser authUser)) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Access token required");
        }
        return authUser;
    }

    /**
     * Loads the current authenticated user from persistent storage.
     *
     * @param authentication Spring Security authentication
     * @return current user response payload
     */
    private AuthDtos.UserResponse getCurrentUser(Authentication authentication) {
        User user = requireActiveUser(authentication);
        return toResponse(user);
    }

    private User requireActiveUser(Authentication authentication) {
        AuthUser authUser = requireAuthUser(authentication);
        User user = userRepository.findById(authUser.id())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "User not found"));
        if (user.suspended()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Endpoint not found");
        }
        return user;
    }

    /**
     * Maps a domain user into the outward-facing API response model.
     *
     * @param user persisted user
     * @return API response payload
     */
    private AuthDtos.UserResponse toResponse(User user) {
        return new AuthDtos.UserResponse(
                user.id(),
                user.username(),
                user.email(),
                user.titul(),
                user.cell(),
                user.question(),
                user.answer(),
                user.lastVisit(),
                user.suspended(),
                user.createdAt(),
                user.updatedAt()
        );
    }

    private String trimToEmpty(String value) {
        return value == null ? "" : value.trim();
    }
}
