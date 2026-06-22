package com.fishfind.water.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpHeaders;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

import java.net.http.HttpClient;
import java.time.Duration;

/**
 * Shared HTTP client for fetching upstream water-source feeds.
 *
 * <p>Uses the JDK {@link HttpClient} (which pools/keeps-alive connections per instance) behind Spring's
 * {@link RestClient}, replacing the previous per-request {@code HttpURLConnection}. Connect and read timeouts
 * are enforced at the transport layer; resilience (retry + circuit breaker) is applied declaratively on the
 * fetcher methods.
 */
@Configuration
public class HttpClientConfig {

    /**
     * Builds the {@link RestClient} used by both the CA and US fetchers.
     *
     * @param connectTimeoutMs connection-establishment timeout
     * @param readTimeoutMs response read timeout
     * @param userAgent identifying User-Agent sent to the public government feeds
     * @return a configured, connection-pooling REST client
     */
    @Bean
    public RestClient waterSourceRestClient(
            @Value("${water.worker.connect-timeout-ms:15000}") int connectTimeoutMs,
            @Value("${water.worker.read-timeout-ms:30000}") int readTimeoutMs,
            @Value("${water.worker.user-agent:water-station-pusher/1.0.0 (+https://fishfind.info)}") String userAgent) {

        HttpClient httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofMillis(connectTimeoutMs))
                .followRedirects(HttpClient.Redirect.NORMAL)
                .build();

        JdkClientHttpRequestFactory requestFactory = new JdkClientHttpRequestFactory(httpClient);
        requestFactory.setReadTimeout(Duration.ofMillis(readTimeoutMs));

        return RestClient.builder()
                .requestFactory(requestFactory)
                .defaultHeader(HttpHeaders.USER_AGENT, userAgent)
                .build();
    }
}
