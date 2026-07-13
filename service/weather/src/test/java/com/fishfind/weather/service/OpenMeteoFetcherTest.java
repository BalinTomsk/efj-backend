package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.sun.net.httpserver.HttpServer;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.concurrent.atomic.AtomicInteger;
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
 * full request-building, response-handling, and 429/Retry-After paths are covered.
 * (Resilience4j retry/breaker/rate-limiter are AOP-applied at runtime and are not
 * active when the bean is constructed directly here.)
 */
class OpenMeteoFetcherTest {

    private HttpServer server;
    private int port;
    private final AtomicReference<String> lastQuery = new AtomicReference<>();
    private final AtomicReference<String> lastUserAgent = new AtomicReference<>();
    private final AtomicInteger requestCount = new AtomicInteger();

    private OpenMeteoFetcher fetcher;

    @BeforeEach
    void startServer() throws IOException {
        requestCount.set(0);
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            int count = requestCount.incrementAndGet();
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
            if (path.startsWith("/ratelimit-always") || (path.startsWith("/ratelimit-once") && count == 1)) {
                exchange.getResponseHeaders().set("Retry-After", "0");
                exchange.sendResponseHeaders(429, -1);
                exchange.close();
                return;
            }
            if (path.startsWith("/html")) {
                byte[] html = "<!doctype html><html><body>captive portal</body></html>"
                        .getBytes(StandardCharsets.UTF_8);
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

    @Test
    void honoursRetryAfterThenSucceeds() throws IOException {
        pointAt("/ratelimit-once");

        String json = fetcher.fetch(1.0, 2.0);

        assertThat(json).isEqualTo("{\"raw\":\"va\\\"lue\"}");
        assertThat(requestCount.get()).isEqualTo(2); // one 429, one success
    }

    @Test
    void throwsRateLimitedAfterExhaustingRetries() {
        pointAt("/ratelimit-always");

        assertThatThrownBy(() -> fetcher.fetch(1.0, 2.0))
                .isInstanceOf(RateLimitedException.class)
                // rateLimitMaxRetries is 2 (see startServer): exactly 2 waits are honoured
                // before giving up, so the message must say "2", not the off-by-one "3".
                .hasMessageContaining("after 2 waits");
        assertThat(requestCount.get()).isEqualTo(3); // initial + 2 retries
    }

    @Test
    void rejectsNonJsonBodyOn200() {
        pointAt("/html");

        assertThatThrownBy(() -> fetcher.fetch(1.0, 2.0))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("JSON");
    }

    @Test
    void rejectsBodyLargerThanConfiguredCap() {
        pointAt("/big");
        ReflectionTestUtils.setField(fetcher, "maxResponseBytes", 64);

        assertThatThrownBy(() -> fetcher.fetch(1.0, 2.0))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("64");
    }

    @Test
    void interruptDuringRetryAfterWaitIsNotRetriableIo() {
        pointAt("/ratelimit-always");

        Thread.currentThread().interrupt();
        try {
            // Must surface as RateLimitedException (excluded from Resilience4j retry),
            // not a plain IOException that would trigger up to 3 more backoff attempts
            // while the application is shutting down.
            assertThatThrownBy(() -> fetcher.fetch(1.0, 2.0))
                    .isInstanceOf(RateLimitedException.class);
            assertThat(Thread.currentThread().isInterrupted())
                    .as("interrupt flag must stay set for the worker loop")
                    .isTrue();
        } finally {
            Thread.interrupted(); // clear the flag so later tests are unaffected
        }
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
}
