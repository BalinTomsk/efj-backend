package com.fishfind.water.service;

import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

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
        // Template variables are strictly URL-encoded by RestClient, so DB values cannot inject query params.
        String urlTemplate = "https://waterservices.usgs.gov/nwis/iv/?sites={mli}&period=P3D&format=waterml";

        log.debug("Fetching USGS WaterML. station={} state={}", mli, state);

        try {
            String body = restClient.get().uri(urlTemplate, mli).retrieve().body(String.class);
            log.debug("Fetched USGS WaterML. station={} state={}", mli, state);
            return body == null ? "" : body;
        } catch (HttpClientErrorException.NotFound ex) {
            throw new FileNotFoundException(
                    "HTTP 404: WaterML not published for US station " + mli + " (state " + state + ")");
        } catch (RestClientException ex) {
            IOException ioCause = findCause(ex, IOException.class);
            if (ioCause != null) {
                throw new ResourceAccessException(
                        "I/O error while reading USGS WaterML response for station " + mli
                                + " (state " + state + ")",
                        ioCause);
            }
            throw ex;
        }
    }

    private static <T extends Throwable> T findCause(Throwable throwable, Class<T> type) {
        Throwable current = throwable;
        while (current != null) {
            if (type.isInstance(current)) {
                return type.cast(current);
            }
            current = current.getCause();
        }
        return null;
    }
}
