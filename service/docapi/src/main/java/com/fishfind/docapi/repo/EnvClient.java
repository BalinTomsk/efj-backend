package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.service.InvalidDocumentException;
import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.function.Supplier;

/**
 * docapi's way to the water and weather data (1.45.0, env_service plan step 6c): the read API of <strong>env_service</strong>
 * ({@code efcs-backend/service/env_service}, C#, on csnode), {@code /api/v1/env/*}, over the VPC. docapi keeps its public
 * {@code /forecast/*}, {@code /river/weather/{guid}} and catch-log endpoints, their validation and caches, and asks
 * env_service instead of SQL Server for the water and weather half. Built like {@link CsNewsClient}:
 * <ul>
 *   <li><strong>Envelope.</strong> env_service answers {@code {data, error, meta}}; {@link #get} returns {@code data}. A 404
 *   is {@code null} (an unknown station / fish pair, as the old repositories returned).</li>
 *   <li><strong>Errors.</strong> A 400 is an {@link InvalidDocumentException} (docapi validated first, so it should not
 *   happen). Anything else, including env_service's own 503 before its station cache has loaded, is an
 *   {@link EnvUnavailableException}: a 503 to the caller.</li>
 *   <li><strong>Breaker.</strong> Every call goes through the {@code envBreaker}, never the {@code sqlBreaker}: an
 *   env_service outage must not fail the SQL Server endpoints. A 400 is ignored by it.</li>
 *   <li><strong>Retry.</strong> Once, only when the connection itself failed. env_service retries its own database reads.</li>
 *   <li><strong>Time budget.</strong> cproxy gives up after 10 s, so connect 2 s and a whole request 8 s.</li>
 * </ul>
 */
public class EnvClient {

    private static final Logger log = LoggerFactory.getLogger(EnvClient.class);

    static final String PREFIX = "/api/v1/env";

    private final HttpClient http;
    private final String baseUrl;
    private final Duration requestTimeout;
    private final ObjectMapper objectMapper;
    private final CircuitBreaker breaker;

    public EnvClient(String baseUrl, Duration connectTimeout, Duration requestTimeout,
                     ObjectMapper objectMapper, CircuitBreaker breaker) {
        if (baseUrl == null || baseUrl.isBlank()) {
            throw new IllegalStateException("ENV_URL (env.url) must be set: docapi reads water and weather from env_service");
        }
        this.baseUrl = baseUrl.trim().replaceAll("/+$", "");
        this.http = HttpClient.newBuilder().connectTimeout(connectTimeout).version(HttpClient.Version.HTTP_1_1).build();
        this.requestTimeout = requestTimeout;
        this.objectMapper = objectMapper;
        this.breaker = breaker;
    }

    /** URL-encodes one path segment or query value. */
    public static String enc(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20");
    }

    /** GET {@code PREFIX + path}: the {@code data} node, or {@code null} on 404. */
    public JsonNode get(String path) {
        Supplier<JsonNode> call = () -> {
            try {
                HttpResponse<byte[]> r = exchange(request(path));
                return r.statusCode() == 404 ? null : data(r, path);
            } catch (IOException ex) {
                throw new EnvUnavailableException("env_service call failed: " + ex.getClass().getSimpleName(), ex);
            } catch (InterruptedException ex) {
                Thread.currentThread().interrupt();
                throw new EnvUnavailableException("interrupted while calling env_service", ex);
            }
        };
        try {
            return breaker.executeSupplier(call);
        } catch (CallNotPermittedException ex) {
            throw new EnvUnavailableException("env_service circuit open", ex);
        } catch (EnvUnavailableException ex) {
            log.warn("Water/weather unavailable: {}", ex.detail());
            throw ex;
        }
    }

    private HttpRequest request(String path) {
        return HttpRequest.newBuilder(URI.create(baseUrl + PREFIX + path))
                .timeout(requestTimeout)
                .header("Accept", "application/json")
                .GET()
                .build();
    }

    private HttpResponse<byte[]> exchange(HttpRequest req) throws IOException, InterruptedException {
        try {
            return http.send(req, HttpResponse.BodyHandlers.ofByteArray());
        } catch (java.net.ConnectException ex) {
            log.debug("env_service connect failed, retrying once: {}", ex.toString());
            Thread.sleep(200);
            return http.send(req, HttpResponse.BodyHandlers.ofByteArray());
        }
    }

    private JsonNode data(HttpResponse<byte[]> r, String path) throws IOException {
        int status = r.statusCode();
        if (status < 200 || status >= 300) {
            String message = errorMessage(r.body());
            if (status == 400) {
                throw new InvalidDocumentException(message == null ? "env_service rejected the request" : message);
            }
            throw new EnvUnavailableException("env_service answered " + status + " for " + path
                    + (message == null ? "" : ": " + message), null);
        }
        JsonNode root = objectMapper.readTree(r.body());
        return root == null ? null : root.get("data");
    }

    private String errorMessage(byte[] body) {
        try {
            JsonNode root = objectMapper.readTree(body);
            JsonNode message = root == null ? null : root.path("error").get("message");
            return message == null || message.isNull() ? null : message.asText();
        } catch (IOException | RuntimeException ex) {
            return null;
        }
    }
}
