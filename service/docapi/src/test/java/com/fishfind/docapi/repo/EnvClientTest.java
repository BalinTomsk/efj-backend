package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.service.InvalidDocumentException;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.RowMapper;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.LocalDate;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.function.Function;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * {@link EnvClient} and the three readers that use it from 1.45.0 (forecast, river Weather tab, catch-log weather fill)
 * against a real HTTP server standing in for env_service: paths, query strings, envelope unwrapping, status mapping,
 * and the documents the readers build from env_service's answers.
 */
class EnvClientTest {

    private record Reply(int status, String json) {}

    private final ObjectMapper om = new ObjectMapper();
    private final List<String> seen = new CopyOnWriteArrayList<>();
    private volatile Function<String, Reply> handler = uri -> new Reply(200, "{\"data\":null}");
    private HttpServer server;
    private EnvClient client;

    @BeforeEach
    void start() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", this::serve);
        server.start();
        CircuitBreaker breaker = CircuitBreaker.of("envBreaker", CircuitBreakerConfig.custom()
                .slidingWindowSize(4).minimumNumberOfCalls(4).failureRateThreshold(50)
                .waitDurationInOpenState(Duration.ofMinutes(1))
                .ignoreExceptions(InvalidDocumentException.class).build());
        client = new EnvClient("http://127.0.0.1:" + server.getAddress().getPort() + "/", Duration.ofSeconds(1),
                Duration.ofSeconds(2), om, breaker);
    }

    @AfterEach
    void stop() {
        server.stop(0);
    }

    private void serve(HttpExchange ex) throws IOException {
        String uri = ex.getRequestURI().toString();
        seen.add(uri);
        Reply r = handler.apply(uri);
        byte[] body = r.json().getBytes(StandardCharsets.UTF_8);
        ex.getResponseHeaders().add("Content-Type", "application/json");
        ex.sendResponseHeaders(r.status(), body.length);
        ex.getResponseBody().write(body);
        ex.close();
    }

    @SuppressWarnings("unchecked")
    private static JdbcTemplate lakeRow(String guid, String name) {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        List<Object> rows = guid == null ? List.of() : List.of((Object) new String[] {guid, name});
        when(jdbc.query(anyString(), any(PreparedStatementSetter.class), any(RowMapper.class))).thenReturn(rows);
        return jdbc;
    }

    @Test
    void forecastStationsSendsDocapisArgumentsAndReturnsTheBody() {
        handler = uri -> new Reply(200, "{\"data\":{\"total\":3,\"stations\":[]},\"error\":null}");

        JsonNode doc = new HttpForecastQueryRepository(client)
                .stations("2cffb500-3e59-4120-9460-055856e9ac5c", 43.45, -80.49, 100, "CA", 20);

        assertThat(seen.get(0)).isEqualTo("/api/v1/env/forecast/stations?fish=2cffb500-3e59-4120-9460-055856e9ac5c"
                + "&lat=43.45&lon=-80.49&radius=100&limit=20&country=CA");
        assertThat(doc.path("total").asInt()).isEqualTo(3);
    }

    @Test
    void forecastPlotAndReasoningPathsAnd404IsNull() {
        handler = uri -> new Reply(404, "{\"data\":null,\"error\":{\"code\":\"not_found\",\"message\":\"Unknown\"}}");
        HttpForecastQueryRepository repo = new HttpForecastQueryRepository(client);

        assertThat(repo.plot(12, "f1")).isNull();
        assertThat(repo.reasoning(12, "f1", 3)).isNull();
        assertThat(seen).containsExactly("/api/v1/env/forecast/plot/12?fish=f1", "/api/v1/env/forecast/reasoning/12?fish=f1&day=3");
    }

    @Test
    void a503IsUnavailableAnd400IsTheCallersMistake() {
        handler = uri -> new Reply(503, "{\"data\":null,\"error\":{\"code\":\"unavailable\",\"message\":\"loading\"}}");
        assertThatThrownBy(() -> client.get("/forecast/plot/1?fish=x")).isInstanceOf(EnvUnavailableException.class);

        handler = uri -> new Reply(400, "{\"data\":null,\"error\":{\"code\":\"invalid_request\",\"message\":\"day must be 0..6\"}}");
        assertThatThrownBy(() -> client.get("/forecast/reasoning/1?fish=x&day=9"))
                .isInstanceOf(InvalidDocumentException.class).hasMessage("day must be 0..6");
    }

    @Test
    void riverWeatherKeepsTheWeatherTabShape() {
        handler = uri -> new Reply(200, """
                {"data":{"lakeId":"0d012b12-849c-20c3-8532-2f7a21cfcc58","lakeName":"Credit River","date":"2026-11-24","stations":[
                 {"station":{"sid":263811,"mli":"02HB001","country":"CA","state":"ON","lat":43.7,"lon":-79.9,"locName":"CREDIT NEAR CATARACT "},
                  "current":null,"weather":null},
                 {"station":{"sid":263810,"mli":"02HB004","country":"CA","state":"ON","lat":43.58,"lon":-79.71,"locName":"CREDIT AT ERINDALE "},
                  "current":{"ts":"2026-11-24T19:58:58Z","discharge":12.44,"turbidity":null,"oxygen":9.12345,"ph":7.80,"level":1.234},
                  "weather":{"date":"2026-11-24","conditions":"Rain","conditionsLong":"Light rain","icon":"rain","airTempC":2,
                             "tempHighC":6.5,"tempLowC":-1,"humidityPct":80,"windMaxKmh":12,"windDirection":"W","windDegree":270,
                             "precipChancePct":70,"rainTodayMm":3,"pressureMm":755.3}}]}}""");
        RiverQueryRepository sql = mock(RiverQueryRepository.class);

        JsonNode doc = new EnvRiverQueryRepository(sql, lakeRow("0D012B12-849C-20C3-8532-2F7A21CFCC58", "Credit River"), client, om)
                .weather("0d012b12-849c-20c3-8532-2f7a21cfcc58");

        assertThat(seen.get(0)).isEqualTo("/api/v1/env/lakes/0d012b12-849c-20c3-8532-2f7a21cfcc58/weather");
        assertThat(doc.path("guid").asText()).isEqualTo("0D012B12-849C-20C3-8532-2F7A21CFCC58");
        assertThat(doc.path("lakeName").asText()).isEqualTo("Credit River");
        JsonNode first = doc.path("stations").get(0);
        assertThat(first.path("mli").asText()).isEqualTo("02HB001");
        assertThat(first.get("science").isNull()).isTrue();
        assertThat(first.get("weather").isNull()).isTrue();
        JsonNode science = doc.path("stations").get(1).path("science");
        assertThat(science.path("discharge").asText()).isEqualTo("12.4");
        assertThat(science.path("discharge_unit").asText()).isEqualTo("m^3/s");
        assertThat(science.path("elevation").asText()).isEqualTo("1.23");
        assertThat(science.path("oxygen").asText()).isEqualTo("9.123");
        assertThat(science.path("ph").asText()).isEqualTo("7.8");
        assertThat(science.path("turbidity").asText()).isEqualTo("N/A");
        assertThat(science.path("velocity").asText()).isEqualTo("N/A");
        assertThat(science.path("stamp").asText()).isEqualTo("2026-11-24T19:58:58");
        assertThat(science.path("dt").asText()).isEqualTo("Nov 24, 2026");
        JsonNode weather = doc.path("stations").get(1).path("weather");
        assertThat(weather.path("conditions").asText()).isEqualTo("Rain");
        assertThat(weather.path("temp_high").asDouble()).isEqualTo(6.5);
        assertThat(weather.path("precip_amount").asInt()).isEqualTo(3);
        assertThat(weather.path("wind_speed").asInt()).isEqualTo(12);
        assertThat(weather.has("pressureMm")).isFalse();
    }

    @Test
    void riverWeatherOfAnUnknownLakeIsNullWithoutAsking() {
        JsonNode doc = new EnvRiverQueryRepository(mock(RiverQueryRepository.class), lakeRow(null, null), client, om)
                .weather("00000000-0000-0000-0000-000000000001");

        assertThat(doc).isNull();
        assertThat(seen).isEmpty();
    }

    @Test
    void catchWeatherTakesTheFirstStationWithWeatherInHpa() {
        handler = uri -> new Reply(200, """
                {"data":{"stations":[
                 {"station":{"sid":1,"mli":"A"},"current":null,"weather":null},
                 {"station":{"sid":2,"mli":"B"},"current":null,
                  "weather":{"date":"2026-11-20","conditions":"Sunny","icon":"sun","tempHighC":4.5,"pressureMm":755.0}}]}}""");
        JdbcCatchLogCommandRepository repo = new JdbcCatchLogCommandRepository(mock(JdbcTemplate.class), om, client);

        CatchLog.Weather w = repo.stationWeather("0d012b12-849c-20c3-8532-2f7a21cfcc58", LocalDate.of(2026, 11, 20));

        assertThat(seen.get(0)).isEqualTo("/api/v1/env/lakes/0d012b12-849c-20c3-8532-2f7a21cfcc58/weather?date=2026-11-20");
        assertThat(w.temp()).isEqualTo(4.5);
        assertThat(w.pressure()).isEqualTo(1006.6);   // 755.0 mm Hg x 1.333224 = 1006.58 hPa, as catch_memo stores it
        assertThat(w.text()).isEqualTo("Sunny");
        assertThat(w.icon()).isEqualTo("sun");
        assertThat(w.water()).isNull();
    }

    @Test
    void catchWeatherOutsideTheWindowOrDownIsNoForecast() {
        JdbcCatchLogCommandRepository repo = new JdbcCatchLogCommandRepository(mock(JdbcTemplate.class), om, client);

        handler = uri -> new Reply(400, "{\"data\":null,\"error\":{\"code\":\"invalid_request\",\"message\":\"date must be within\"}}");
        assertThat(repo.stationWeather("0d012b12-849c-20c3-8532-2f7a21cfcc58", LocalDate.of(2020, 1, 1)))
                .isEqualTo(CatchLog.Weather.NONE);

        handler = uri -> new Reply(503, "{\"data\":null}");
        assertThat(repo.stationWeather("0d012b12-849c-20c3-8532-2f7a21cfcc58", LocalDate.of(2026, 11, 20)))
                .isEqualTo(CatchLog.Weather.NONE);
    }
}
