package com.fishfind.water.config;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.SpringApplication;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.StandardEnvironment;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class DotenvEnvironmentPostProcessorTest {

    private static final Path DOTENV_PATH = Path.of(".env");
    private static final String SOURCE_NAME = "dotenvProperties";

    private final DotenvEnvironmentPostProcessor processor = new DotenvEnvironmentPostProcessor();

    @AfterEach
    void cleanup() throws Exception {
        Files.deleteIfExists(DOTENV_PATH);
    }

    @Test
    void exposesDotenvValuesAsProperties() throws Exception {
        Files.writeString(DOTENV_PATH, "DB_URL=jdbc:test\nDB_USERNAME=test-user\nDB_PASSWORD=test-pass\n");
        StandardEnvironment environment = new StandardEnvironment();

        processor.postProcessEnvironment(environment, new SpringApplication());

        assertTrue(environment.getPropertySources().contains(SOURCE_NAME));
        assertEquals("jdbc:test", environment.getProperty("DB_URL"));
        assertEquals("test-user", environment.getProperty("DB_USERNAME"));
    }

    @Test
    void doesNotCopySecretsIntoSystemProperties() throws Exception {
        Files.writeString(DOTENV_PATH, "DB_PASSWORD=top-secret\n");
        StandardEnvironment environment = new StandardEnvironment();

        processor.postProcessEnvironment(environment, new SpringApplication());

        // The whole point of the change: credentials must never leak into JVM-global system properties.
        assertEquals(null, System.getProperty("DB_PASSWORD"));
    }

    @Test
    void higherPrecedenceSourcesWinOverDotenv() throws Exception {
        Files.writeString(DOTENV_PATH, "DB_URL=jdbc:from-file\n");
        StandardEnvironment environment = new StandardEnvironment();
        environment.getPropertySources().addFirst(
                new MapPropertySource("override", Map.of("DB_URL", "jdbc:from-env")));

        processor.postProcessEnvironment(environment, new SpringApplication());

        assertEquals("jdbc:from-env", environment.getProperty("DB_URL"));
    }

    @Test
    void addsNoPropertySourceWhenNoDotenvFilePresent() {
        StandardEnvironment environment = new StandardEnvironment();

        processor.postProcessEnvironment(environment, new SpringApplication());

        assertFalse(environment.getPropertySources().contains(SOURCE_NAME));
    }

    @Test
    void addsNoPropertySourceWhenDotenvPathIsDirectory() throws Exception {
        Files.createDirectory(DOTENV_PATH);
        StandardEnvironment environment = new StandardEnvironment();

        assertDoesNotThrow(() -> processor.postProcessEnvironment(environment, new SpringApplication()));

        assertFalse(environment.getPropertySources().contains(SOURCE_NAME));
    }
}
