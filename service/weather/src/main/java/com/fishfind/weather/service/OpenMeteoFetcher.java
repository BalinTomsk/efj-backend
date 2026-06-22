package com.fishfind.weather.service;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.Locale;
import java.util.Random;
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
    // Chrome-like User-Agent. The two "537.NN" WebKit/Safari build numbers are randomised
    // daily (see currentUserAgent); %d placeholders are filled per calendar day.
    private static final String USER_AGENT_TEMPLATE =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.%d "
                    + "(KHTML, like Gecko) Chrome/124.0 Safari/537.%d";
    private static final int BUILD_MIN = 11;
    private static final int BUILD_MAX = 97;

    @Value("${weather.worker.connect-timeout-ms:15000}")
    private int connectTimeoutMs;

    @Value("${weather.worker.read-timeout-ms:30000}")
    private int readTimeoutMs;

    @Value("${weather.worker.open-meteo-base-url:https://api.open-meteo.com/v1/forecast}")
    private String baseUrl;

    public String fetch(double latitude, double longitude) throws IOException {
        String url = buildUrl(latitude, longitude);
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setRequestMethod("GET");
        connection.setConnectTimeout(connectTimeoutMs);
        connection.setReadTimeout(readTimeoutMs);
        connection.setRequestProperty("User-Agent", currentUserAgent());

        int status = connection.getResponseCode();
        if (status == HttpURLConnection.HTTP_NOT_FOUND) {
            throw new FileNotFoundException("Open-Meteo feed not published for URL " + url);
        }
        if (status != HttpURLConnection.HTTP_OK) {
            throw new IOException("Open-Meteo returned HTTP " + status + " for URL " + url);
        }

        try (InputStream inputStream = connection.getInputStream()) {
            // Store the response body verbatim — the payload must be persisted raw, as-is.
            String json = new String(inputStream.readAllBytes(), StandardCharsets.UTF_8);
            log.info("Open-Meteo fetch succeeded. latitude={} longitude={}", latitude, longitude);
            return json;
        } finally {
            connection.disconnect();
        }
    }

    /** User-Agent for today, with WebKit/Safari build numbers randomised in [11, 97]. */
    static String currentUserAgent() {
        return currentUserAgent(LocalDate.now());
    }

    /**
     * Builds the User-Agent for the given day. The two "537.NN" build numbers are seeded by
     * the calendar day, so they stay stable for a whole day and change from one day to the next.
     */
    static String currentUserAgent(LocalDate date) {
        Random random = new Random(date.toEpochDay());
        int webKitBuild = random.nextInt(BUILD_MIN, BUILD_MAX + 1);
        int safariBuild = random.nextInt(BUILD_MIN, BUILD_MAX + 1);
        return String.format(Locale.ROOT, USER_AGENT_TEMPLATE, webKitBuild, safariBuild);
    }

    private String buildUrl(double latitude, double longitude) {
        return baseUrl + "?latitude=" + latitude
                + "&longitude=" + longitude
                + "&hourly=temperature_2m,relative_humidity_2m,precipitation_probability,pressure_msl,"
                + "wind_speed_10m,wind_direction_10m,weather_code,rain"
                + "&daily=temperature_2m_max,temperature_2m_min&timezone=auto";
    }
}
