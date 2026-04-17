package com.fishfind.weather.service;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Fetches raw forecast JSON from the Open-Meteo API.
 */
@Service
public class OpenMeteoFetcher {
    private static final Logger log = LoggerFactory.getLogger(OpenMeteoFetcher.class);
    private static final String USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";

    @Value("${weather.worker.connect-timeout-ms:15000}")
    private int connectTimeoutMs;

    @Value("${weather.worker.read-timeout-ms:30000}")
    private int readTimeoutMs;

    public String fetch(double latitude, double longitude) throws IOException {
        String url = buildUrl(latitude, longitude);
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setRequestMethod("GET");
        connection.setConnectTimeout(connectTimeoutMs);
        connection.setReadTimeout(readTimeoutMs);
        connection.setRequestProperty("User-Agent", USER_AGENT);

        int status = connection.getResponseCode();
        if (status == HttpURLConnection.HTTP_NOT_FOUND) {
            throw new FileNotFoundException("Open-Meteo feed not published for URL " + url);
        }
        if (status != HttpURLConnection.HTTP_OK) {
            throw new IOException("Open-Meteo returned HTTP " + status + " for URL " + url);
        }

        try (InputStream inputStream = connection.getInputStream()) {
            String json = new String(inputStream.readAllBytes(), StandardCharsets.UTF_8)
                    .replace("\\\"", "\"");
            log.info("Open-Meteo fetch succeeded. latitude={} longitude={}", latitude, longitude);
            return json;
        } finally {
            connection.disconnect();
        }
    }

    private String buildUrl(double latitude, double longitude) {
        return "https://api.open-meteo.com/v1/forecast?latitude=" + latitude
                + "&longitude=" + longitude
                + "&hourly=temperature_2m,relative_humidity_2m,precipitation_probability,pressure_msl,"
                + "wind_speed_10m,wind_direction_10m,weather_code,rain"
                + "&daily=temperature_2m_max,temperature_2m_min&timezone=auto";
    }
}
