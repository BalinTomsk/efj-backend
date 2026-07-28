package com.fishfind.docapi;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Bootstraps the DocApi REST service.
 *
 * <p>DocApi exposes JSON-document CRUD endpoints for four entities — news, waterbody, fish and
 * station — each backed by that entity's own SQL Server stored procedures (add / update) and JSON
 * function (return). It mirrors the {@code waterservice} conventions: dotenv-backed local
 * credentials, JDBC access to legacy procedures, Resilience4j around SQL, and an Actuator surface on
 * a private management port.
 *
 * <p>Database credentials are resolved by Spring from the process environment ({@code DB_URL},
 * {@code DB_USERNAME}, {@code DB_PASSWORD}). For local development a {@code .env} file is loaded by
 * {@link com.fishfind.docapi.config.DotenvEnvironmentPostProcessor} as a low-precedence property
 * source, so real environment variables and JVM system properties always win and secrets are never
 * copied into JVM-global system properties.
 */
@SpringBootApplication
public class DocApiApplication {

    /**
     * Starts the Spring Boot application.
     *
     * @param args command-line arguments passed to the application
     */
    public static void main(String[] args) {
        SpringApplication.run(DocApiApplication.class, args);
    }
}
