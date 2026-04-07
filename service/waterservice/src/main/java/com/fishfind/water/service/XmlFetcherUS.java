package com.fishfind.water.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.io.EOFException;

/**
 * Downloads WaterML payloads from USGS for one station.
 */
@Service
public class XmlFetcherUS {
    private static final Logger log = LoggerFactory.getLogger(XmlFetcherUS.class);
    private static final int MAX_ATTEMPTS = 3;

    @Value("${water.worker.connect-timeout-ms:15000}")
    private int connectTimeout;

    @Value("${water.worker.read-timeout-ms:30000}")
    private int readTimeout;

    /**
     * Fetches the USGS WaterML document for a station.
     *
     * @param state US state code kept for logging parity with the CA flow
     * @param mli station identifier
     * @return raw XML response body
     * @throws IOException when the remote file cannot be fetched successfully
     */
    public String fetch(String state, String mli) throws IOException {
        String url = "https://waterservices.usgs.gov/nwis/iv/?sites=" + mli + "&period=P3D&format=waterml";

        IOException lastException = null;
        for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
            HttpURLConnection conn = openConnection(url);
            conn.setConnectTimeout(connectTimeout);
            conn.setReadTimeout(readTimeout);
            conn.setRequestProperty("User-Agent", "Mozilla/5.0");

            try {
                log.debug("Fetching USGS WaterML. station={} state={} url={} attempt={}", mli, state, url, attempt);

                if (conn.getResponseCode() != 200) {
                    throw new IOException("HTTP error " + conn.getResponseCode());
                }

                try (InputStream inputStream = conn.getInputStream()) {
                    String xml = new String(inputStream.readAllBytes(), StandardCharsets.UTF_8);
                    log.debug("Fetched USGS WaterML. station={} state={} attempt={}", mli, state, attempt);
                    return xml;
                }
            } catch (IOException ex) {
                lastException = ex;
                if (!isRetryable(ex) || attempt == MAX_ATTEMPTS) {
                    throw ex;
                }

                log.warn("Retrying USGS WaterML fetch after transient failure. station={} state={} attempt={} maxAttempts={}",
                        mli, state, attempt, MAX_ATTEMPTS, ex);
            } finally {
                conn.disconnect();
            }
        }

        throw lastException == null ? new IOException("USGS fetch failed without a captured exception") : lastException;
    }

    private boolean isRetryable(IOException ex) {
        if (ex instanceof EOFException || ex instanceof SocketTimeoutException || ex instanceof SocketException) {
            return true;
        }

        String message = ex.getMessage();
        return message != null && message.contains("Premature EOF");
    }

    /**
     * Opens an HTTP connection for the requested WaterML URL.
     *
     * @param url source URL to connect to
     * @return opened HTTP connection
     * @throws IOException when the connection cannot be created
     */
    HttpURLConnection openConnection(String url) throws IOException {
        return (HttpURLConnection) new URL(url).openConnection();
    }
}
