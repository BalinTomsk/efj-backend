package com.fishfind.water;

import io.github.cdimascio.dotenv.Dotenv;
import java.nio.file.Path;
import java.nio.file.Files;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Bootstraps the water station worker application and loads database credentials
 * from the process environment or a dotenv file before Spring starts.
 */
@SpringBootApplication
public class WaterStationPusherApplication {
    private static final String DEFAULT_DOTENV_FILE = ".env";
    private static final String DOTENV_PATH_ENV = "DOTENV_PATH";

    /**
     * Starts the Spring Boot application after populating missing DB properties.
     *
     * @param args command-line arguments passed to the application
     */
    public static void main(String[] args) {
        loadDotenvCredentials();
        SpringApplication.run(WaterStationPusherApplication.class, args);
    }

    /**
     * Copies supported DB settings from dotenv into system properties when they are absent.
     */
    private static void loadDotenvCredentials() {
        Dotenv dotenv = loadDotenv();

        applyIfMissing(dotenv, "DB_URL");
        applyIfMissing(dotenv, "DB_USERNAME");
        applyIfMissing(dotenv, "DB_PASSWORD");
    }

    /**
     * Loads dotenv configuration from a custom path or the working directory when available.
     *
     * @return the loaded dotenv instance
     */
    private static Dotenv loadDotenv() {
        Path configuredPath = resolveDotenvPath();
        if (configuredPath != null && Files.exists(configuredPath)) {
            Path parent = configuredPath.toAbsolutePath().getParent();
            String directory = parent == null ? "." : parent.toString();
            return Dotenv.configure()
                    .directory(directory)
                    .filename(configuredPath.getFileName().toString())
                    .ignoreIfMalformed()
                    .ignoreIfMissing()
                    .load();
        }

        return Dotenv.configure()
                .ignoreIfMalformed()
                .ignoreIfMissing()
                .load();
    }

    /**
     * Resolves the dotenv file to use, preferring {@code DOTENV_PATH} over the default project file.
     *
     * @return the configured dotenv path, or {@code null} when no file is available
     */
    private static Path resolveDotenvPath() {
        String configuredPath = System.getenv(DOTENV_PATH_ENV);
        if (configuredPath != null && !configuredPath.isBlank()) {
            return Path.of(configuredPath.trim());
        }

        Path workingDirectoryDotenv = Path.of(DEFAULT_DOTENV_FILE);
        if (Files.exists(workingDirectoryDotenv)) {
            return workingDirectoryDotenv;
        }

        return null;
    }

    /**
     * Applies a dotenv value to system properties only when the key is not already configured.
     *
     * @param dotenv loaded dotenv source
     * @param key configuration key to copy
     */
    private static void applyIfMissing(Dotenv dotenv, String key) {
        if (System.getenv(key) != null || System.getProperty(key) != null) {
            return;
        }

        String value = dotenv.get(key);
        if (value != null && !value.isBlank()) {
            System.setProperty(key, value);
        }
    }
}
