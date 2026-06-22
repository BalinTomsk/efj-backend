package com.fishfind.water.service;

import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

import java.io.FileNotFoundException;
import java.io.IOException;

/**
 * Downloads WaterML payloads from USGS for one station.
 *
 * <p>Transient failures (network errors such as premature EOF / socket timeouts, and 5xx) are retried via
 * {@code httpRetry}; sustained failures of the USGS feed open the {@code usFeed} circuit breaker. The
 * previous hand-rolled retry loop is replaced by this declarative configuration. A 404 means the feed is not
 * published for that station and is surfaced as {@link FileNotFoundException}.
 */
@Service
public class XmlFetcherUS {
    private static final Logger log = LoggerFactory.getLogger(XmlFetcherUS.class);

    private final RestClient restClient;

    public XmlFetcherUS(RestClient waterSourceRestClient) {
        this.restClient = waterSourceRestClient;
    }

    /**
     * Fetches the USGS WaterML document for a station.
     *
     * @param state US state code kept for logging parity with the CA flow
     * @param mli station identifier
     * @return raw XML response body
     * @throws FileNotFoundException when the source feed is not published (HTTP 404)
     * @throws IOException when the remote file cannot be fetched successfully
     */
    @Retry(name = "httpRetry")
    @CircuitBreaker(name = "usFeed")
    public String fetch(String state, String mli) throws IOException {
        String url = "https://waterservices.usgs.gov/nwis/iv/?sites=" + mli + "&period=P3D&format=waterml";

        log.debug("Fetching USGS WaterML. station={} state={} url={}", mli, state, url);

        try {
            String body = restClient.get().uri(url).retrieve().body(String.class);
            log.debug("Fetched USGS WaterML. station={} state={}", mli, state);
            return body == null ? "" : body;
        } catch (HttpClientErrorException.NotFound ex) {
            throw new FileNotFoundException("HTTP error 404");
        }
    }
}
