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

class WeatherGovFetcherTest {

    private HttpServer server;
    private int port;
    private final AtomicReference<String> lastPath = new AtomicReference<>();
    private final AtomicReference<String> lastAccept = new AtomicReference<>();
    private final AtomicReference<String> lastUserAgent = new AtomicReference<>();
    private final AtomicInteger requestCount = new AtomicInteger();

    private WeatherGovFetcher fetcher;

    @BeforeEach
    void startServer() throws IOException {
        requestCount.set(0);
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            int count = requestCount.incrementAndGet();
            lastPath.set(exchange.getRequestURI().getPath());
            lastAccept.set(exchange.getRequestHeaders().getFirst("Accept"));
            lastUserAgent.set(exchange.getRequestHeaders().getFirst("User-Agent"));

            String path = exchange.getRequestURI().getPath();
            String normalizedPath = path.toUpperCase();
            if (normalizedPath.contains("/NOTFOUND/")) {
                exchange.sendResponseHeaders(404, -1);
                exchange.close();
                return;
            }
            if (normalizedPath.contains("/RATELIMIT-ALWAYS/")
                    || (normalizedPath.contains("/RATELIMIT-ONCE/") && count == 1)) {
                exchange.getResponseHeaders().set("Retry-After", "0");
                exchange.sendResponseHeaders(429, -1);
                exchange.close();
                return;
            }
            if (normalizedPath.contains("/HTML/")) {
                byte[] html = "<html></html>".getBytes(StandardCharsets.UTF_8);
                exchange.sendResponseHeaders(200, html.length);
                exchange.getResponseBody().write(html);
                exchange.close();
                return;
            }

            byte[] body = "{\"properties\":{\"temperature\":{\"value\":22.5}}}".getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(200, body.length);
            exchange.getResponseBody().write(body);
            exchange.close();
        });
        server.start();
        port = server.getAddress().getPort();

        fetcher = new WeatherGovFetcher();
        ReflectionTestUtils.setField(fetcher, "connectTimeoutMs", 5000);
        ReflectionTestUtils.setField(fetcher, "readTimeoutMs", 5000);
        ReflectionTestUtils.setField(fetcher, "baseUrl", "http://127.0.0.1:" + port);
        ReflectionTestUtils.setField(fetcher, "userAgent", "efj-backend-weather-test/1.0 (ops@example.com)");
        ReflectionTestUtils.setField(fetcher, "rateLimitMaxRetries", 2);
        ReflectionTestUtils.setField(fetcher, "rateLimitDefaultWaitMs", 10L);
        ReflectionTestUtils.setField(fetcher, "rateLimitMaxWaitMs", 1000L);
        ReflectionTestUtils.setField(fetcher, "maxResponseBytes", 5 * 1024 * 1024);
    }

    @AfterEach
    void stopServer() {
        server.stop(0);
    }

    @Test
    void fetchesLatestObservationWithWeatherGovHeaders() throws IOException {
        String json = fetcher.fetchLatestObservation("knyc");

        assertThat(json).contains("\"temperature\"");
        assertThat(lastPath.get()).isEqualTo("/stations/KNYC/observations/latest");
        assertThat(lastAccept.get()).isEqualTo("application/geo+json");
        assertThat(lastUserAgent.get()).isEqualTo("efj-backend-weather-test/1.0 (ops@example.com)");
    }

    @Test
    void throwsFileNotFoundOn404() {
        assertThatThrownBy(() -> fetcher.fetchLatestObservation("notfound"))
                .isInstanceOf(FileNotFoundException.class);
    }

    @Test
    void honoursRetryAfterThenSucceeds() throws IOException {
        String json = fetcher.fetchLatestObservation("ratelimit-once");

        assertThat(json).contains("\"temperature\"");
        assertThat(requestCount.get()).isEqualTo(2);
    }

    @Test
    void throwsRateLimitedAfterExhaustingRetries() {
        assertThatThrownBy(() -> fetcher.fetchLatestObservation("ratelimit-always"))
                .isInstanceOf(RateLimitedException.class)
                .hasMessageContaining("after 2 waits");
        assertThat(requestCount.get()).isEqualTo(3);
    }

    @Test
    void rejectsNonJsonBodyOn200() {
        assertThatThrownBy(() -> fetcher.fetchLatestObservation("html"))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("JSON");
    }

    @Test
    void rejectsBlankStationId() {
        assertThatThrownBy(() -> fetcher.fetchLatestObservation(" "))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
