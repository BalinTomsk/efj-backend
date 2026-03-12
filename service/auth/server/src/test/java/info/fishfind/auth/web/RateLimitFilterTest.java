package info.fishfind.auth.web;

import info.fishfind.auth.config.AppProperties;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import jakarta.servlet.FilterChain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;

class RateLimitFilterTest {

    @Test
    void doFilterInternalAllowsRequestsUpToConfiguredLimit() throws Exception {
        RateLimitFilter filter = new RateLimitFilter(appProperties(2, 1));
        FilterChain filterChain = mock(FilterChain.class);

        MockHttpServletRequest firstRequest = request("127.0.0.1");
        MockHttpServletResponse firstResponse = new MockHttpServletResponse();
        filter.doFilterInternal(firstRequest, firstResponse, filterChain);

        MockHttpServletRequest secondRequest = request("127.0.0.1");
        MockHttpServletResponse secondResponse = new MockHttpServletResponse();
        filter.doFilterInternal(secondRequest, secondResponse, filterChain);

        verify(filterChain).doFilter(firstRequest, firstResponse);
        verify(filterChain).doFilter(secondRequest, secondResponse);
        assertThat(firstResponse.getStatus()).isEqualTo(200);
        assertThat(secondResponse.getStatus()).isEqualTo(200);
    }

    @Test
    void doFilterInternalRejectsRequestsAboveConfiguredLimitForSameClient() throws Exception {
        RateLimitFilter filter = new RateLimitFilter(appProperties(1, 1));
        FilterChain filterChain = mock(FilterChain.class);

        MockHttpServletRequest firstRequest = request("127.0.0.1");
        MockHttpServletResponse firstResponse = new MockHttpServletResponse();
        filter.doFilterInternal(firstRequest, firstResponse, filterChain);

        MockHttpServletRequest secondRequest = request("127.0.0.1");
        MockHttpServletResponse secondResponse = new MockHttpServletResponse();
        filter.doFilterInternal(secondRequest, secondResponse, filterChain);

        verify(filterChain).doFilter(firstRequest, firstResponse);
        verifyNoMoreInteractions(filterChain);
        assertThat(secondResponse.getStatus()).isEqualTo(429);
        assertThat(secondResponse.getContentType()).isEqualTo("application/json");
        assertThat(secondResponse.getContentAsString()).isEqualTo("{\"error\":\"Too many requests\"}");
    }

    @Test
    void doFilterInternalUsesUnknownKeyWhenRemoteAddressIsNull() throws Exception {
        RateLimitFilter filter = new RateLimitFilter(appProperties(1, 1));
        FilterChain filterChain = mock(FilterChain.class);

        MockHttpServletRequest firstRequest = new MockHttpServletRequest();
        MockHttpServletResponse firstResponse = new MockHttpServletResponse();
        filter.doFilterInternal(firstRequest, firstResponse, filterChain);

        MockHttpServletRequest secondRequest = new MockHttpServletRequest();
        MockHttpServletResponse secondResponse = new MockHttpServletResponse();
        filter.doFilterInternal(secondRequest, secondResponse, filterChain);

        verify(filterChain).doFilter(firstRequest, firstResponse);
        verifyNoMoreInteractions(filterChain);
        assertThat(secondResponse.getStatus()).isEqualTo(429);
    }

    private static MockHttpServletRequest request(String remoteAddress) {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setRemoteAddr(remoteAddress);
        return request;
    }

    private static AppProperties appProperties(int maxRequests, long windowMinutes) {
        return new AppProperties(
                "https://fishfind.example",
                new AppProperties.Jwt("MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=", 4),
                new AppProperties.Mail("noreply@example.com"),
                new AppProperties.RateLimit(maxRequests, windowMinutes)
        );
    }
}
