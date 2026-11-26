package com.fishfind.water.config;

import java.util.Locale;

/**
 * Normalises {@code MYSQL_URL}, the JDBC URL of the MySQL {@code envdata} database
 * ({@code jdbc:mysql://HOST:PORT/envdata?sslMode=REQUIRED}), the same key the C# twin reads
 * (efcs-backend/service/waterservice {@code MySqlUrl}). Only the defaults the C# twin applies are added, and only when
 * the URL does not say otherwise:
 * <ul>
 *   <li>{@code sslMode=REQUIRED}: envdata's accounts are {@code REQUIRE SSL} (no {@code sslMode} / {@code useSSL} given);</li>
 *   <li>{@code connectTimeout=15000} (milliseconds; the C# twin's 15 s);</li>
 *   <li>{@code connectionTimeZone=UTC}: every envdata time is UTC (this code binds {@code LocalDateTime}s, which are
 *       never shifted, but a stray {@code Timestamp} must not be shifted by the JVM zone either).</li>
 * </ul>
 * Any other JDBC URL (the H2 one of the tests) is returned unchanged. A native MySqlConnector connection string, which
 * the C# twin also accepts, is not a JDBC URL and is refused.
 */
public final class MySqlUrl {

    private static final String MYSQL_PREFIX = "jdbc:mysql://";

    private MySqlUrl() {
    }

    /**
     * @param url {@code MYSQL_URL}
     * @return the URL with the defaults above added
     * @throws IllegalStateException when the URL is blank or not a JDBC URL
     */
    public static String normalize(String url) {
        if (url == null || url.isBlank()) {
            throw new IllegalStateException("MYSQL_URL is not set: the envdata JDBC URL "
                    + "(jdbc:mysql://<host>:3306/envdata?sslMode=REQUIRED) is required since 2.0.0.");
        }
        String trimmed = url.trim();
        if (!trimmed.regionMatches(true, 0, "jdbc:", 0, 5)) {
            throw new IllegalStateException("MYSQL_URL must be a JDBC URL (jdbc:mysql://...), not a connection string.");
        }
        if (!trimmed.regionMatches(true, 0, MYSQL_PREFIX, 0, MYSQL_PREFIX.length())) {
            return trimmed;
        }

        StringBuilder result = new StringBuilder(trimmed);
        String query = trimmed.indexOf('?') >= 0 ? trimmed.substring(trimmed.indexOf('?') + 1) : "";
        String lower = "&" + query.toLowerCase(Locale.ROOT);
        char separator = trimmed.indexOf('?') >= 0 ? (query.isEmpty() ? '\0' : '&') : '?';

        if (!lower.contains("&sslmode=") && !lower.contains("&usessl=") && !lower.contains("&requiressl=")) {
            separator = append(result, separator, "sslMode=REQUIRED");
        }
        if (!lower.contains("&connecttimeout=")) {
            separator = append(result, separator, "connectTimeout=15000");
        }
        if (!lower.contains("&connectiontimezone=") && !lower.contains("&servertimezone=")) {
            append(result, separator, "connectionTimeZone=UTC");
        }
        return result.toString();
    }

    private static char append(StringBuilder url, char separator, String pair) {
        if (separator != '\0') {
            url.append(separator);
        }
        url.append(pair);
        return '&';
    }
}
