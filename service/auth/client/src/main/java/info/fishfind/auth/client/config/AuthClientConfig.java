package info.fishfind.auth.client.config;

import info.fishfind.auth.client.AuthClient;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestClient;

@Configuration
@EnableConfigurationProperties(AuthClientProperties.class)
public class AuthClientConfig {

    @Bean
    public RestClient authRestClient(AuthClientProperties properties, RestClient.Builder builder) {
        return builder.baseUrl(properties.baseUrl()).build();
    }

    @Bean
    public AuthClient authClient(RestClient authRestClient) {
        return new AuthClient(authRestClient);
    }
}
