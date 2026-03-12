package info.fishfind.auth.client.config;

import info.fishfind.auth.client.AuthClient;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestClient;

@Configuration
@EnableConfigurationProperties(AuthClientProperties.class)
public class AuthClientConfig {

    /**
     * Builds the shared REST client targeting the auth service base URL.
     *
     * @param properties client properties containing the base URL
     * @param builder Spring REST client builder
     * @return configured REST client
     */
    @Bean
    public RestClient authRestClient(AuthClientProperties properties, RestClient.Builder builder) {
        return builder.baseUrl(properties.baseUrl()).build();
    }

    /**
     * Exposes the typed auth client bean.
     *
     * @param authRestClient REST client configured for the auth service
     * @return auth client wrapper
     */
    @Bean
    public AuthClient authClient(RestClient authRestClient) {
        return new AuthClient(authRestClient);
    }
}
