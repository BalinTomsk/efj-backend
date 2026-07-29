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
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

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

    @Test
    void failsFastWhenAValueIsEncryptedButNoMasterKeyIsConfigured() throws Exception {
        // Only meaningful when this JVM has no key configured; skip rather than fail on a machine
        // that legitimately has one exported.
        assumeTrue(System.getenv("FF_MASTER_KEY_FILE") == null && System.getenv("FF_MASTER_KEY") == null,
                "a master key is configured in this environment");

        Files.writeString(DOTENV_PATH, "DB_PASSWORD=enc:v1:6tiG1Z4iC24LMP6h7LN5x9s_OraeqDKDny_lHf9rAm94XKFNbu3pSaqv9A\n");
        StandardEnvironment environment = new StandardEnvironment();

        // Startup must break loudly. Passing the raw enc:v1: string through to the JDBC driver would
        // surface as an unrelated-looking SQL login failure.
        IllegalStateException thrown = assertThrows(IllegalStateException.class,
                () -> processor.postProcessEnvironment(environment, new SpringApplication()));

        assertTrue(thrown.getMessage().contains("DB_PASSWORD"));
        assertTrue(thrown.getMessage().contains("FF_MASTER_KEY_FILE"));
    }

    @Test
    void leavesAPlaintextDotenvCompletelyUnaffected() throws Exception {
        // The rollout depends on this: decrypt-capable images ship first and must run against the
        // existing all-plaintext .env with no key present at all.
        assumeTrue(System.getenv("FF_MASTER_KEY_FILE") == null && System.getenv("FF_MASTER_KEY") == null,
                "a master key is configured in this environment");

        Files.writeString(DOTENV_PATH, "DB_URL=jdbc:plain\nDB_USERNAME=user\nDB_PASSWORD=pass\n");
        StandardEnvironment environment = new StandardEnvironment();

        assertDoesNotThrow(() -> processor.postProcessEnvironment(environment, new SpringApplication()));

        assertEquals("jdbc:plain", environment.getProperty("DB_URL"));
        assertEquals("pass", environment.getProperty("DB_PASSWORD"));
    }
}
