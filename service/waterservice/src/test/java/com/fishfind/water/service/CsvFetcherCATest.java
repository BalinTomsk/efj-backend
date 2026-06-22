package com.fishfind.water.service;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.RestClient;

import java.io.FileNotFoundException;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import static org.springframework.http.HttpMethod.GET;
import static org.springframework.http.HttpStatus.INTERNAL_SERVER_ERROR;
import static org.springframework.http.HttpStatus.NOT_FOUND;

class CsvFetcherCATest {

    private static final String URL =
            "https://dd.weather.gc.ca/today/hydrometric/csv/QC/hourly/QC_02JE025_hourly_hydrometric.csv";

    private final RestClient.Builder builder = RestClient.builder()
            .defaultHeader(HttpHeaders.USER_AGENT, "water-station-pusher/1.0.0 (+https://fishfind.info)");
    private final MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    private final CsvFetcherCA fetcher = new CsvFetcherCA(builder.build());

    @Test
    void fetchReturnsCsvBodyAndSendsIdentifyingUserAgent() throws Exception {
        String body = "station,stamp,level,a,b,c,discharge\n02JE025,2024-01-02T03:04:05Z,1.2,0,0,0,3.4\n";
        server.expect(requestTo(URL))
                .andExpect(method(GET))
                .andExpect(header(HttpHeaders.USER_AGENT, "water-station-pusher/1.0.0 (+https://fishfind.info)"))
                .andRespond(withSuccess(body, MediaType.TEXT_PLAIN));

        String result = fetcher.fetch("QC", "02JE025");

        assertEquals(body, result);
        server.verify();
    }

    @Test
    void fetchThrowsFileNotFoundOn404() {
        server.expect(requestTo(URL)).andRespond(withStatus(NOT_FOUND));

        assertThrows(FileNotFoundException.class, () -> fetcher.fetch("QC", "02JE025"));
    }

    @Test
    void fetchThrowsServerErrorOnOtherNonSuccessStatus() {
        server.expect(requestTo(URL)).andRespond(withStatus(INTERNAL_SERVER_ERROR));

        assertThrows(HttpServerErrorException.class, () -> fetcher.fetch("QC", "02JE025"));
    }
}
