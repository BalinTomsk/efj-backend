package com.fishfind.water.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.net.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

@Service
public class CsvFetcher {

    @Value("${water.worker.connect-timeout-ms:15000}")
    private int connectTimeout;

    @Value("${water.worker.read-timeout-ms:30000}")
    private int readTimeout;

    public List<String[]> fetch(String state, String mli) throws Exception {

        String url = String.format(
            "https://dd.weather.gc.ca/today/hydrometric/csv/%s/hourly/%s_%s_hourly_hydrometric.csv",
            state, state, mli);

        HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
        conn.setConnectTimeout(connectTimeout);
        conn.setReadTimeout(readTimeout);
        conn.setRequestProperty("User-Agent", "Mozilla/5.0");

        if (conn.getResponseCode() != 200) {
            throw new RuntimeException("HTTP error " + conn.getResponseCode());
        }

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
}
