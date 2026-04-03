package com.fishfind.water;

import io.github.cdimascio.dotenv.Dotenv;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import org.springframework.boot.SpringApplication;

import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WaterStationPusherApplicationTest {
    private static final Path DOTENV_PATH = Path.of(".env");

    @AfterEach
    void cleanup() throws Exception {
        Files.deleteIfExists(DOTENV_PATH);
        System.clearProperty("DB_URL");
        System.clearProperty("DB_USERNAME");
        System.clearProperty("DB_PASSWORD");
        System.clearProperty("TEST_KEY");
    }

    @Test
    void mainStartsSpringApplication() {
        try (MockedStatic<SpringApplication> springApplication = mockStatic(SpringApplication.class)) {
            springApplication.when(() -> SpringApplication.run(eq(WaterStationPusherApplication.class), eq(new String[]{"--console"})))
                    .thenReturn(mock(org.springframework.context.ConfigurableApplicationContext.class));

            WaterStationPusherApplication.main(new String[]{"--console"});

            springApplication.verify(
                    () -> SpringApplication.run(eq(WaterStationPusherApplication.class), eq(new String[]{"--console"})),
                    times(1)
            );
        }
    }

    @Test
    void loadDotenvReadsWorkingDirectoryFile() throws Exception {
        Files.writeString(DOTENV_PATH, "DB_URL=jdbc:test\nDB_USERNAME=test-user\nDB_PASSWORD=test-pass\n");

        Dotenv dotenv = (Dotenv) invokeStatic("loadDotenv");

        assertNotNull(dotenv.get("DB_URL"));
        assertEquals("jdbc:test", dotenv.get("DB_URL"));
    }

    @Test
    void resolveDotenvPathReturnsWorkingDirectoryDotenv() throws Exception {
        Files.writeString(DOTENV_PATH, "DB_URL=jdbc:test\n");

        Path resolved = (Path) invokeStatic("resolveDotenvPath");

        assertEquals(Path.of(".env"), resolved);
    }

    @Test
    void applyIfMissingSetsPropertyFromDotenv() throws Exception {
        Dotenv dotenv = mock(Dotenv.class);
        when(dotenv.get("TEST_KEY")).thenReturn("test-value");

        invokeStatic("applyIfMissing", new Class<?>[]{Dotenv.class, String.class}, dotenv, "TEST_KEY");

        assertEquals("test-value", System.getProperty("TEST_KEY"));
    }

    @Test
    void applyIfMissingKeepsExistingSystemProperty() throws Exception {
        Dotenv dotenv = mock(Dotenv.class);
        when(dotenv.get(any())).thenReturn("jdbc:ignored");
        System.setProperty("TEST_KEY", "existing");

        invokeStatic("applyIfMissing", new Class<?>[]{Dotenv.class, String.class}, dotenv, "TEST_KEY");

        assertEquals("existing", System.getProperty("TEST_KEY"));
    }

    @Test
    void loadDotenvCredentialsCopiesKnownKeysWhenTheyAreUnset() throws Exception {
        Files.writeString(DOTENV_PATH, "DB_URL=jdbc:test\nDB_USERNAME=test-user\nDB_PASSWORD=test-pass\n");
        Dotenv dotenv = Dotenv.configure().ignoreIfMalformed().ignoreIfMissing().load();

        invokeStatic("loadDotenvCredentials");

        assertExpectedProperty("DB_URL", dotenv);
        assertExpectedProperty("DB_USERNAME", dotenv);
        assertExpectedProperty("DB_PASSWORD", dotenv);
    }

    private static void assertExpectedProperty(String key, Dotenv dotenv) {
        if (System.getenv(key) == null) {
            assertEquals(dotenv.get(key), System.getProperty(key));
        } else {
            assertNull(System.getProperty(key));
        }
    }

    private static Object invokeStatic(String name, Class<?>[] parameterTypes, Object... args) throws Exception {
        Method method = WaterStationPusherApplication.class.getDeclaredMethod(name, parameterTypes);
        method.setAccessible(true);
        return method.invoke(null, args);
    }

    private static Object invokeStatic(String name) throws Exception {
        return invokeStatic(name, new Class<?>[0]);
    }
}
