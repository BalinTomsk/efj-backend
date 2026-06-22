package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.sun.net.httpserver.HttpServer;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.IntStream;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * Exercises {@link OpenMeteoFetcher} against a real loopback HTTP server so the
 * full request-building and response-handling paths are covered.
 */
class OpenMeteoFetcherTest {

    private HttpServer server;
    private int port;
    private final AtomicReference<String> lastPath = new AtomicReference<>();
    private final AtomicReference<String> lastQuery = new AtomicReference<>();
    private final AtomicReference<String> lastUserAgent = new AtomicReference<>();

    private OpenMeteoFetcher fetcher;

    @BeforeEach
    void startServer() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            lastPath.set(exchange.getRequestURI().getPath());
            lastQuery.set(exchange.getRequestURI().getRawQuery());
            lastUserAgent.set(exchange.getRequestHeaders().getFirst("User-Agent"));

            String path = exchange.getRequestURI().getPath();
            if (path.startsWith("/notfound")) {
                exchange.sendResponseHeaders(404, -1);
                exchange.close();
                return;
            }
            if (path.startsWith("/error")) {
                exchange.sendResponseHeaders(500, -1);
                exchange.close();
                return;
            }

            // Body deliberately contains a backslash-quote sequence to prove the
            // payload is returned verbatim (no \" -> " rewriting).
            byte[] body = "{\"raw\":\"va\\\"lue\"}".getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(200, body.length);
            exchange.getResponseBody().write(body);
            exchange.close();
        });
        server.start();
        port = server.getAddress().getPort();

        fetcher = new OpenMeteoFetcher();
        ReflectionTestUtils.setField(fetcher, "connectTimeoutMs", 5000);
        ReflectionTestUtils.setField(fetcher, "readTimeoutMs", 5000);
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
        pointAt("/v1/forecast");

        String json = fetcher.fetch(47.5, -122.3);

        assertThat(json).isEqualTo("{\"raw\":\"va\\\"lue\"}");
    }

    @Test
    void sendsDailyUserAgentAndCoordinateQuery() throws IOException {
        pointAt("/v1/forecast");

        fetcher.fetch(47.5, -122.3);

        assertThat(lastUserAgent.get()).isEqualTo(OpenMeteoFetcher.currentUserAgent());
        assertThat(lastQuery.get())
                .contains("latitude=47.5")
                .contains("longitude=-122.3")
                .contains("hourly=temperature_2m")
                .contains("daily=temperature_2m_max")
                .contains("timezone=auto");
    }

    @Test
    void userAgentBuildNumbersAreDailyStableAndInRange() {
        LocalDate day = LocalDate.of(2026, 6, 22);

        String ua = OpenMeteoFetcher.currentUserAgent(day);
        assertThat(OpenMeteoFetcher.currentUserAgent(day)).isEqualTo(ua); // stable within a day

        Matcher m = Pattern.compile(
                "^Mozilla/5\\.0 \\(Windows NT 10\\.0; Win64; x64\\) AppleWebKit/537\\.(\\d+) "
                        + "\\(KHTML, like Gecko\\) Chrome/124\\.0 Safari/537\\.(\\d+)$")
                .matcher(ua);
        assertThat(m.matches()).as("UA matches Chrome-like pattern: %s", ua).isTrue();
        assertThat(Integer.parseInt(m.group(1))).isBetween(11, 97);
        assertThat(Integer.parseInt(m.group(2))).isBetween(11, 97);
    }

    @Test
    void userAgentVariesAcrossDays() {
        long distinct = IntStream.range(0, 30)
                .mapToObj(i -> OpenMeteoFetcher.currentUserAgent(LocalDate.of(2026, 1, 1).plusDays(i)))
                .distinct()
                .count();

        assertThat(distinct).isGreaterThan(1);
    }

    @Test
    void throwsFileNotFoundOn404() {
        pointAt("/notfound");

        assertThatThrownBy(() -> fetcher.fetch(1.0, 2.0))
                .isInstanceOf(FileNotFoundException.class);
    }

    @Test
    void throwsIoExceptionOnOtherNon200() {
        pointAt("/error");

        assertThatThrownBy(() -> fetcher.fetch(1.0, 2.0))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("HTTP 500");
    }
}
