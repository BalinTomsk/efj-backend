package info.fishfind.auth.service;

import info.fishfind.auth.domain.User;
import info.fishfind.auth.dto.AuthDtos;
import info.fishfind.auth.exception.ApiException;
import info.fishfind.auth.repository.UserRepository;
import info.fishfind.auth.security.AuthUser;
import info.fishfind.auth.security.JwtService;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
public class AuthService {
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final EmailService emailService;

    public AuthService(UserRepository userRepository,
                       PasswordEncoder passwordEncoder,
                       JwtService jwtService,
                       EmailService emailService) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.emailService = emailService;
    }

    public AuthDtos.MessageResponse register(AuthDtos.RegisterRequest request) {
        String hashedPassword = passwordEncoder.encode(request.password());
        String activationToken = UUID.randomUUID().toString();

        try {
            userRepository.insert(request.username(), request.email(), hashedPassword, activationToken);
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

    public AuthDtos.LoginResponse login(AuthDtos.LoginRequest request) {
        User user = userRepository.findByEmailOrUsername(request.login())
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "Invalid credentials"));

        if (!user.confirmed()) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Please activate your email before logging in");
        }

        if (!passwordEncoder.matches(request.password(), user.password())) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Invalid credentials");
        }

        String token = jwtService.generateToken(new AuthUser(user.id(), user.username(), user.email()));
        return new AuthDtos.LoginResponse("Login successful", token, toResponse(user));
    }

    public AuthDtos.UserWrapper validate(Authentication authentication) {
        return new AuthDtos.UserWrapper(getCurrentUser(authentication));
    }

    public AuthDtos.UserWrapper profile(Authentication authentication) {
        return new AuthDtos.UserWrapper(getCurrentUser(authentication));
    }

    public AuthDtos.UserWrapper updateProfile(Authentication authentication, AuthDtos.UpdateProfileRequest request) {
        AuthUser authUser = requireAuthUser(authentication);
        try {
            int changed = userRepository.updateProfile(authUser.id(), request.username(), request.email());
            if (changed == 0) {
                throw new ApiException(HttpStatus.NOT_FOUND, "User not found");
            }
        } catch (DataIntegrityViolationException ex) {
            throw new ApiException(HttpStatus.CONFLICT, "Username or email already exists");
        }
        User updated = userRepository.findById(authUser.id())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "User not found"));
        return new AuthDtos.UserWrapper(toResponse(updated));
    }

    public AuthDtos.MessageResponse changePassword(Authentication authentication,
                                                   AuthDtos.ChangePasswordRequest request) {
        AuthUser authUser = requireAuthUser(authentication);
        User user = userRepository.findById(authUser.id())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "User not found"));

        if (!passwordEncoder.matches(request.currentPassword(), user.password())) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Current password is incorrect");
        }

        userRepository.updatePassword(authUser.id(), passwordEncoder.encode(request.newPassword()));
        return new AuthDtos.MessageResponse("Password changed successfully");
    }

    public AuthDtos.MessageResponse deleteAccount(Authentication authentication) {
        AuthUser authUser = requireAuthUser(authentication);
        int changed = userRepository.deleteById(authUser.id());
        if (changed == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "User not found");
        }
        return new AuthDtos.MessageResponse("Account deleted successfully");
    }

    private AuthUser requireAuthUser(Authentication authentication) {
        if (authentication == null || !(authentication.getPrincipal() instanceof AuthUser authUser)) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Access token required");
        }
        return authUser;
    }

    private AuthDtos.UserResponse getCurrentUser(Authentication authentication) {
        AuthUser authUser = requireAuthUser(authentication);
        User user = userRepository.findById(authUser.id())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "User not found"));
        return toResponse(user);
    }

    private AuthDtos.UserResponse toResponse(User user) {
        return new AuthDtos.UserResponse(
                user.id(),
                user.username(),
                user.email(),
                user.createdAt(),
                user.updatedAt()
        );
    }
}
