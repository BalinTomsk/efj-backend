package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.sun.net.httpserver.HttpServer;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

class GoogleWeatherFetcherTest {

    private HttpServer server;
    private int port;
    private final AtomicReference<String> lastPath = new AtomicReference<>();
    private final AtomicReference<String> lastQuery = new AtomicReference<>();
    private final AtomicReference<String> lastAccept = new AtomicReference<>();
    private final AtomicInteger requestCount = new AtomicInteger();

    private GoogleWeatherFetcher fetcher;

    @BeforeEach
    void startServer() throws IOException {
        requestCount.set(0);
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            int count = requestCount.incrementAndGet();
            lastPath.set(exchange.getRequestURI().getRawPath());
            lastQuery.set(exchange.getRequestURI().getRawQuery());
            lastAccept.set(exchange.getRequestHeaders().getFirst("Accept"));

            String path = exchange.getRequestURI().getPath();
            if (path.startsWith("/notfound")) {
                exchange.sendResponseHeaders(404, -1);
                exchange.close();
                return;
            }
            if (path.startsWith("/auth")) {
                exchange.sendResponseHeaders(403, -1);
                exchange.close();
                return;
            }
            if (path.startsWith("/error")) {
                exchange.sendResponseHeaders(500, -1);
                exchange.close();
                return;
            }
            if (path.startsWith("/ratelimit-always") || (path.startsWith("/ratelimit-once") && count == 1)) {
                exchange.getResponseHeaders().set("Retry-After", "0");
                exchange.sendResponseHeaders(429, -1);
                exchange.close();
                return;
            }
            if (path.startsWith("/html")) {
                byte[] html = "<html></html>".getBytes(StandardCharsets.UTF_8);
                exchange.sendResponseHeaders(200, html.length);
                exchange.getResponseBody().write(html);
                exchange.close();
                return;
            }
            if (path.startsWith("/big")) {
                byte[] big = ("{\"pad\":\"" + "x".repeat(500) + "\"}").getBytes(StandardCharsets.UTF_8);
                exchange.sendResponseHeaders(200, big.length);
                exchange.getResponseBody().write(big);
                exchange.close();
                return;
            }

            byte[] body = "{\"temperature\":{\"degrees\":84.2,\"unit\":\"FAHRENHEIT\"}}"
                    .getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(200, body.length);
            exchange.getResponseBody().write(body);
            exchange.close();
        });
        server.start();
        port = server.getAddress().getPort();

        fetcher = new GoogleWeatherFetcher();
        ReflectionTestUtils.setField(fetcher, "connectTimeoutMs", 5000);
        ReflectionTestUtils.setField(fetcher, "readTimeoutMs", 5000);
        ReflectionTestUtils.setField(fetcher, "baseUrl", "http://127.0.0.1:" + port);
        ReflectionTestUtils.setField(fetcher, "apiKey", "test-key");
        ReflectionTestUtils.setField(fetcher, "rateLimitMaxRetries", 2);
        ReflectionTestUtils.setField(fetcher, "rateLimitDefaultWaitMs", 10L);
        ReflectionTestUtils.setField(fetcher, "rateLimitMaxWaitMs", 1000L);
        ReflectionTestUtils.setField(fetcher, "maxResponseBytes", 5 * 1024 * 1024);
    }

    @AfterEach
    void stopServer() {
        server.stop(0);
    }

    private void pointAt(String path) {
        ReflectionTestUtils.setField(fetcher, "baseUrl", "http://127.0.0.1:" + port + path);
    }

    @Test
    void returnsBodyVerbatimOn200() throws IOException {
        String json = fetcher.fetchCurrent(40.7128, -74.0060);

        assertThat(json).isEqualTo("{\"temperature\":{\"degrees\":84.2,\"unit\":\"FAHRENHEIT\"}}");
    }

    @Test
    void sendsGoogleCurrentConditionsQuery() throws IOException {
        fetcher.fetchCurrent(40.7128, -74.0060);

        assertThat(lastPath.get()).isEqualTo("/");
        assertThat(lastQuery.get())
                .contains("location.latitude=40.7128")
                .contains("location.longitude=-74.006")
                .contains("unitsSystem=IMPERIAL")
                .contains("key=test-key");
        assertThat(lastAccept.get()).isEqualTo("application/json");
    }

    @Test
    void throwsFileNotFoundOn404() {
        pointAt("/notfound");

        assertThatThrownBy(() -> fetcher.fetchCurrent(1.0, 2.0))
                .isInstanceOf(FileNotFoundException.class);
    }

    @Test
    void throwsIoExceptionOnAuthenticationFailure() {
        pointAt("/auth");

        assertThatThrownBy(() -> fetcher.fetchCurrent(1.0, 2.0))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("authentication");
    }

    @Test
    void throwsIoExceptionOnOtherNon200() {
        pointAt("/error");

        assertThatThrownBy(() -> fetcher.fetchCurrent(1.0, 2.0))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("HTTP 500");
    }

    @Test
    void honoursRetryAfterThenSucceeds() throws IOException {
        pointAt("/ratelimit-once");

        String json = fetcher.fetchCurrent(1.0, 2.0);

        assertThat(json).contains("\"temperature\"");
        assertThat(requestCount.get()).isEqualTo(2);
    }

    @Test
    void throwsRateLimitedAfterExhaustingRetries() {
        pointAt("/ratelimit-always");

        assertThatThrownBy(() -> fetcher.fetchCurrent(1.0, 2.0))
                .isInstanceOf(RateLimitedException.class)
                .hasMessageContaining("after 2 waits");
        assertThat(requestCount.get()).isEqualTo(3);
    }

    @Test
    void rejectsNonJsonBodyOn200() {
        pointAt("/html");

        assertThatThrownBy(() -> fetcher.fetchCurrent(1.0, 2.0))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("JSON");
    }

    @Test
    void rejectsBodyLargerThanConfiguredCap() {
        pointAt("/big");
        ReflectionTestUtils.setField(fetcher, "maxResponseBytes", 64);

        assertThatThrownBy(() -> fetcher.fetchCurrent(1.0, 2.0))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("64");
    }

    @Test
    void failsWhenApiKeyMissing() {
        ReflectionTestUtils.setField(fetcher, "apiKey", " ");

        assertThatThrownBy(() -> fetcher.fetchCurrent(1.0, 2.0))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("GOOGLE_WEATHER_API_KEY");
        assertThat(requestCount.get()).isZero();
    }
}
