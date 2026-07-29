package com.fishfind.water.config;

import io.github.cdimascio.dotenv.Dotenv;
import io.github.cdimascio.dotenv.DotenvEntry;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.env.EnvironmentPostProcessor;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.StandardEnvironment;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;

/**
 * Loads a {@code .env} file (for local development) and exposes its values to Spring as a
 * <strong>lowest-precedence</strong> property source.
 *
 * <p>This replaces the previous approach of copying credentials into JVM-global system properties via
 * {@code System.setProperty}, which leaked secrets into {@code System.getProperties()}, heap dumps, and
 * diagnostic tooling. Because the property source is registered with {@code addLast}, real OS environment
 * variables and JVM system properties always take precedence, so production deployments that inject
 * {@code DB_URL}/{@code DB_USERNAME}/{@code DB_PASSWORD} as environment variables are unaffected and the
 * {@code .env} file is only a local fallback.
 */
public class DotenvEnvironmentPostProcessor implements EnvironmentPostProcessor {

    private static final String PROPERTY_SOURCE_NAME = "dotenvProperties";
    private static final String DECRYPTED_SOURCE_NAME = "decryptedEnvironmentProperties";
    private static final String DOTENV_PATH_ENV = "DOTENV_PATH";
    private static final String DEFAULT_DOTENV_FILE = ".env";
    private static final String MISSING_DOTENV_FILE = ".env.missing";

    /**
     * Reads the resolved {@code .env} file and adds its declared entries as a low-precedence property source,
     * unwrapping any {@code enc:v1:} values it finds. Encrypted values already present as real environment
     * variables are handled separately by {@link #decryptEncryptedEnvironmentVariables}.
     *
     * @param environment the application environment to augment
     * @param application the Spring application being started
     */
    @Override
    public void postProcessEnvironment(ConfigurableEnvironment environment, SpringApplication application) {
        decryptEncryptedEnvironmentVariables(environment);

        Dotenv dotenv = loadDotenv();

        Map<String, Object> values = new HashMap<>();
        // DECLARED_IN_ENV_FILE so we only pick up keys from the file, never the entire OS environment.
        for (DotenvEntry entry : dotenv.entries(Dotenv.Filter.DECLARED_IN_ENV_FILE)) {
            if (entry.getValue() != null && !entry.getValue().isBlank()) {
                values.put(entry.getKey(), SecretCodec.decryptIfNeeded(entry.getKey(), entry.getValue()));
            }
        }

        if (values.isEmpty()) {
            return;
        }

        environment.getPropertySources().addLast(new MapPropertySource(PROPERTY_SOURCE_NAME, values));
    }

    /**
     * Replaces any {@code enc:v1:} values sitting in the real process environment with their plaintext.
     *
     * <p>Needed because credentials do not always arrive through the dotenv file: {@code docapi} is
     * deployed with Docker's {@code --env-file}, which is read by the daemon and injects the values as
     * genuine environment variables, so the file-loading path above never sees them. The decrypted
     * values are added directly <em>before</em> the {@code systemEnvironment} source rather than with
     * {@code addFirst}, so command-line arguments and any test override still take precedence.
     *
     * <p>No property source is added when nothing in the environment is encrypted, which keeps this a
     * complete no-op for the existing all-plaintext deployments.
     *
     * @param environment the application environment to augment
     */
    private void decryptEncryptedEnvironmentVariables(ConfigurableEnvironment environment) {
        Map<String, Object> decrypted = new HashMap<>();

        for (Map.Entry<String, Object> entry : environment.getSystemEnvironment().entrySet()) {
            if (entry.getValue() instanceof String value && SecretCodec.isEncrypted(value)) {
                decrypted.put(entry.getKey(), SecretCodec.decryptIfNeeded(entry.getKey(), value));
            }
        }

        if (decrypted.isEmpty()) {
            return;
        }

        MapPropertySource source = new MapPropertySource(DECRYPTED_SOURCE_NAME, decrypted);
        if (environment.getPropertySources().contains(StandardEnvironment.SYSTEM_ENVIRONMENT_PROPERTY_SOURCE_NAME)) {
            environment.getPropertySources()
                    .addBefore(StandardEnvironment.SYSTEM_ENVIRONMENT_PROPERTY_SOURCE_NAME, source);
        } else {
            environment.getPropertySources().addFirst(source);
        }
    }

    /**
     * Loads dotenv configuration from a custom path ({@code DOTENV_PATH}) or the working directory when present.
     *
     * @return the loaded dotenv instance; never throws for a missing or malformed file
     */
    private Dotenv loadDotenv() {
        Path configuredPath = resolveDotenvPath();
        if (configuredPath != null && Files.isRegularFile(configuredPath)) {
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
                .filename(MISSING_DOTENV_FILE)
                .ignoreIfMalformed()
                .ignoreIfMissing()
                .load();
    }

    /**
     * Resolves the dotenv file to use, preferring {@code DOTENV_PATH} over the default project file.
     *
     * @return the configured dotenv path, or {@code null} when no file is available
     */
    private Path resolveDotenvPath() {
        String configuredPath = System.getenv(DOTENV_PATH_ENV);
        if (configuredPath != null && !configuredPath.isBlank()) {
            return Path.of(configuredPath.trim());
        }

        Path workingDirectoryDotenv = Path.of(DEFAULT_DOTENV_FILE);
        if (Files.isRegularFile(workingDirectoryDotenv)) {
            return workingDirectoryDotenv;
        }

        return null;
    }
}
