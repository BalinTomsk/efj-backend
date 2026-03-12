package info.fishfind.auth.config;

import info.fishfind.auth.web.RateLimitFilter;
import org.junit.jupiter.api.Test;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

class WebConfigTest {

    private final WebConfig webConfig = new WebConfig();

    @Test
    void corsConfigurationSourceRegistersExpectedRules() {
        CorsConfigurationSource source = webConfig.corsConfigurationSource();

        MockHttpServletRequest request = new MockHttpServletRequest("OPTIONS", "/auth/login");
        CorsConfiguration configuration = source.getCorsConfiguration(request);

        assertThat(configuration).isNotNull();
        assertThat(configuration.getAllowedOriginPatterns()).containsExactly("*");
        assertThat(configuration.getAllowedMethods())
                .containsExactly("GET", "POST", "PUT", "DELETE", "OPTIONS");
        assertThat(configuration.getAllowedHeaders()).containsExactly("*");
        assertThat(configuration.getAllowCredentials()).isFalse();
    }

    @Test
    void rateLimitFilterRegistrationAppliesFilterToAllPathsWithOrderOne() {
        RateLimitFilter rateLimitFilter = mock(RateLimitFilter.class);

        FilterRegistrationBean<RateLimitFilter> registration =
                webConfig.rateLimitFilterRegistration(rateLimitFilter);

        assertThat(registration.getFilter()).isSameAs(rateLimitFilter);
        assertThat(registration.getUrlPatterns()).containsExactly("/*");
        assertThat(registration.getOrder()).isEqualTo(1);
    }
}
