package com.fishfind.water.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.net.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/**
 * Downloads hourly hydrometric CSV files from Environment Canada.
 */
@Service
public class CsvFetcherCA {
    private static final Logger log = LoggerFactory.getLogger(CsvFetcherCA.class);

    @Value("${water.worker.connect-timeout-ms:15000}")
    private int connectTimeout;

    @Value("${water.worker.read-timeout-ms:30000}")
    private int readTimeout;

    /**
     * Fetches the raw CSV rows for a station.
     *
     * @param state Canadian province code used in the source URL
     * @param mli station identifier
     * @return CSV rows split by comma
     * @throws Exception when the remote file cannot be fetched successfully
     */
    public List<String[]> fetch(String state, String mli) throws Exception {
        String url = String.format(
            "https://dd.weather.gc.ca/today/hydrometric/csv/%s/hourly/%s_%s_hourly_hydrometric.csv",
            state, state, mli);

        log.debug("Fetching hydrometric CSV. station={} state={} url={}", mli, state, url);

        HttpURLConnection conn = openConnection(url);
        conn.setConnectTimeout(connectTimeout);
        conn.setReadTimeout(readTimeout);
        conn.setRequestProperty("User-Agent", "Mozilla/5.0");

        int responseCode = conn.getResponseCode();
        if (responseCode == HttpURLConnection.HTTP_NOT_FOUND) {
            throw new FileNotFoundException("HTTP error " + responseCode);
        }
        if (responseCode != HttpURLConnection.HTTP_OK) {
            throw new IOException("HTTP error " + responseCode);
        }
        log.debug("Fetched station CSV. station={} state={}", mli, state);

        try (BufferedReader br = new BufferedReader(
                new InputStreamReader(conn.getInputStream(), StandardCharsets.UTF_8))) {

            List<String[]> list = new ArrayList<>();
            String line;
            while ((line = br.readLine()) != null) {
                list.add(line.split(","));
            }
            return list;
        }
    }

    /**
     * Opens an HTTP connection for the requested CSV URL.
     *
     * @param url source URL to connect to
     * @return opened HTTP connection
     * @throws IOException when the connection cannot be created
     */
    HttpURLConnection openConnection(String url) throws IOException {
        return (HttpURLConnection) new URL(url).openConnection();
    }
}
