package com.fishfind.water.service;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;

import java.io.FileNotFoundException;
import java.io.IOException;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withException;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import static org.springframework.http.HttpMethod.GET;
import static org.springframework.http.HttpStatus.INTERNAL_SERVER_ERROR;
import static org.springframework.http.HttpStatus.NOT_FOUND;

class XmlFetcherUSTest {

    private static final String URL =
            "https://waterservices.usgs.gov/nwis/iv/?sites=08313000&period=P3D&format=waterml";

    private final RestClient.Builder builder = RestClient.builder();
    private final MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    private final XmlFetcherUS fetcher = new XmlFetcherUS(builder.build());

    @Test
    void fetchReturnsBody() throws Exception {
        server.expect(requestTo(URL))
                .andExpect(method(GET))
                .andRespond(withSuccess("<root>ok</root>", MediaType.APPLICATION_XML));

        String xml = fetcher.fetch("NY", "08313000");

        assertEquals("<root>ok</root>", xml);
        server.verify();
    }

    @Test
    void fetchEncodesStationValueIntoTheQueryInsteadOfInterpolatingRaw() throws Exception {
        // A hostile/corrupt DB row must not be able to append or override query parameters.
        server.expect(requestTo(
                        "https://waterservices.usgs.gov/nwis/iv/?sites=08313000%26period%3DP1000Y&period=P3D&format=waterml"))
                .andRespond(withSuccess("<root/>", MediaType.APPLICATION_XML));

        fetcher.fetch("NY", "08313000&period=P1000Y");

        server.verify();
    }

    @Test
    void fetchThrowsFileNotFoundOn404WithStationContextInMessage() {
        server.expect(requestTo(URL)).andRespond(withStatus(NOT_FOUND));

        FileNotFoundException ex =
                assertThrows(FileNotFoundException.class, () -> fetcher.fetch("NY", "08313000"));

        // The message must be self-sufficient when it surfaces without caller context (stack traces, alerts).
        assertTrue(ex.getMessage().contains("08313000"), "message should name the station: " + ex.getMessage());
        assertTrue(ex.getMessage().contains("NY"), "message should name the state: " + ex.getMessage());
    }

    @Test
    void fetchThrowsServerErrorOnNonSuccessStatus() {
        server.expect(requestTo(URL)).andRespond(withStatus(INTERNAL_SERVER_ERROR));

        assertThrows(HttpServerErrorException.class, () -> fetcher.fetch("NY", "08313000"));
    }

    @Test
    void fetchClassifiesResponseIoFailureAsResourceAccessExceptionWithStationContext() {
        server.expect(requestTo(URL))
                .andRespond(withException(new IOException("chunked transfer encoding, state: READING_LENGTH")));

        ResourceAccessException ex =
                assertThrows(ResourceAccessException.class, () -> fetcher.fetch("NY", "08313000"));

        assertTrue(ex.getMessage().contains("08313000"), "message should name the station: " + ex.getMessage());
        assertTrue(ex.getMessage().contains("NY"), "message should name the state: " + ex.getMessage());
    }
}
