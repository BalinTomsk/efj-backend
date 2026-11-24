package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.service.InvalidDocumentException;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;
import com.fishfind.docapi.web.NewsController.NewsSearchQuery;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * {@link CsNewsClient} and the four HTTP news repositories against a real HTTP server standing in for csnews-env:
 * paths, query strings, bodies, envelope unwrapping, and the status → exception mapping.
 */
class CsNewsClientTest {

    private record Reply(int status, String contentType, byte[] body) {
        static Reply json(int status, String json) {
            return new Reply(status, "application/json", json.getBytes(StandardCharsets.UTF_8));
        }
    }

    private record Seen(String method, String uri, String body) {}

    private final ObjectMapper om = new ObjectMapper();
    private final List<Seen> seen = new CopyOnWriteArrayList<>();
    private volatile Function<String, Reply> handler = uri -> Reply.json(200, "{\"data\":null}");
    private HttpServer server;
    private CsNewsClient client;

    @BeforeEach
    void start() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", this::serve);
        server.start();
        CircuitBreaker breaker = CircuitBreaker.of("csnewsBreaker", CircuitBreakerConfig.custom()
                .slidingWindowSize(4).minimumNumberOfCalls(4).failureRateThreshold(50)
                .waitDurationInOpenState(Duration.ofMinutes(1))
                .ignoreExceptions(InvalidDocumentException.class).build());
        client = new CsNewsClient("http://127.0.0.1:" + server.getAddress().getPort() + "/", Duration.ofSeconds(1),
                Duration.ofSeconds(2), om, breaker);
    }

    @AfterEach
    void stop() {
        server.stop(0);
    }

    private void serve(HttpExchange ex) throws IOException {
        String body = new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
        String uri = ex.getRequestURI().toString();
        seen.add(new Seen(ex.getRequestMethod(), uri, body));
        Reply r = handler.apply(uri);
        ex.getResponseHeaders().add("Content-Type", r.contentType());
        ex.sendResponseHeaders(r.status(), r.body().length == 0 ? -1 : r.body().length);
        if (r.body().length > 0) {
            ex.getResponseBody().write(r.body());
        }
        ex.close();
    }

    @Test
    void listBindsTheEnvelopeAndSendsWindowOrderCountry() {
        handler = uri -> Reply.json(200, """
                {"data":{"items":[{"rn":1,"newsId":"n1","title":"T","source":"S","stamp":"2026-11-01",
                "flag":"CA.png","hasPhoto":true,"blockOrd":0}],"total":42,"offset":20,"limit":10},
                "error":null,"meta":{"timestamp":"x"}}""");

        NewsListPage page = new HttpNewsQueryRepository(client).list("US", 20, 10, NewsListOrder.EDITED);

        assertThat(seen.get(0).uri()).isEqualTo("/api/v1/csnews/list?offset=20&limit=10&order=edited&country=US");
        assertThat(page.total()).isEqualTo(42);
        assertThat(page.items().get(0).newsId()).isEqualTo("n1");
        assertThat(page.items().get(0).hasPhoto()).isTrue();
    }

    @Test
    void searchEncodesTheTermAndRepeatsFishIds() {
        handler = uri -> Reply.json(200, """
                {"data":{"items":[{"newsId":"n1","title":"T","source":null,"stamp":"2026-11-01","country":"CA",
                "fishes":[],"fishIds":["f1"]}],"total":1,"query":"walleye & pike","offset":0,"limit":20}}""");

        NewsSearchPage page = new HttpNewsQueryRepository(client)
                .search(new NewsSearchQuery("walleye & pike", List.of("f1", "f2"), null, 0, 20));

        assertThat(seen.get(0).uri())
                .isEqualTo("/api/v1/csnews/search?q=walleye%20%26%20pike&offset=0&limit=20&fishId=f1&fishId=f2");
        assertThat(page.items().get(0).fishIds()).containsExactly("f1");
    }

    @Test
    void notFoundIsNullForDocumentExportAndPhoto() {
        handler = uri -> Reply.json(404, "{\"data\":null,\"error\":{\"code\":\"not_found\",\"message\":\"x\"}}");

        assertThat(new HttpNewsDocumentRepository(client).getDocument("nope")).isNull();
        assertThat(new HttpNewsQueryRepository(client).exportNews("nope")).isNull();
        assertThat(new HttpNewsQueryRepository(client).newsPhoto("nope")).isNull();
    }

    @Test
    void documentIsTheRawJsonAndPhotoTheRawBytes() {
        handler = uri -> uri.startsWith("/api/v1/csnews/photo/")
                ? new Reply(200, "application/octet-stream", new byte[]{1, 2, 3})
                : Reply.json(200, "{\"data\":{\"news_id\":\"n1\",\"title\":\"Pike\"}}");

        assertThat(new HttpNewsDocumentRepository(client).getDocument("n1"))
                .isEqualTo("{\"news_id\":\"n1\",\"title\":\"Pike\"}");
        assertThat(new HttpNewsQueryRepository(client).newsPhoto("n1")).containsExactly(1, 2, 3);
    }

    @Test
    void insertSendsTheWriteWithBase64PhotosAndAWallClockStamp() throws Exception {
        handler = uri -> Reply.json(201, "{\"data\":{\"newsId\":\"new-id\"}}");
        NewsWrite write = new NewsWrite("Big pike", null, null, "Src", null, null, "p0", null, null, "CA",
                Timestamp.valueOf(LocalDateTime.of(2026, 11, 20, 8, 30)), "l1", "f1", null, null,
                new NewsWrite.Photo(new byte[]{9, 9}, "Ann", "pike"), null, null);

        String id = new HttpNewsWriteRepository(client).insert(write);

        assertThat(id).isEqualTo("new-id");
        assertThat(seen.get(0).method()).isEqualTo("POST");
        assertThat(seen.get(0).uri()).isEqualTo("/api/v1/csnews/doc");
        JsonNode body = om.readTree(seen.get(0).body());
        assertThat(body.get("stamp").asText()).isEqualTo("2026-11-20T08:30:00.000");
        assertThat(body.get("photo0").get("data").asText()).isEqualTo("CQk=");
        assertThat(body.get("photo1").get("data").isNull()).isTrue();
        assertThat(body.get("lakeId").asText()).isEqualTo("l1");
    }

    @Test
    void updateOfAnUnknownIdIsFalse_andSendsSlotZeroOnly() throws Exception {
        handler = uri -> Reply.json(404, "{\"data\":null,\"error\":{\"code\":\"not_found\",\"message\":\"x\"}}");
        NewsWrite write = new NewsWrite("T", null, null, null, null, null, null, null, null, null, null,
                null, null, null, null, null, null, null);

        assertThat(new HttpNewsWriteRepository(client).update("nx", write)).isFalse();
        assertThat(seen.get(0).method()).isEqualTo("PUT");
        assertThat(om.readTree(seen.get(0).body()).has("photo1")).isFalse();
    }

    @Test
    void adminDraftPublishAndPhoto() throws Exception {
        handler = uri -> switch (uri) {
            case "/api/v1/csnews/admin/draft" -> Reply.json(200, "{\"data\":{\"newsId\":\"d1\"}}");
            case "/api/v1/csnews/admin/publish" -> Reply.json(200, "{\"data\":{\"newsId\":\"d1\",\"action\":\"updated\"}}");
            default -> Reply.json(200, "{\"data\":{\"found\":true,\"updated\":true}}");
        };
        HttpNewsAdminCommandRepository repo = new HttpNewsAdminCommandRepository(client);

        assertThat(repo.createDraft()).isEqualTo("d1");
        assertThat(repo.publish(new NewsAdminCommandRepository.NewsAdminPublishRequest("d1", "T", null, null, null,
                null, null, null, null, null, null, "CA", null, null, null, null)))
                .isEqualTo(new NewsAdminCommandRepository.PublishResult("d1", "updated"));
        assertThat(repo.updatePhoto("d1", 2, new byte[]{7}, null, "alt"))
                .isEqualTo(new NewsAdminCommandRepository.PhotoUpdateResult(true, true));
        assertThat(seen.get(2).uri()).isEqualTo("/api/v1/csnews/admin/d1/photo/2");
        assertThat(om.readTree(seen.get(2).body()).get("data").asText()).isEqualTo("Bw==");
    }

    @Test
    void badRequestIsInvalidDocument_andDoesNotCountAgainstTheBreaker() {
        handler = uri -> Reply.json(400, "{\"data\":null,\"error\":{\"code\":\"invalid_request\",\"message\":\"limit must be 1..100\"}}");

        for (int i = 0; i < 6; i++) {
            assertThatThrownBy(() -> client.get("/list?limit=0"))
                    .isInstanceOf(InvalidDocumentException.class).hasMessage("limit must be 1..100");
        }
        assertThat(seen).hasSize(6);   // still calling: a 400 never opens the breaker
    }

    @Test
    void serverErrorsAreUnavailable_andOpenTheBreaker() {
        AtomicInteger calls = new AtomicInteger();
        handler = uri -> {
            calls.incrementAndGet();
            return Reply.json(503, "{\"data\":null,\"error\":{\"code\":\"unavailable\",\"message\":\"db down\"}}");
        };

        for (int i = 0; i < 4; i++) {
            assertThatThrownBy(() -> client.get("/default"))
                    .isInstanceOf(CsNewsUnavailableException.class)
                    .hasMessage("News is temporarily unavailable");   // never the internal detail
        }
        assertThatThrownBy(() -> client.get("/default")).isInstanceOf(CsNewsUnavailableException.class);

        assertThat(calls.get()).isEqualTo(4);   // the fifth call failed fast, the server never saw it
    }

    @Test
    void aDeadServerIsUnavailable_andPingSaysSo() {
        server.stop(0);

        assertThatThrownBy(() -> client.get("/default")).isInstanceOf(CsNewsUnavailableException.class);
        assertThat(client.reachable()).isFalse();
    }

    @Test
    void pingIsReachableOn200() {
        handler = uri -> Reply.json(200, "{\"data\":{\"mysql\":\"up\"}}");
        assertThat(client.reachable()).isTrue();
        assertThat(seen.get(0).uri()).isEqualTo("/api/v1/csnews/ping");
    }

    @Test
    void aMissingBaseUrlFailsAtStartup() {
        assertThatThrownBy(() -> new CsNewsClient(" ", Duration.ofSeconds(1), Duration.ofSeconds(1), om,
                CircuitBreaker.ofDefaults("x"))).isInstanceOf(IllegalStateException.class);
    }
}
