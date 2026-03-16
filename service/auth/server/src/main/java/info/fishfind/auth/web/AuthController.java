package info.fishfind.auth.web;

import info.fishfind.auth.api.AuthPaths;
import info.fishfind.auth.api.dto.AuthDtos;
import info.fishfind.auth.service.AuthService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping(AuthPaths.AUTH)
public class AuthController {
    private final AuthService authService;
    private final RequestMetadataResolver requestMetadataResolver;

    /**
     * Creates the REST controller for auth endpoints.
     *
     * @param authService auth business service
     */
    public AuthController(AuthService authService, RequestMetadataResolver requestMetadataResolver) {
        this.authService = authService;
        this.requestMetadataResolver = requestMetadataResolver;
    }

    /**
     * Registers a new user account.
     *
     * @param request registration payload
     * @return result message
     */
    @PostMapping("/register")
    public AuthDtos.MessageResponse register(@Valid @RequestBody AuthDtos.RegisterRequest request,
                                             HttpServletRequest httpServletRequest) {
        return authService.register(request, requestMetadataResolver.resolve(httpServletRequest));
    }

    /**
     * Activates an account from the emailed activation token.
     *
     * @param activationToken activation token from the URL
     * @return result message
     */
    @GetMapping("/activate/{activationToken}")
    public AuthDtos.MessageResponse activate(@PathVariable String activationToken) {
        return authService.activate(activationToken);
    }

    /**
     * Authenticates a user and returns a JWT.
     *
     * @param request login payload
     * @return login response
     */
    @PostMapping("/login")
    public AuthDtos.LoginResponse login(@Valid @RequestBody AuthDtos.LoginRequest request) {
        return authService.login(request);
    }

    /**
     * Validates the supplied bearer token and returns the authenticated user.
     *
     * @param authentication Spring Security authentication
     * @return wrapped authenticated user
     */
    @GetMapping("/validate")
    public AuthDtos.UserWrapper validate(Authentication authentication) {
        return authService.validate(authentication);
    }

    /**
     * Returns the current authenticated user's profile.
     *
     * @param authentication Spring Security authentication
     * @return wrapped user profile
     */
    @GetMapping("/profile")
    public AuthDtos.UserWrapper profile(Authentication authentication) {
        return authService.profile(authentication);
    }

    /**
     * Updates the current authenticated user's profile.
     *
     * @param authentication Spring Security authentication
     * @param request profile update payload
     * @return wrapped updated user profile
     */
    @PutMapping("/profile")
    public AuthDtos.UserWrapper updateProfile(Authentication authentication,
                                              @Valid @RequestBody AuthDtos.UpdateProfileRequest request) {
        return authService.updateProfile(authentication, request);
    }

    /**
     * Changes the current authenticated user's password.
     *
     * @param authentication Spring Security authentication
     * @param request password change payload
     * @return result message
     */
    @PutMapping("/change-password")
    public AuthDtos.MessageResponse changePassword(Authentication authentication,
                                                   @Valid @RequestBody AuthDtos.ChangePasswordRequest request) {
        return authService.changePassword(authentication, request);
    }

    /**
     * Deletes the current authenticated user's account.
     *
     * @param authentication Spring Security authentication
     * @return result message
     */
    @DeleteMapping("/account")
    public AuthDtos.MessageResponse deleteAccount(Authentication authentication) {
        return authService.deleteAccount(authentication);
    }
}
