package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.sun.net.httpserver.HttpServer;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

class WundergroundFetcherTest {

    private static final String LOCATION_SUCCESS = "{\"location\":{\"stationId\":[\"KTESTPWS1\",\"KTESTPWS2\"]}}";
    private static final String OBSERVATION_SUCCESS =
            "{\"observations\":[{\"stationID\":\"KTESTPWS1\",\"imperial\":{\"temp\":72}}]}";

    private HttpServer server;
    private int port;
    private final List<String> requestedPaths = new CopyOnWriteArrayList<>();
    private final List<String> requestedQueries = new CopyOnWriteArrayList<>();
    private final AtomicInteger locationRequestCount = new AtomicInteger();
    private final AtomicInteger observationRequestCount = new AtomicInteger();

    private WundergroundFetcher fetcher;

    @BeforeEach
    void startServer() throws IOException {
        requestedPaths.clear();
        requestedQueries.clear();
        locationRequestCount.set(0);
        observationRequestCount.set(0);

        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            String path = exchange.getRequestURI().getPath();
            requestedPaths.add(path);
            requestedQueries.add(exchange.getRequestURI().getRawQuery());

            boolean isLocation = path.startsWith("/location");
            int count = isLocation ? locationRequestCount.incrementAndGet() : observationRequestCount.incrementAndGet();
            String scenario = path.substring(isLocation ? "/location".length() : "/observation".length());

            respond(exchange, scenario, count, isLocation);
        });
        server.start();
        port = server.getAddress().getPort();

        fetcher = new WundergroundFetcher();
        ReflectionTestUtils.setField(fetcher, "connectTimeoutMs", 5000);
        ReflectionTestUtils.setField(fetcher, "readTimeoutMs", 5000);
        ReflectionTestUtils.setField(fetcher, "locationBaseUrl", "http://127.0.0.1:" + port + "/location");
        ReflectionTestUtils.setField(fetcher, "observationBaseUrl", "http://127.0.0.1:" + port + "/observation");
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

    private void respond(com.sun.net.httpserver.HttpExchange exchange, String scenario, int count, boolean isLocation)
            throws IOException {
        if (scenario.startsWith("/notfound")) {
            exchange.sendResponseHeaders(404, -1);
            exchange.close();
            return;
        }
        if (scenario.startsWith("/auth")) {
            exchange.sendResponseHeaders(403, -1);
            exchange.close();
            return;
        }
        if (scenario.startsWith("/error")) {
            exchange.sendResponseHeaders(500, -1);
            exchange.close();
            return;
        }
        if (scenario.startsWith("/ratelimit-always")
                || (scenario.startsWith("/ratelimit-once") && count == 1)) {
            exchange.getResponseHeaders().set("Retry-After", "0");
            exchange.sendResponseHeaders(429, -1);
            exchange.close();
            return;
        }
        if (scenario.startsWith("/html")) {
            byte[] html = "<html></html>".getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(200, html.length);
            exchange.getResponseBody().write(html);
            exchange.close();
            return;
        }
        if (scenario.startsWith("/big")) {
            byte[] big = ("{\"pad\":\"" + "x".repeat(500) + "\"}").getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(200, big.length);
            exchange.getResponseBody().write(big);
            exchange.close();
            return;
        }
        if (scenario.startsWith("/empty")) {
            byte[] empty = "{\"location\":{\"stationId\":[]}}".getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(200, empty.length);
            exchange.getResponseBody().write(empty);
            exchange.close();
            return;
        }

        byte[] body = (isLocation ? LOCATION_SUCCESS : OBSERVATION_SUCCESS).getBytes(StandardCharsets.UTF_8);
        exchange.sendResponseHeaders(200, body.length);
        exchange.getResponseBody().write(body);
        exchange.close();
    }

    private void pointLocationAt(String scenario) {
        ReflectionTestUtils.setField(fetcher, "locationBaseUrl", "http://127.0.0.1:" + port + "/location" + scenario);
    }

    private void pointObservationAt(String scenario) {
        ReflectionTestUtils.setField(fetcher, "observationBaseUrl",
                "http://127.0.0.1:" + port + "/observation" + scenario);
    }

    @Test
    void returnsObservationBodyVerbatimOnSuccess() throws IOException {
        String json = fetcher.fetchCurrent(40.7128, -74.0060);

        assertThat(json).isEqualTo(OBSERVATION_SUCCESS);
    }

    @Test
    void sendsLocationLookupThenObservationQueryWithResolvedStationId() throws IOException {
        fetcher.fetchCurrent(40.7128, -74.0060);

        assertThat(requestedPaths).containsExactly("/location", "/observation");
        assertThat(requestedQueries.get(0))
                .contains("geocode=40.7128,-74.006")
                .contains("product=pws")
                .contains("apiKey=test-key");
        assertThat(requestedQueries.get(1))
                .contains("stationId=KTESTPWS1")
                .contains("apiKey=test-key");
    }

    @Test
    void throwsFileNotFoundWhenNoNearbyStation() {
        pointLocationAt("/empty");

        assertThatThrownBy(() -> fetcher.fetchCurrent(1.0, 2.0))
                .isInstanceOf(FileNotFoundException.class)
                .hasMessageContaining("No Wunderground PWS station found");
        assertThat(observationRequestCount.get()).isZero();
    }

    @Test
    void throwsFileNotFoundOn404DuringLocationLookup() {
        pointLocationAt("/notfound");

        assertThatThrownBy(() -> fetcher.fetchCurrent(1.0, 2.0))
                .isInstanceOf(FileNotFoundException.class);
        assertThat(observationRequestCount.get()).isZero();
    }

    @Test
    void throwsIoExceptionOnAuthFailureDuringLocationLookup() {
        pointLocationAt("/auth");

        assertThatThrownBy(() -> fetcher.fetchCurrent(1.0, 2.0))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("authentication");
    }

    @Test
    void throwsFileNotFoundOn404DuringObservationFetch() {
        pointObservationAt("/notfound");

        assertThatThrownBy(() -> fetcher.fetchCurrent(1.0, 2.0))
                .isInstanceOf(FileNotFoundException.class);
    }

    @Test
    void throwsIoExceptionOnOtherNon200() {
        pointObservationAt("/error");

        assertThatThrownBy(() -> fetcher.fetchCurrent(1.0, 2.0))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("HTTP 500");
    }

    @Test
    void honoursRetryAfterThenSucceeds() throws IOException {
        pointObservationAt("/ratelimit-once");

        String json = fetcher.fetchCurrent(1.0, 2.0);

        assertThat(json).contains("\"observations\"");
        assertThat(observationRequestCount.get()).isEqualTo(2);
    }

    @Test
    void throwsRateLimitedAfterExhaustingRetries() {
        pointObservationAt("/ratelimit-always");

        assertThatThrownBy(() -> fetcher.fetchCurrent(1.0, 2.0))
                .isInstanceOf(RateLimitedException.class)
                .hasMessageContaining("after 2 waits");
        assertThat(observationRequestCount.get()).isEqualTo(3);
    }

    @Test
    void rejectsNonJsonBodyOn200() {
        pointObservationAt("/html");

        assertThatThrownBy(() -> fetcher.fetchCurrent(1.0, 2.0))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("non-JSON");
    }

    @Test
    void rejectsBodyLargerThanConfiguredCap() {
        pointObservationAt("/big");
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
                .hasMessageContaining("WUNDERGROUND_API_KEY");
        assertThat(locationRequestCount.get()).isZero();
    }
}
