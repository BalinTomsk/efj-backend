package com.fishfind.weather;

import io.github.cdimascio.dotenv.Dotenv;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Bootstraps the weather worker application and loads database/SMTP credentials
 * from the process environment or a dotenv file before Spring starts.
 */
@SpringBootApplication
@EnableScheduling
public class WeatherStationPusherApplication {
    private static final String DEFAULT_DOTENV_FILE = ".env";
    private static final String DOTENV_PATH_ENV = "DOTENV_PATH";

    public static void main(String[] args) {
        SpringApplication application = new SpringApplication(WeatherStationPusherApplication.class);

        Map<String, Object> dotenvFallback = loadDotenvCredentials();
        if (!dotenvFallback.isEmpty()) {
            // Lowest-precedence source: the real process environment / system properties still win.
            application.setDefaultProperties(dotenvFallback);
        }

        application.run(args);
    }

    /**
     * Collects DB and SMTP credentials from a dotenv file as a fallback for keys not already
     * supplied by the process environment or JVM system properties. The values are returned
     * for use as Spring default properties rather than being copied into the JVM-global system
     * properties table, so that secrets (notably {@code DB_PASSWORD} and {@code SMTP_PASSWORD})
     * are not exposed process-wide via {@link System#getProperty} or heap-dump diagnostics.
     *
     * <p>The SMTP_* keys and REPORT_EMAIL_TO are optional: the weekly report email is silently
     * skipped (not a startup failure) when they are absent — see {@link
     * com.fishfind.weather.service.WeeklyReportMailService}.
     */
    private static Map<String, Object> loadDotenvCredentials() {
        Dotenv dotenv = loadDotenv();

        Map<String, Object> fallback = new HashMap<>();
        addIfMissing(dotenv, fallback, "DB_URL");
        addIfMissing(dotenv, fallback, "DB_USERNAME");
        addIfMissing(dotenv, fallback, "DB_PASSWORD");
        addIfMissing(dotenv, fallback, "SMTP_HOST");
        addIfMissing(dotenv, fallback, "SMTP_PORT");
        addIfMissing(dotenv, fallback, "SMTP_USERNAME");
        addIfMissing(dotenv, fallback, "SMTP_PASSWORD");
        addIfMissing(dotenv, fallback, "REPORT_EMAIL_TO");
        addIfMissing(dotenv, fallback, "REPORT_EMAIL_FROM");
        addIfMissing(dotenv, fallback, "WEATHER_GOV_USER_AGENT");
        return fallback;
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

    static void addIfMissing(Dotenv dotenv, Map<String, Object> fallback, String key) {
        if (System.getenv(key) != null || System.getProperty(key) != null) {
            return;
        }

        String value = dotenv.get(key);
        if (value != null && !value.isBlank()) {
            fallback.put(key, value);
        }
    }
}
