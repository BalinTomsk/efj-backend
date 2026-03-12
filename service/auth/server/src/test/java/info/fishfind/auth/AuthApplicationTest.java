package info.fishfind.auth;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.MockedStatic;
import org.springframework.boot.SpringApplication;

import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mockStatic;

class AuthApplicationTest {

    private static final String TEST_PROPERTY = "AUTH_APP_TEST_VALUE";
    private static final String USER_DIR = "user.dir";
    private final String originalUserDir = System.getProperty(USER_DIR);

    @AfterEach
    void tearDown() {
        System.clearProperty(TEST_PROPERTY);
        if (originalUserDir != null) {
            System.setProperty(USER_DIR, originalUserDir);
        } else {
            System.clearProperty(USER_DIR);
        }
    }

    @Test
    void tryLoadSetsSystemPropertyFromDotEnv(@TempDir Path tempDir) throws Exception {
        Files.writeString(tempDir.resolve(".env"), TEST_PROPERTY + "=loaded-value");

        invokeTryLoad(tempDir);

        assertThat(System.getProperty(TEST_PROPERTY)).isEqualTo("loaded-value");
    }

    @Test
    void tryLoadDoesNotOverrideExistingSystemProperty(@TempDir Path tempDir) throws Exception {
        Files.writeString(tempDir.resolve(".env"), TEST_PROPERTY + "=loaded-value");
        System.setProperty(TEST_PROPERTY, "existing-value");

        invokeTryLoad(tempDir);

        assertThat(System.getProperty(TEST_PROPERTY)).isEqualTo("existing-value");
    }

    @Test
    void tryLoadDoesNothingWhenDotEnvFileIsMissing(@TempDir Path tempDir) throws Exception {
        invokeTryLoad(tempDir);

        assertThat(System.getProperty(TEST_PROPERTY)).isNull();
    }

    @Test
    void mainInvokesSpringApplicationRun() {
        String[] args = new String[]{"--spring.profiles.active=test"};

        try (MockedStatic<SpringApplication> springApplication = mockStatic(SpringApplication.class)) {
            AuthApplication.main(args);

            springApplication.verify(() -> SpringApplication.run(AuthApplication.class, args));
        }
    }

    private static void invokeLoadDotEnv() throws Exception {
        Method method = AuthApplication.class.getDeclaredMethod("loadDotEnv");
        method.setAccessible(true);
        method.invoke(null);
    }

    private static void invokeTryLoad(Path dir) throws Exception {
        Method method = AuthApplication.class.getDeclaredMethod("tryLoad", Path.class);
        method.setAccessible(true);
        method.invoke(null, dir);
    }
}
