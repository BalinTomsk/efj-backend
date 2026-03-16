package info.fishfind.auth.repository;

import info.fishfind.auth.domain.User;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.sql.PreparedStatement;
import java.sql.Statement;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public class UserRepository {
    private static final UserRowMapper USER_ROW_MAPPER = new UserRowMapper();

    private final JdbcTemplate jdbcTemplate;

    /**
     * Creates a repository backed by the provided JDBC template.
     *
     * @param jdbcTemplate JDBC access helper
     */
    public UserRepository(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
        initializeSchema();
    }

    /**
     * Looks up a user by email address or username.
     *
     * @param login email address or username
     * @return matching user when present
     */
    public Optional<User> findByEmailOrUsername(String login) {
        var sql = baseSelect() + """
                WHERE email = ? OR username = ?
                """;
        List<User> users = jdbcTemplate.query(sql, USER_ROW_MAPPER, login, login);
        return users.stream().findFirst();
    }

    /**
     * Looks up a user by primary key.
     *
     * @param id user identifier
     * @return matching user when present
     */
    public Optional<User> findById(Long id) {
        try {
            var sql = baseSelect() + """
                    WHERE id = ?
                    """;
            return Optional.ofNullable(jdbcTemplate.queryForObject(sql, USER_ROW_MAPPER, id));
        } catch (EmptyResultDataAccessException ex) {
            return Optional.empty();
        }
    }

    /**
     * Finds a user by the pending confirmation token.
     *
     * @param token email confirmation token
     * @return matching user when present
     */
    public Optional<User> findByConfirmationToken(String token) {
        var sql = baseSelect() + """
                WHERE confirmation_token = ?
                """;
        List<User> users = jdbcTemplate.query(sql, USER_ROW_MAPPER, token);
        return users.stream().findFirst();
    }

    /**
     * Inserts a new user row and returns the generated identifier.
     *
     * @param username username to persist
     * @param email email address to persist
     * @param encodedPassword hashed password
     * @param confirmationToken account activation token
     * @return generated user identifier
     */
    public long insert(String username,
                       String email,
                       String encodedPassword,
                       String ip4,
                       String ip6,
                       String titul,
                       String question,
                       String answer,
                       String cell,
                       String agent,
                       String confirmationToken) {
        var sql = """
                INSERT INTO users (
                    username, email, password, ip4, ip6, titul, question, answer, cell, agent, confirmation_token, confirmed
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                """;
        KeyHolder keyHolder = new GeneratedKeyHolder();
        jdbcTemplate.update(connection -> {
            PreparedStatement statement = connection.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS);
            statement.setString(1, username);
            statement.setString(2, email);
            statement.setString(3, encodedPassword);
            statement.setString(4, ip4);
            statement.setString(5, ip6);
            statement.setString(6, titul);
            statement.setString(7, question);
            statement.setString(8, answer);
            statement.setString(9, cell);
            statement.setString(10, agent);
            statement.setString(11, confirmationToken);
            return statement;
        }, keyHolder);
        return keyHolder.getKey().longValue();
    }

    public Optional<User> findSuspendedByNetwork(String ip4, String ip6) {
        var sql = baseSelect() + """
                WHERE suspended = 1
                  AND ((? <> '' AND ip4 = ?) OR (? <> '' AND ip6 = ?))
                """;
        List<User> users = jdbcTemplate.query(sql, USER_ROW_MAPPER, ip4, ip4, ip6, ip6);
        return users.stream().findFirst();
    }

    public Optional<User> findByNetwork(String ip4, String ip6) {
        var sql = baseSelect() + """
                WHERE (? <> '' AND ip4 = ?)
                   OR (? <> '' AND ip6 = ?)
                """;
        List<User> users = jdbcTemplate.query(sql, USER_ROW_MAPPER, ip4, ip4, ip6, ip6);
        return users.stream().findFirst();
    }

    /**
     * Marks a user as confirmed and clears the confirmation token.
     *
     * @param id user identifier
     * @return number of updated rows
     */
    public int activateUser(long id) {
        var sql = """
                UPDATE users
                SET confirmed = 1,
                    confirmation_token = NULL,
                    updated_at = SYSDATETIMEOFFSET()
                WHERE id = ?
                """;
        return jdbcTemplate.update(sql, id);
    }

    /**
     * Updates a user's username and email.
     *
     * @param id user identifier
     * @param username new username
     * @param email new email address
     * @return number of updated rows
     */
    public int updateProfile(long id, String username, String email) {
        var sql = """
                UPDATE users
                SET username = ?,
                    email = ?,
                    updated_at = SYSDATETIMEOFFSET()
                WHERE id = ?
                """;
        return jdbcTemplate.update(sql, username, email, id);
    }

    public int updateLastVisit(long id, OffsetDateTime lastVisit) {
        var sql = """
                UPDATE users
                SET last_visit = ?,
                    updated_at = SYSDATETIMEOFFSET()
                WHERE id = ?
                """;
        return jdbcTemplate.update(sql, lastVisit, id);
    }

    /**
     * Updates a user's stored password hash.
     *
     * @param id user identifier
     * @param encodedPassword new hashed password
     * @return number of updated rows
     */
    public int updatePassword(long id, String encodedPassword) {
        var sql = """
                UPDATE users
                SET password = ?,
                    updated_at = SYSDATETIMEOFFSET()
                WHERE id = ?
                """;
        return jdbcTemplate.update(sql, encodedPassword, id);
    }

    /**
     * Deletes a user by identifier.
     *
     * @param id user identifier
     * @return number of deleted rows
     */
    public int deleteById(long id) {
        return jdbcTemplate.update("DELETE FROM users WHERE id = ?", id);
    }

    @Transactional
    void initializeSchema() {
        jdbcTemplate.execute("""
                IF OBJECT_ID('users', 'U') IS NULL
                BEGIN
                    CREATE TABLE users (
                        id BIGINT IDENTITY(1,1) PRIMARY KEY,
                        username NVARCHAR(255) NOT NULL UNIQUE,
                        email NVARCHAR(255) NOT NULL UNIQUE,
                        password NVARCHAR(255) NOT NULL,
                        ip4 NVARCHAR(64) NULL,
                        ip6 NVARCHAR(128) NULL,
                        titul NVARCHAR(255) NULL,
                        last_visit DATETIMEOFFSET NULL,
                        question NVARCHAR(255) NULL,
                        answer NVARCHAR(255) NULL,
                        cell NVARCHAR(255) NULL,
                        suspended BIT NOT NULL CONSTRAINT DF_users_suspended DEFAULT 0,
                        agent NVARCHAR(1024) NULL,
                        confirmed BIT NOT NULL CONSTRAINT DF_users_confirmed DEFAULT 0,
                        confirmation_token NVARCHAR(255) NULL,
                        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_users_created_at DEFAULT SYSDATETIMEOFFSET(),
                        updated_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_users_updated_at DEFAULT SYSDATETIMEOFFSET()
                    )
                END
                """);

        addColumnIfMissing("ip4", "NVARCHAR(64) NULL");
        addColumnIfMissing("ip6", "NVARCHAR(128) NULL");
        addColumnIfMissing("titul", "NVARCHAR(255) NULL");
        addColumnIfMissing("last_visit", "DATETIMEOFFSET NULL");
        addColumnIfMissing("question", "NVARCHAR(255) NULL");
        addColumnIfMissing("answer", "NVARCHAR(255) NULL");
        addColumnIfMissing("cell", "NVARCHAR(255) NULL");
        addColumnIfMissing("suspended", "BIT NOT NULL CONSTRAINT DF_users_suspended_backfill DEFAULT 0");
        addColumnIfMissing("agent", "NVARCHAR(1024) NULL");
        addColumnIfMissing("confirmed", "BIT NOT NULL CONSTRAINT DF_users_confirmed_backfill DEFAULT 0");
        addColumnIfMissing("confirmation_token", "NVARCHAR(255) NULL");
        addColumnIfMissing("created_at", "DATETIMEOFFSET NOT NULL CONSTRAINT DF_users_created_at_backfill DEFAULT SYSDATETIMEOFFSET()");
        addColumnIfMissing("updated_at", "DATETIMEOFFSET NOT NULL CONSTRAINT DF_users_updated_at_backfill DEFAULT SYSDATETIMEOFFSET()");
        backfillLegacyNetworkColumns();
    }

    private void addColumnIfMissing(String columnName, String definition) {
        jdbcTemplate.execute("""
                IF COL_LENGTH('users', '%s') IS NULL
                BEGIN
                    EXEC('ALTER TABLE users ADD %s %s')
                END
                """.formatted(columnName, columnName, definition));
    }

    private void backfillLegacyNetworkColumns() {
        Integer legacyColumnCount = jdbcTemplate.queryForObject("""
                SELECT COUNT(*)
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'users' AND COLUMN_NAME = 'registration_ip'
                """, Integer.class);
        if (legacyColumnCount == null || legacyColumnCount == 0) {
            return;
        }

        jdbcTemplate.query("""
                SELECT id, registration_ip
                FROM users
                WHERE (ip4 IS NULL OR ip4 = '')
                  AND (ip6 IS NULL OR ip6 = '')
                  AND registration_ip IS NOT NULL
                  AND registration_ip <> ''
                """, rs -> {
            long id = rs.getLong("id");
            String registrationIp = rs.getString("registration_ip");
            StoredIp storedIp = getStoredIpColumns(registrationIp);
            if (!storedIp.hasValue()) {
                return;
            }
            jdbcTemplate.update("UPDATE users SET ip4 = ?, ip6 = ? WHERE id = ?", storedIp.ip4(), storedIp.ip6(), id);
        });
    }

    private StoredIp getStoredIpColumns(String ipValue) {
        if (ipValue == null || ipValue.isBlank()) {
            return new StoredIp("", "");
        }

        String trimmedIp = ipValue.trim();
        if (trimmedIp.startsWith("::ffff:")) {
            String extractedIpv4 = trimmedIp.substring(7);
            if (extractedIpv4.matches("^(25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)(\\.(25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){3}$")) {
                return new StoredIp(extractedIpv4, trimmedIp.toLowerCase());
            }
        }

        if (trimmedIp.matches("^(25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)(\\.(25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){3}$")) {
            return new StoredIp(trimmedIp, "");
        }

        if (trimmedIp.contains(":")) {
            return new StoredIp("", trimmedIp.toLowerCase());
        }

        return new StoredIp("", "");
    }

    private String baseSelect() {
        return """
                SELECT id, username, email, password, ip4, ip6, titul, last_visit, question, answer, cell, suspended, agent,
                       confirmed, confirmation_token, created_at, updated_at
                FROM users
                """;
    }

    private record StoredIp(String ip4, String ip6) {
        boolean hasValue() {
            return (ip4 != null && !ip4.isBlank()) || (ip6 != null && !ip6.isBlank());
        }
    }
}
