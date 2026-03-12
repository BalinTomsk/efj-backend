package info.fishfind.auth.client;

import info.fishfind.auth.api.AuthPaths;
import info.fishfind.auth.api.dto.AuthDtos;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.web.client.RestClient;

public class AuthClient {
    private final RestClient restClient;

    /**
     * Creates a client backed by the provided Spring {@link RestClient}.
     *
     * @param restClient HTTP client configured for the auth service
     */
    public AuthClient(RestClient restClient) {
        this.restClient = restClient;
    }

    /**
     * Registers a new user account.
     *
     * @param request registration payload
     * @return registration result message
     */
    public AuthDtos.MessageResponse register(AuthDtos.RegisterRequest request) {
        return restClient.post()
                .uri(AuthPaths.REGISTER)
                .contentType(MediaType.APPLICATION_JSON)
                .body(request)
                .retrieve()
                .body(AuthDtos.MessageResponse.class);
    }

    /**
     * Activates a user account with the supplied activation token.
     *
     * @param activationToken account activation token
     * @return activation result message
     */
    public AuthDtos.MessageResponse activate(String activationToken) {
        return restClient.get()
                .uri(AuthPaths.ACTIVATE, activationToken)
                .retrieve()
                .body(AuthDtos.MessageResponse.class);
    }

    /**
     * Authenticates a user and returns a JWT with the profile payload.
     *
     * @param request login payload
     * @return login response with token and user data
     */
    public AuthDtos.LoginResponse login(AuthDtos.LoginRequest request) {
        return restClient.post()
                .uri(AuthPaths.LOGIN)
                .contentType(MediaType.APPLICATION_JSON)
                .body(request)
                .retrieve()
                .body(AuthDtos.LoginResponse.class);
    }

    /**
     * Validates a bearer token and returns the associated user.
     *
     * @param bearerToken authorization header value
     * @return wrapped authenticated user
     */
    public AuthDtos.UserWrapper validate(String bearerToken) {
        return authorizedGet(AuthPaths.VALIDATE, bearerToken, AuthDtos.UserWrapper.class);
    }

    /**
     * Fetches the authenticated user's profile.
     *
     * @param bearerToken authorization header value
     * @return wrapped user profile
     */
    public AuthDtos.UserWrapper profile(String bearerToken) {
        return authorizedGet(AuthPaths.PROFILE, bearerToken, AuthDtos.UserWrapper.class);
    }

    /**
     * Updates the authenticated user's profile fields.
     *
     * @param bearerToken authorization header value
     * @param request profile update payload
     * @return wrapped updated user profile
     */
    public AuthDtos.UserWrapper updateProfile(String bearerToken, AuthDtos.UpdateProfileRequest request) {
        return restClient.put()
                .uri(AuthPaths.PROFILE)
                .header(HttpHeaders.AUTHORIZATION, bearerToken)
                .contentType(MediaType.APPLICATION_JSON)
                .body(request)
                .retrieve()
                .body(AuthDtos.UserWrapper.class);
    }

    /**
     * Changes the authenticated user's password.
     *
     * @param bearerToken authorization header value
     * @param request password change payload
     * @return result message
     */
    public AuthDtos.MessageResponse changePassword(String bearerToken, AuthDtos.ChangePasswordRequest request) {
        return restClient.put()
                .uri(AuthPaths.CHANGE_PASSWORD)
                .header(HttpHeaders.AUTHORIZATION, bearerToken)
                .contentType(MediaType.APPLICATION_JSON)
                .body(request)
                .retrieve()
                .body(AuthDtos.MessageResponse.class);
    }

    /**
     * Deletes the authenticated user's account.
     *
     * @param bearerToken authorization header value
     * @return result message
     */
    public AuthDtos.MessageResponse deleteAccount(String bearerToken) {
        return restClient.delete()
                .uri(AuthPaths.ACCOUNT)
                .header(HttpHeaders.AUTHORIZATION, bearerToken)
                .retrieve()
                .body(AuthDtos.MessageResponse.class);
    }

    /**
     * Checks the auth service health endpoint.
     *
     * @return health status payload
     */
    public AuthDtos.HealthResponse health() {
        return restClient.get()
                .uri(AuthPaths.HEALTH)
                .retrieve()
                .body(AuthDtos.HealthResponse.class);
    }

    /**
     * Executes an authorized GET request and maps the response body.
     *
     * @param path auth service path
     * @param bearerToken authorization header value
     * @param type target response type
     * @param <T> response type
     * @return mapped response body
     */
    private <T> T authorizedGet(String path, String bearerToken, Class<T> type) {
        return restClient.get()
                .uri(path)
                .header(HttpHeaders.AUTHORIZATION, bearerToken)
                .retrieve()
                .body(type);
    }
}
