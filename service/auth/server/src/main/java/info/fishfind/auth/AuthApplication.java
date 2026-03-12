package info.fishfind.auth;

import io.github.cdimascio.dotenv.Dotenv;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

@SpringBootApplication
public class AuthApplication {

    /**
     * Boots the auth application after loading environment overrides from local .env files.
     *
     * @param args Spring Boot startup arguments
     */
    public static void main(String[] args) {
        loadDotEnv();
        SpringApplication.run(AuthApplication.class, args);
    }

    /**
     * Attempts to load a .env file from likely launch locations.
     */
    private static void loadDotEnv() {
        Path cwd = Paths.get("").toAbsolutePath();

        // Try current working directory first
        tryLoad(cwd);

        // Try ./server when running from auth root
        tryLoad(cwd.resolve("server"));

        // Try parent in case of odd launch location
        Path parent = cwd.getParent();
        if (parent != null) {
            tryLoad(parent);
            tryLoad(parent.resolve("server"));
        }
    }

    /**
     * Loads environment values from the given directory when a .env file is present.
     *
     * @param dir directory expected to contain a .env file
     */
    private static void tryLoad(Path dir) {
        Path envFile = dir.resolve(".env");
        if (!Files.exists(envFile)) {
            return;
        }

        Dotenv dotenv = Dotenv.configure()
                .directory(dir.toString())
                .ignoreIfMalformed()
                .ignoreIfMissing()
                .load();

        dotenv.entries().forEach(entry -> {
            // Only set if not already provided by OS env / JVM args
            if (System.getProperty(entry.getKey()) == null && System.getenv(entry.getKey()) == null) {
                System.setProperty(entry.getKey(), entry.getValue());
            }
        });
    }
}
