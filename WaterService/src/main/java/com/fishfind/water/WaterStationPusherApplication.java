package com.fishfind.water;

import io.github.cdimascio.dotenv.Dotenv;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class WaterStationPusherApplication {
    private static final String DOTENV_DIRECTORY = "src/main/resources";

    public static void main(String[] args) {
        loadDotenvCredentials();
        SpringApplication.run(WaterStationPusherApplication.class, args);
    }

    private static void loadDotenvCredentials() {
        Dotenv dotenv = loadDotenv();

        applyIfMissing(dotenv, "DB_URL");
        applyIfMissing(dotenv, "DB_USERNAME");
        applyIfMissing(dotenv, "DB_PASSWORD");
    }

    private static Dotenv loadDotenv() {
        Path dotenvPath = Path.of(DOTENV_DIRECTORY, ".env");
        if (Files.exists(dotenvPath)) {
            return Dotenv.configure()
                    .directory(dotenvPath.getParent().toString())
                    .filename(dotenvPath.getFileName().toString())
                    .ignoreIfMalformed()
                    .ignoreIfMissing()
                    .load();
        }

        try (InputStream inputStream = WaterStationPusherApplication.class.getResourceAsStream("/.env")) {
            if (inputStream == null) {
                return Dotenv.configure()
                        .ignoreIfMalformed()
                        .ignoreIfMissing()
                        .load();
            }

            Path tempDotenv = Files.createTempFile("water-service-", ".env");
            Files.copy(inputStream, tempDotenv, StandardCopyOption.REPLACE_EXISTING);
            tempDotenv.toFile().deleteOnExit();

            return Dotenv.configure()
                    .directory(tempDotenv.getParent().toString())
                    .filename(tempDotenv.getFileName().toString())
                    .ignoreIfMalformed()
                    .ignoreIfMissing()
                    .load();
        } catch (IOException exception) {
            throw new IllegalStateException("Failed to load .env configuration", exception);
        }
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
