package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.sun.net.httpserver.HttpServer;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

class WeatherCanadaFetcherTest {

    private HttpServer server;
    private int port;
    private final AtomicReference<String> lastPath = new AtomicReference<>();
    private final AtomicReference<String> lastQuery = new AtomicReference<>();
    private final AtomicReference<String> lastAccept = new AtomicReference<>();
    private final AtomicReference<String> lastUserAgent = new AtomicReference<>();

    private WeatherCanadaFetcher fetcher;

    @BeforeEach
    void startServer() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            lastPath.set(exchange.getRequestURI().getRawPath());
            lastQuery.set(exchange.getRequestURI().getRawQuery());
            lastAccept.set(exchange.getRequestHeaders().getFirst("Accept"));
            lastUserAgent.set(exchange.getRequestHeaders().getFirst("User-Agent"));

            String path = exchange.getRequestURI().getPath();
            if (path.startsWith("/notfound")) {
                exchange.sendResponseHeaders(404, -1);
                exchange.close();
                return;
            }
            if (path.startsWith("/empty")) {
                byte[] body = "{\"type\":\"FeatureCollection\",\"features\":[]}".getBytes(StandardCharsets.UTF_8);
                exchange.sendResponseHeaders(200, body.length);
                exchange.getResponseBody().write(body);
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

            byte[] body = "{\"type\":\"FeatureCollection\",\"features\":[{\"id\":\"obs-1\"}]}"
                    .getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(200, body.length);
            exchange.getResponseBody().write(body);
            exchange.close();
        });
        server.start();
        port = server.getAddress().getPort();

        fetcher = new WeatherCanadaFetcher();
        ReflectionTestUtils.setField(fetcher, "connectTimeoutMs", 5000);
        ReflectionTestUtils.setField(fetcher, "readTimeoutMs", 5000);
        ReflectionTestUtils.setField(fetcher, "baseUrl", "http://127.0.0.1:" + port);
        ReflectionTestUtils.setField(fetcher, "userAgent", "weather-canada-test");
        ReflectionTestUtils.setField(fetcher, "bboxRadiusDegrees", 0.05);
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
    void returnsBodyVerbatimOn200() throws IOException {
        String json = fetcher.fetchLatestObservation(43.6532, -79.3832);

        assertThat(json).isEqualTo("{\"type\":\"FeatureCollection\",\"features\":[{\"id\":\"obs-1\"}]}");
    }

    @Test
    void sendsSwobBboxQuery() throws IOException {
        fetcher.fetchLatestObservation(43.6532, -79.3832);

        assertThat(lastPath.get()).isEqualTo("/collections/swob-realtime/items");
        assertThat(lastQuery.get())
                .contains("lang=en")
                .contains("f=json")
                .contains("limit=1")
                .contains("sortby=-date_tm-value")
                .contains("bbox=-79.433200,43.603200,-79.333200,43.703200");
        assertThat(lastAccept.get()).isEqualTo("application/geo+json");
        assertThat(lastUserAgent.get()).isEqualTo("weather-canada-test");
    }

    @Test
    void throwsFileNotFoundOn404() {
        ReflectionTestUtils.setField(fetcher, "baseUrl", "http://127.0.0.1:" + port + "/notfound");

        assertThatThrownBy(() -> fetcher.fetchLatestObservation(1.0, 2.0))
                .isInstanceOf(FileNotFoundException.class);
    }

    @Test
    void throwsFileNotFoundWhenNoFeaturesReturned() {
        ReflectionTestUtils.setField(fetcher, "baseUrl", "http://127.0.0.1:" + port + "/empty");

        assertThatThrownBy(() -> fetcher.fetchLatestObservation(1.0, 2.0))
                .isInstanceOf(FileNotFoundException.class)
                .hasMessageContaining("no SWOB features");
    }

    @Test
    void rejectsNonJsonBodyOn200() {
        ReflectionTestUtils.setField(fetcher, "baseUrl", "http://127.0.0.1:" + port + "/html");

        assertThatThrownBy(() -> fetcher.fetchLatestObservation(1.0, 2.0))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("JSON");
    }
}
