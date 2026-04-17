package com.fishfind.weather;

import io.github.cdimascio.dotenv.Dotenv;
import java.nio.file.Files;
import java.nio.file.Path;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Bootstraps the weather worker application and loads database credentials
 * from the process environment or a dotenv file before Spring starts.
 */
@SpringBootApplication
public class WeatherStationPusherApplication {
    private static final String DEFAULT_DOTENV_FILE = ".env";
    private static final String DOTENV_PATH_ENV = "DOTENV_PATH";

    public static void main(String[] args) {
        loadDotenvCredentials();
        SpringApplication.run(WeatherStationPusherApplication.class, args);
    }

    private static void loadDotenvCredentials() {
        Dotenv dotenv = loadDotenv();

        applyIfMissing(dotenv, "DB_URL");
        applyIfMissing(dotenv, "DB_USERNAME");
        applyIfMissing(dotenv, "DB_PASSWORD");
    }

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
