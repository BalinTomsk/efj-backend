package info.fishfind.auth.client;

import info.fishfind.auth.api.AuthPaths;
import info.fishfind.auth.api.dto.AuthDtos;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.web.client.RestClient;

public class AuthClient {
    private final RestClient restClient;

    public AuthClient(RestClient restClient) {
        this.restClient = restClient;
    }

    public AuthDtos.MessageResponse register(AuthDtos.RegisterRequest request) {
        return restClient.post()
                .uri(AuthPaths.REGISTER)
                .contentType(MediaType.APPLICATION_JSON)
                .body(request)
                .retrieve()
                .body(AuthDtos.MessageResponse.class);
    }

    public AuthDtos.MessageResponse activate(String activationToken) {
        return restClient.get()
                .uri(AuthPaths.ACTIVATE, activationToken)
                .retrieve()
                .body(AuthDtos.MessageResponse.class);
    }

    public AuthDtos.LoginResponse login(AuthDtos.LoginRequest request) {
        return restClient.post()
                .uri(AuthPaths.LOGIN)
                .contentType(MediaType.APPLICATION_JSON)
                .body(request)
                .retrieve()
                .body(AuthDtos.LoginResponse.class);
    }

    public AuthDtos.UserWrapper validate(String bearerToken) {
        return authorizedGet(AuthPaths.VALIDATE, bearerToken, AuthDtos.UserWrapper.class);
    }

    public AuthDtos.UserWrapper profile(String bearerToken) {
        return authorizedGet(AuthPaths.PROFILE, bearerToken, AuthDtos.UserWrapper.class);
    }

    public AuthDtos.UserWrapper updateProfile(String bearerToken, AuthDtos.UpdateProfileRequest request) {
        return restClient.put()
                .uri(AuthPaths.PROFILE)
                .header(HttpHeaders.AUTHORIZATION, bearerToken)
                .contentType(MediaType.APPLICATION_JSON)
                .body(request)
                .retrieve()
                .body(AuthDtos.UserWrapper.class);
    }

    public AuthDtos.MessageResponse changePassword(String bearerToken, AuthDtos.ChangePasswordRequest request) {
        return restClient.put()
                .uri(AuthPaths.CHANGE_PASSWORD)
                .header(HttpHeaders.AUTHORIZATION, bearerToken)
                .contentType(MediaType.APPLICATION_JSON)
                .body(request)
                .retrieve()
                .body(AuthDtos.MessageResponse.class);
    }

    public AuthDtos.MessageResponse deleteAccount(String bearerToken) {
        return restClient.delete()
                .uri(AuthPaths.ACCOUNT)
                .header(HttpHeaders.AUTHORIZATION, bearerToken)
                .retrieve()
                .body(AuthDtos.MessageResponse.class);
    }

    public AuthDtos.HealthResponse health() {
        return restClient.get()
                .uri(AuthPaths.HEALTH)
                .retrieve()
                .body(AuthDtos.HealthResponse.class);
    }

    private <T> T authorizedGet(String path, String bearerToken, Class<T> type) {
        return restClient.get()
                .uri(path)
                .header(HttpHeaders.AUTHORIZATION, bearerToken)
                .retrieve()
                .body(type);
    }
}
