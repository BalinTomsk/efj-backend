package com.fishfind.water;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Bootstraps the water station worker application.
 *
 * <p>Database credentials are resolved by Spring from the process environment (e.g. {@code DB_URL},
 * {@code DB_USERNAME}, {@code DB_PASSWORD}). For local development a {@code .env} file is loaded by
 * {@link com.fishfind.water.config.DotenvEnvironmentPostProcessor} as a low-precedence property source,
 * so real environment variables and JVM system properties always win and secrets are never copied into
 * JVM-global system properties.
 */
@SpringBootApplication
public class WaterStationPusherApplication {

    /**
     * Starts the Spring Boot application.
     *
     * @param args command-line arguments passed to the application
     */
    public static void main(String[] args) {
        SpringApplication.run(WaterStationPusherApplication.class, args);
    }
}
