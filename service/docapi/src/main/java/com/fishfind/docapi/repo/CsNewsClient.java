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
 * docapi's only way to the news database (1.44.0): the internal news data API of <strong>csnews-env</strong>
 * ({@code efcs-backend/service/csnews-env}, C#, on csnode), {@code /api/v1/csnews/*}. docapi holds no MySQL
 * driver or credential any more; it keeps the public {@code /api/v1/news/*} surface, its validation, role rules
 * and caches, and asks csnews-env on a cache miss.
 *
 * <ul>
 *   <li><strong>Envelope.</strong> csnews-env answers {@code {data, error, meta}}; {@link #get}/{@link #send}
 *   return {@code data}. A 404 is {@code null} (an unknown id, as the old repositories returned).</li>
 *   <li><strong>Errors.</strong> A 400 is a {@link InvalidDocumentException} (docapi validated first, so it should
 *   not happen). Anything else — 5xx, 503 from csnews-env's own MySQL breaker, connect/read failure, timeout —
 *   is a {@link CsNewsUnavailableException}, a 503 to the caller.</li>
 *   <li><strong>Breaker.</strong> Every call goes through the {@code csnewsBreaker} (application.yml), so a dead
 *   csnode fails fast. It is NOT the {@code sqlBreaker}: a news outage must never fail the SQL Server
 *   endpoints. A 400 is ignored by it.</li>
 *   <li><strong>Retry.</strong> A GET is retried once, only when the connection itself failed (a dropped
 *   handshake); a write never is. csnews-env retries its own MySQL reads.</li>
 *   <li><strong>Time budget.</strong> cproxy gives up after 10 s, so connect 2 s and a whole request 8 s.</li>
 * </ul>
 */
public class CsNewsClient {

    private static final Logger log = LoggerFactory.getLogger(CsNewsClient.class);

    static final String PREFIX = "/api/v1/csnews";

    private final HttpClient http;
    private final String baseUrl;
    private final Duration requestTimeout;
    private final ObjectMapper objectMapper;
    private final CircuitBreaker breaker;

    public CsNewsClient(String baseUrl, Duration connectTimeout, Duration requestTimeout,
                        ObjectMapper objectMapper, CircuitBreaker breaker) {
        if (baseUrl == null || baseUrl.isBlank()) {
            throw new IllegalStateException("CSNEWS_URL (csnews.url) must be set: docapi reads news from csnews-env");
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
        return guarded(() -> {
            HttpResponse<byte[]> r = exchange(request(path).GET().build(), true);
            return r.statusCode() == 404 ? null : data(r, path);
        });
    }

    /** GET {@code PREFIX + path} for raw bytes (the lead photo), or {@code null} on 404. */
    public byte[] getBytes(String path) {
        return guarded(() -> {
            HttpResponse<byte[]> r = exchange(request(path).GET().build(), true);
            if (r.statusCode() == 404) {
                return null;
            }
            check(r, path);
            return r.body();
        });
    }

    /**
     * POST/PUT {@code PREFIX + path} with a JSON body ({@code null} = empty): the {@code data} node, or
     * {@code null} on 404. Never retried.
     */
    public JsonNode send(String method, String path, Object body) {
        return guarded(() -> {
            byte[] json = body == null ? new byte[0] : objectMapper.writeValueAsBytes(body);
            HttpRequest req = request(path)
                    .header("Content-Type", "application/json")
                    .method(method, HttpRequest.BodyPublishers.ofByteArray(json))
                    .build();
            HttpResponse<byte[]> r = exchange(req, false);
            return r.statusCode() == 404 ? null : data(r, path);
        });
    }

    /** Whether csnews-env and its MySQL answer {@code GET /ping}; never throws, never counts against the breaker. */
    public boolean reachable() {
        try {
            HttpResponse<byte[]> r = http.send(request("/ping").GET().build(), HttpResponse.BodyHandlers.ofByteArray());
            return r.statusCode() == 200;
        } catch (IOException ex) {
            log.debug("csnews-env ping failed: {}", ex.toString());
            return false;
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            return false;
        }
    }

    /** Binds a {@code data} node to a record, failing as a 503 (a contract break, not the caller's fault). */
    public <T> T bind(JsonNode data, Class<T> type, String what) {
        try {
            return objectMapper.treeToValue(data, type);
        } catch (IOException ex) {
            throw new CsNewsUnavailableException("csnews-env returned a malformed " + what, ex);
        }
    }

    // ---- internals ------------------------------------------------------------------------------------------

    private HttpRequest.Builder request(String path) {
        return HttpRequest.newBuilder(URI.create(baseUrl + PREFIX + path))
                .timeout(requestTimeout)
                .header("Accept", "application/json, application/octet-stream");
    }

    @FunctionalInterface
    private interface Call<T> {
        T run() throws IOException, InterruptedException;
    }

    private <T> T guarded(Call<T> call) {
        Supplier<T> supplier = () -> {
            try {
                return call.run();
            } catch (IOException ex) {
                throw new CsNewsUnavailableException("csnews-env call failed: " + ex.getClass().getSimpleName(), ex);
            } catch (InterruptedException ex) {
                Thread.currentThread().interrupt();
                throw new CsNewsUnavailableException("interrupted while calling csnews-env", ex);
            }
        };
        try {
            return breaker.executeSupplier(supplier);
        } catch (CallNotPermittedException ex) {
            throw new CsNewsUnavailableException("csnews-env circuit open", ex);
        } catch (CsNewsUnavailableException ex) {
            log.warn("News unavailable: {}", ex.detail());
            throw ex;
        }
    }

    private HttpResponse<byte[]> exchange(HttpRequest req, boolean retryConnectFailure)
            throws IOException, InterruptedException {
        try {
            return http.send(req, HttpResponse.BodyHandlers.ofByteArray());
        } catch (java.net.ConnectException ex) {
            if (!retryConnectFailure) {
                throw ex;
            }
            log.debug("csnews-env connect failed, retrying once: {}", ex.toString());
            Thread.sleep(200);
            return http.send(req, HttpResponse.BodyHandlers.ofByteArray());
        }
    }

    private JsonNode data(HttpResponse<byte[]> r, String path) throws IOException {
        check(r, path);
        JsonNode root = objectMapper.readTree(r.body());
        return root == null ? null : root.get("data");
    }

    private void check(HttpResponse<byte[]> r, String path) {
        int status = r.statusCode();
        if (status >= 200 && status < 300) {
            return;
        }
        String message = errorMessage(r.body());
        if (status == 400) {
            throw new InvalidDocumentException(message == null ? "csnews-env rejected the request" : message);
        }
        throw new CsNewsUnavailableException("csnews-env answered " + status + " for " + path
                + (message == null ? "" : ": " + message), null);
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
