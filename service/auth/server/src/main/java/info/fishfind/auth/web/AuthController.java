package info.fishfind.auth.web;

import info.fishfind.auth.api.AuthPaths;
import info.fishfind.auth.api.dto.AuthDtos;
import info.fishfind.auth.service.AuthService;
import jakarta.validation.Valid;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping(AuthPaths.AUTH)
public class AuthController {
    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/register")
    public AuthDtos.MessageResponse register(@Valid @RequestBody AuthDtos.RegisterRequest request) {
        return authService.register(request);
    }

    @GetMapping("/activate/{activationToken}")
    public AuthDtos.MessageResponse activate(@PathVariable String activationToken) {
        return authService.activate(activationToken);
    }

    @PostMapping("/login")
    public AuthDtos.LoginResponse login(@Valid @RequestBody AuthDtos.LoginRequest request) {
        return authService.login(request);
    }

    @GetMapping("/validate")
    public AuthDtos.UserWrapper validate(Authentication authentication) {
        return authService.validate(authentication);
    }

    @GetMapping("/profile")
    public AuthDtos.UserWrapper profile(Authentication authentication) {
        return authService.profile(authentication);
    }

    @PutMapping("/profile")
    public AuthDtos.UserWrapper updateProfile(Authentication authentication,
                                              @Valid @RequestBody AuthDtos.UpdateProfileRequest request) {
        return authService.updateProfile(authentication, request);
    }

    @PutMapping("/change-password")
    public AuthDtos.MessageResponse changePassword(Authentication authentication,
                                                   @Valid @RequestBody AuthDtos.ChangePasswordRequest request) {
        return authService.changePassword(authentication, request);
    }

    @DeleteMapping("/account")
    public AuthDtos.MessageResponse deleteAccount(Authentication authentication) {
        return authService.deleteAccount(authentication);
    }
}
