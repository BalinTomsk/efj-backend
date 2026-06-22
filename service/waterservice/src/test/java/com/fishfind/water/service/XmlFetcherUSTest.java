package com.fishfind.water.service;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.RestClient;

import java.io.FileNotFoundException;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
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
    void fetchThrowsFileNotFoundOn404() {
        server.expect(requestTo(URL)).andRespond(withStatus(NOT_FOUND));

        assertThrows(FileNotFoundException.class, () -> fetcher.fetch("NY", "08313000"));
    }

    @Test
    void fetchThrowsServerErrorOnNonSuccessStatus() {
        server.expect(requestTo(URL)).andRespond(withStatus(INTERNAL_SERVER_ERROR));

        assertThrows(HttpServerErrorException.class, () -> fetcher.fetch("NY", "08313000"));
    }
}
