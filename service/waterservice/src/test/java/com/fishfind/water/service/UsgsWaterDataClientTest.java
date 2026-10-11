package com.fishfind.water.service;

import com.fishfind.water.domain.UsgsObservation;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.io.IOException;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.http.HttpStatus.TOO_MANY_REQUESTS;
import static org.springframework.test.web.client.ExpectedCount.once;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.queryParam;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class UsgsWaterDataClientTest {
    private static final String BASE = "https://usgs.test/ogcapi/v1/collections";

    private final RestClient.Builder builder = RestClient.builder();
    private final MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();

    private UsgsWaterDataClient client(String apiKey) {
        return new UsgsWaterDataClient(builder.build(), BASE, apiKey);
    }

    private static String feature(String site, String code, String value) {
        return "{\"type\":\"Feature\",\"properties\":{\"monitoring_location_id\":\"" + site + "\",\"parameter_code\":\""
                + code + "\",\"statistic_id\":\"00011\",\"time\":\"2026-10-11T04:00:00+00:00\",\"value\":\"" + value + "\"}}";
    }

    private static String page(String next, String... features) {
        String links = next == null ? "" : "{\"rel\":\"next\",\"href\":\"" + next + "\"}";
        return "{\"type\":\"FeatureCollection\",\"features\":[" + String.join(",", features) + "],\"links\":[" + links + "]}";
    }

    @Test
    void fetchLatestFollowsNextLinksAndKeysByBareSiteNumber() throws Exception {
        UsgsWaterDataClient client = client("k");
        server.expect(once(), request -> assertTrue(request.getURI().toString().startsWith(BASE + "/latest-continuous/items?")))
                .andExpect(header("X-Api-Key", "k"))
                .andRespond(withSuccess(page(BASE + "/latest-continuous/items?cursor=2",
                        feature("USGS-08313000", "00060", "12.5")), MediaType.APPLICATION_JSON));
        server.expect(once(), requestTo(BASE + "/latest-continuous/items?cursor=2"))
                .andExpect(header("X-Api-Key", "k"))
                .andRespond(withSuccess(page(null,
                        feature("USGS-08313000", "00065", "3.3"), feature("USGS-05112000", "00060", "40")),
                        MediaType.APPLICATION_JSON));

        Map<String, List<UsgsObservation>> snapshot = client.fetchLatest(null);

        server.verify();
        assertEquals(2, snapshot.get("08313000").size());
        assertEquals("40", snapshot.get("05112000").get(0).value());
    }

    @Test
    void fetchLatestSingleStationFiltersBySite() throws Exception {
        server.expect(queryParam("monitoring_location_id", "USGS-08313000"))
                .andRespond(withSuccess(page(null), MediaType.APPLICATION_JSON));

        client("").fetchLatest("08313000");

        server.verify();
    }

    @Test
    void rateLimitFailsNamingTheKey() {
        server.expect(queryParam("f", "json")).andRespond(withStatus(TOO_MANY_REQUESTS));

        IOException thrown = assertThrows(IOException.class, () -> client("k").fetchLatest(null));

        assertTrue(thrown.getMessage().contains("USGS_API_KEY"));
    }

    @Test
    void ensureTimeZonesLooksUpEachSiteOnce() throws Exception {
        UsgsWaterDataClient client = client("k");
        server.expect(once(), queryParam("id", "USGS-09380000,USGS-00000000"))
                .andRespond(withSuccess("{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\","
                        + "\"id\":\"USGS-09380000\",\"properties\":{\"time_zone_abbreviation\":\"MST\","
                        + "\"uses_daylight_savings\":\"N\"}}]}", MediaType.APPLICATION_JSON));

        client.ensureTimeZones(List.of("09380000", "00000000"));
        client.ensureTimeZones(List.of("09380000", "00000000"));

        server.verify();
        assertEquals(ZoneOffset.ofHours(-7), client.timeZoneFor("09380000"));
        assertEquals(ZoneOffset.UTC, client.timeZoneFor("00000000"));
    }
}
