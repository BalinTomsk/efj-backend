package com.fishfind.weather;

import com.fishfind.weather.config.SecretCodec;
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

    /**
     * The keys taken from the dotenv file. Only these: the file is shared with the water service and holds keys this
     * service must not see. {@code MYSQL_*} (2.0.0) is the envdata connection; {@code DB_*} (SQL Server) is still
     * imported but no longer read by anything.
     */
    static final java.util.List<String> DOTENV_KEYS = java.util.List.of(
            "MYSQL_URL", "MYSQL_USERNAME", "MYSQL_PASSWORD",
            "DB_URL", "DB_USERNAME", "DB_PASSWORD",
            "SMTP_HOST", "SMTP_PORT", "SMTP_USERNAME", "SMTP_PASSWORD",
            "REPORT_EMAIL_TO", "REPORT_EMAIL_FROM",
            "WEATHER_GOV_USER_AGENT", "WEATHER_CANADA_USER_AGENT",
            "VISUAL_CROSSING_API_KEY", "GOOGLE_WEATHER_API_KEY", "WUNDERGROUND_API_KEY");

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
        for (String key : DOTENV_KEYS) {
            addIfMissing(dotenv, fallback, key);
        }
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

    /**
     * Adds one dotenv value to the fallback map unless the process environment or system properties
     * already supply it, unwrapping the value first when it is stored as {@code enc:v1:} ciphertext.
     * An encrypted value arriving as a real environment variable instead is handled by
     * {@link com.fishfind.weather.config.EncryptedEnvironmentPostProcessor}, which can outrank it.
     */
    static void addIfMissing(Dotenv dotenv, Map<String, Object> fallback, String key) {
        if (System.getenv(key) != null || System.getProperty(key) != null) {
            return;
        }

        String value = dotenv.get(key);
        if (value != null && !value.isBlank()) {
            fallback.put(key, SecretCodec.decryptIfNeeded(key, value));
        }
    }
}
