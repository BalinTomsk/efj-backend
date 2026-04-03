package com.fishfind.water.service;

import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.ByteArrayInputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.spy;

class CsvFetcherCATest {

    @Test
    void fetchReturnsSplitCsvRowsAndAppliesConnectionSettings() throws Exception {
        CsvFetcherCA fetcher = spy(new CsvFetcherCA());
        ReflectionTestUtils.setField(fetcher, "connectTimeout", 15000);
        ReflectionTestUtils.setField(fetcher, "readTimeout", 30000);
        FakeHttpURLConnection connection = new FakeHttpURLConnection(
                new URL("https://example.test/file.csv"),
                200,
                "station,stamp,level,a,b,c,discharge\n02JE025,2024-01-02T03:04:05Z,1.2,0,0,0,3.4\n"
        );
        doReturn(connection).when(fetcher).openConnection("https://dd.weather.gc.ca/today/hydrometric/csv/QC/hourly/QC_02JE025_hourly_hydrometric.csv");

        List<String[]> rows = fetcher.fetch("QC", "02JE025");

        assertEquals(2, rows.size());
        assertEquals("station", rows.get(0)[0]);
        assertEquals("02JE025", rows.get(1)[0]);
        assertEquals(15000, connection.connectTimeout);
        assertEquals(30000, connection.readTimeout);
        assertEquals("Mozilla/5.0", connection.userAgent);
    }

    @Test
    void fetchThrowsFileNotFoundOn404() throws Exception {
        CsvFetcherCA fetcher = spy(new CsvFetcherCA());
        ReflectionTestUtils.setField(fetcher, "connectTimeout", 1);
        ReflectionTestUtils.setField(fetcher, "readTimeout", 1);
        FakeHttpURLConnection connection = new FakeHttpURLConnection(new URL("https://example.test/file.csv"), 404, "");
        doReturn(connection).when(fetcher).openConnection("https://dd.weather.gc.ca/today/hydrometric/csv/QC/hourly/QC_02JE025_hourly_hydrometric.csv");

        FileNotFoundException ex = assertThrows(FileNotFoundException.class, () -> fetcher.fetch("QC", "02JE025"));

        assertEquals("HTTP error 404", ex.getMessage());
    }

    @Test
    void fetchThrowsIoExceptionOnOtherNonSuccessStatus() throws Exception {
        CsvFetcherCA fetcher = spy(new CsvFetcherCA());
        ReflectionTestUtils.setField(fetcher, "connectTimeout", 1);
        ReflectionTestUtils.setField(fetcher, "readTimeout", 1);
        FakeHttpURLConnection connection = new FakeHttpURLConnection(new URL("https://example.test/file.csv"), 500, "");
        doReturn(connection).when(fetcher).openConnection("https://dd.weather.gc.ca/today/hydrometric/csv/QC/hourly/QC_02JE025_hourly_hydrometric.csv");

        IOException ex = assertThrows(IOException.class, () -> fetcher.fetch("QC", "02JE025"));

        assertInstanceOf(IOException.class, ex);
        assertEquals("HTTP error 500", ex.getMessage());
    }

    private static final class FakeHttpURLConnection extends HttpURLConnection {
        private final int responseCode;
        private final byte[] body;
        private int connectTimeout;
        private int readTimeout;
        private String userAgent;

        private FakeHttpURLConnection(URL url, int responseCode, String body) {
            super(url);
            this.responseCode = responseCode;
            this.body = body.getBytes(StandardCharsets.UTF_8);
        }

        @Override
        public void disconnect() {
        }

        @Override
        public boolean usingProxy() {
            return false;
        }

        @Override
        public void connect() {
        }

        @Override
        public void setConnectTimeout(int timeout) {
            this.connectTimeout = timeout;
        }

        @Override
        public void setReadTimeout(int timeout) {
            this.readTimeout = timeout;
        }

        @Override
        public void setRequestProperty(String key, String value) {
            if ("User-Agent".equals(key)) {
                this.userAgent = value;
            }
        }

        @Override
        public int getResponseCode() {
            return responseCode;
        }

        @Override
        public InputStream getInputStream() throws IOException {
            return new ByteArrayInputStream(body);
        }
    }
}
