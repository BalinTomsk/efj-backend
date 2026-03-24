package com.fishfind.water.service;

import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class XmlFetcherUSTest {

    @Test
    void fetchReturnsBodyAndSetsUserAgent() throws Exception {
        FakeHttpURLConnection connection = new FakeHttpURLConnection(
                200,
                "<root>ok</root>"
        );

        XmlFetcherUS fetcher = new XmlFetcherUS() {
            @Override
            HttpURLConnection openConnection(String url) {
                assertEquals("https://waterservices.usgs.gov/nwis/iv/?sites=08313000&period=P3D&format=waterml", url);
                return connection;
            }
        };
        ReflectionTestUtils.setField(fetcher, "connectTimeout", 1234);
        ReflectionTestUtils.setField(fetcher, "readTimeout", 5678);

        String xml = fetcher.fetch("NY", "08313000");

        assertEquals("<root>ok</root>", xml);
        assertEquals("Mozilla/5.0", connection.userAgent);
        assertEquals(1234, connection.connectTimeoutValue);
        assertEquals(5678, connection.readTimeoutValue);
    }

    @Test
    void fetchThrowsOnNonSuccessStatus() {
        XmlFetcherUS fetcher = new XmlFetcherUS() {
            @Override
            HttpURLConnection openConnection(String url) {
                return new FakeHttpURLConnection(500, "bad");
            }
        };

        Exception ex = assertThrows(Exception.class, () -> fetcher.fetch("NY", "08313000"));
        assertEquals("HTTP error 500", ex.getMessage());
    }

    private static final class FakeHttpURLConnection extends HttpURLConnection {
        private final int responseCode;
        private final byte[] body;
        private String userAgent;
        private int connectTimeoutValue;
        private int readTimeoutValue;

        private FakeHttpURLConnection(int responseCode, String body) {
            super(null);
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
        public int getResponseCode() {
            return responseCode;
        }

        @Override
        public InputStream getInputStream() {
            return new ByteArrayInputStream(body);
        }

        @Override
        public void setRequestProperty(String key, String value) {
            if ("User-Agent".equals(key)) {
                this.userAgent = value;
            }
        }

        @Override
        public void setConnectTimeout(int timeout) {
            this.connectTimeoutValue = timeout;
        }

        @Override
        public void setReadTimeout(int timeout) {
            this.readTimeoutValue = timeout;
        }
    }
}
