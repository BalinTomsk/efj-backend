package com.fishfind.water.service;

import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.HttpClientErrorException;

import java.io.FileNotFoundException;
import java.io.IOException;

/**
 * Downloads hourly hydrometric CSV files from Environment Canada.
 *
 * <p>Transient failures (network errors, 5xx) are retried via {@code httpRetry}; sustained failures of the
 * Environment Canada feed open the {@code caFeed} circuit breaker. A 404 means the feed is simply not
 * published for that station and is surfaced as {@link FileNotFoundException} (neither retried nor counted
 * against the breaker).
 */
@Service
public class CsvFetcherCA {
    private static final Logger log = LoggerFactory.getLogger(CsvFetcherCA.class);

    private final RestClient restClient;

    public CsvFetcherCA(RestClient waterSourceRestClient) {
        this.restClient = waterSourceRestClient;
    }

    /**
     * Fetches the raw CSV body for a station.
     *
     * @param state Canadian province code used in the source URL
     * @param mli station identifier
     * @return raw CSV document body
     * @throws FileNotFoundException when the source feed is not published (HTTP 404)
     * @throws IOException when the remote file cannot be fetched successfully
     */
    @Retry(name = "httpRetry")
    @CircuitBreaker(name = "caFeed")
    public String fetch(String state, String mli) throws IOException {
        String url = String.format(
                "https://dd.weather.gc.ca/today/hydrometric/csv/%s/hourly/%s_%s_hourly_hydrometric.csv",
                state, state, mli);

        log.debug("Fetching hydrometric CSV. station={} state={} url={}", mli, state, url);

        try {
            String body = restClient.get().uri(url).retrieve().body(String.class);
            log.debug("Fetched station CSV. station={} state={}", mli, state);
            return body == null ? "" : body;
        } catch (HttpClientErrorException.NotFound ex) {
            throw new FileNotFoundException("HTTP error 404");
        }
    }
}
