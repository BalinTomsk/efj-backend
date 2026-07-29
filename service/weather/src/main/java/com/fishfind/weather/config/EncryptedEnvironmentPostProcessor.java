package com.fishfind.weather.config;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.env.EnvironmentPostProcessor;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.StandardEnvironment;

import java.util.HashMap;
import java.util.Map;

/**
 * Replaces any {@code enc:v1:} values sitting in the real process environment with their plaintext.
 *
 * <p>The dotenv half of the same job is done in
 * {@link com.fishfind.weather.WeatherStationPusherApplication}, which loads credentials as Spring
 * <em>default</em> properties. Default properties sit at the very bottom of the precedence order and
 * therefore cannot override a real environment variable, so an encrypted variable arriving through
 * Docker's {@code --env-file} needs this higher-precedence source instead.
 *
 * <p>The decrypted values are added directly <em>before</em> the {@code systemEnvironment} source
 * rather than with {@code addFirst}, so command-line arguments and any test override still take
 * precedence. Nothing is added when no environment variable is encrypted, keeping this a complete
 * no-op for the existing all-plaintext deployments.
 */
public class EncryptedEnvironmentPostProcessor implements EnvironmentPostProcessor {

    private static final String PROPERTY_SOURCE_NAME = "decryptedEnvironmentProperties";

    /**
     * Scans the process environment and, when it holds encrypted values, adds their plaintext as a
     * property source ranked just above {@code systemEnvironment}.
     *
     * @param environment the application environment to augment
     * @param application the Spring application being started
     */
    @Override
    public void postProcessEnvironment(ConfigurableEnvironment environment, SpringApplication application) {
        Map<String, Object> decrypted = new HashMap<>();

        for (Map.Entry<String, Object> entry : environment.getSystemEnvironment().entrySet()) {
            if (entry.getValue() instanceof String value && SecretCodec.isEncrypted(value)) {
                decrypted.put(entry.getKey(), SecretCodec.decryptIfNeeded(entry.getKey(), value));
            }
        }

        if (decrypted.isEmpty()) {
            return;
        }

        MapPropertySource source = new MapPropertySource(PROPERTY_SOURCE_NAME, decrypted);
        if (environment.getPropertySources().contains(StandardEnvironment.SYSTEM_ENVIRONMENT_PROPERTY_SOURCE_NAME)) {
            environment.getPropertySources()
                    .addBefore(StandardEnvironment.SYSTEM_ENVIRONMENT_PROPERTY_SOURCE_NAME, source);
        } else {
            environment.getPropertySources().addFirst(source);
        }
    }
}
