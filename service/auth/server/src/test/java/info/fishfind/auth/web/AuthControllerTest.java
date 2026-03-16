package info.fishfind.auth.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import info.fishfind.auth.api.dto.AuthDtos;
import info.fishfind.auth.api.model.AuthUser;
import info.fishfind.auth.exception.ApiException;
import info.fishfind.auth.exception.GlobalExceptionHandler;
import info.fishfind.auth.service.AuthService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.OffsetDateTime;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class AuthControllerTest {

    private final ObjectMapper objectMapper = new ObjectMapper().findAndRegisterModules();

    private AuthService authService;
    private RequestMetadataResolver requestMetadataResolver;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        authService = mock(AuthService.class);
        requestMetadataResolver = mock(RequestMetadataResolver.class);
        when(requestMetadataResolver.resolve(any())).thenReturn(new RequestMetadata("127.0.0.1", "127.0.0.1", "", "JUnit"));
        mockMvc = MockMvcBuilders.standaloneSetup(new AuthController(authService, requestMetadataResolver))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();
    }

    @AfterEach
    void tearDown() {
        Mockito.reset(authService, requestMetadataResolver);
    }

    @Test
    void registerReturnsServiceResponse() throws Exception {
        when(authService.register(any(AuthDtos.RegisterRequest.class), any(RequestMetadata.class)))
                .thenReturn(new AuthDtos.MessageResponse("registered"));

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"username":"alice","email":"alice@example.com","password":"secret1","titul":"Captain","question":"Q","answer":"A","cell":"123"}
                                """))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("registered"));
    }

    @Test
    void registerReturnsBadRequestForInvalidBody() throws Exception {
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"username":"","email":"bad-email","password":"123"}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").isNotEmpty());
    }

    @Test
    void activateReturnsServiceResponse() throws Exception {
        when(authService.activate("token-123"))
                .thenReturn(new AuthDtos.MessageResponse("activated"));

        mockMvc.perform(get("/api/auth/activate/token-123"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("activated"));
    }

    @Test
    void loginReturnsServiceResponse() throws Exception {
        when(authService.login(any(AuthDtos.LoginRequest.class)))
                .thenReturn(new AuthDtos.LoginResponse("ok", "jwt-token", userResponse()));

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"login":"alice","password":"secret1"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("ok"))
                .andExpect(jsonPath("$.token").value("jwt-token"))
                .andExpect(jsonPath("$.user.id").value(7))
                .andExpect(jsonPath("$.user.username").value("alice"))
                .andExpect(jsonPath("$.user.titul").value("Captain"))
                .andExpect(jsonPath("$.user.suspended").value(false));
    }

    @Test
    void loginAcceptsEmailAliasForLoginField() throws Exception {
        when(authService.login(any(AuthDtos.LoginRequest.class)))
                .thenReturn(new AuthDtos.LoginResponse("ok", "jwt-token", userResponse()));

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"alice@example.com","password":"secret1"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("ok"));

        verify(authService).login(eq(new AuthDtos.LoginRequest("alice@example.com", "secret1")));
    }

    @Test
    void validatePassesAuthenticationToService() throws Exception {
        Authentication authentication = authentication();
        when(authService.validate(authentication)).thenReturn(new AuthDtos.UserWrapper(userResponse()));

        mockMvc.perform(get("/api/auth/validate").principal(authentication))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.user.email").value("alice@example.com"))
                .andExpect(jsonPath("$.user.question").value("River?"));

        verify(authService).validate(authentication);
    }

    @Test
    void profilePassesAuthenticationToService() throws Exception {
        Authentication authentication = authentication();
        when(authService.profile(authentication)).thenReturn(new AuthDtos.UserWrapper(userResponse()));

        mockMvc.perform(get("/api/auth/profile").principal(authentication))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.user.username").value("alice"))
                .andExpect(jsonPath("$.user.cell").value("555-0100"));

        verify(authService).profile(authentication);
    }

    @Test
    void updateProfileReturnsServiceResponse() throws Exception {
        Authentication authentication = authentication();
        when(authService.updateProfile(eq(authentication), any(AuthDtos.UpdateProfileRequest.class)))
                .thenReturn(new AuthDtos.UserWrapper(updatedUserResponse()));

        mockMvc.perform(put("/api/auth/profile")
                        .principal(authentication)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"username":"alice2","email":"alice2@example.com"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.user.username").value("alice2"))
                .andExpect(jsonPath("$.user.email").value("alice2@example.com"))
                .andExpect(jsonPath("$.user.titul").value("Captain"));
    }

    @Test
    void changePasswordReturnsServiceResponse() throws Exception {
        Authentication authentication = authentication();
        when(authService.changePassword(eq(authentication), any(AuthDtos.ChangePasswordRequest.class)))
                .thenReturn(new AuthDtos.MessageResponse("changed"));

        mockMvc.perform(put("/api/auth/change-password")
                        .principal(authentication)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"currentPassword":"oldpass","newPassword":"newpass1"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("changed"));
    }

    @Test
    void deleteAccountReturnsServiceResponse() throws Exception {
        Authentication authentication = authentication();
        when(authService.deleteAccount(authentication))
                .thenReturn(new AuthDtos.MessageResponse("deleted"));

        mockMvc.perform(delete("/api/auth/account").principal(authentication))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("deleted"));
    }

    @Test
    void controllerUsesGlobalExceptionHandlerForApiExceptions() throws Exception {
        when(authService.activate("bad-token"))
                .thenThrow(new ApiException(HttpStatus.BAD_REQUEST, "Invalid activation link"));

        mockMvc.perform(get("/api/auth/activate/bad-token"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Invalid activation link"));
    }

    private static Authentication authentication() {
        return new UsernamePasswordAuthenticationToken(
                new AuthUser(7L, "alice", "alice@example.com"),
                null
        );
    }

    private static AuthDtos.UserResponse userResponse() {
        return new AuthDtos.UserResponse(
                7L,
                "alice",
                "alice@example.com",
                "Captain",
                "555-0100",
                "River?",
                "Salmon",
                OffsetDateTime.parse("2026-03-12T03:00:00Z"),
                false,
                OffsetDateTime.parse("2026-03-12T00:00:00Z"),
                OffsetDateTime.parse("2026-03-12T01:00:00Z")
        );
    }

    private static AuthDtos.UserResponse updatedUserResponse() {
        return new AuthDtos.UserResponse(
                7L,
                "alice2",
                "alice2@example.com",
                "Captain",
                "555-0100",
                "River?",
                "Salmon",
                OffsetDateTime.parse("2026-03-12T03:00:00Z"),
                false,
                OffsetDateTime.parse("2026-03-12T00:00:00Z"),
                OffsetDateTime.parse("2026-03-12T02:00:00Z")
        );
    }
}
