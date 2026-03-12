package info.fishfind.auth.client.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "auth.client")
public record AuthClientProperties(String baseUrl) {
}
