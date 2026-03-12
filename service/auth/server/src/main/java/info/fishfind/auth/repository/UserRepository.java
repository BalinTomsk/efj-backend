package info.fishfind.auth.repository;

import info.fishfind.auth.domain.User;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Repository;

import java.sql.PreparedStatement;
import java.sql.Statement;
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
    }

    /**
     * Looks up a user by email address or username.
     *
     * @param login email address or username
     * @return matching user when present
     */
    public Optional<User> findByEmailOrUsername(String login) {
        var sql = """
                SELECT id, username, email, password, confirmed, confirmation_token, created_at, updated_at
                FROM users
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
            var sql = """
                    SELECT id, username, email, password, confirmed, confirmation_token, created_at, updated_at
                    FROM users
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
        var sql = """
                SELECT id, username, email, password, confirmed, confirmation_token, created_at, updated_at
                FROM users
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
    public long insert(String username, String email, String encodedPassword, String confirmationToken) {
        var sql = """
                INSERT INTO users (username, email, password, confirmation_token, confirmed)
                VALUES (?, ?, ?, ?, 0)
                """;
        KeyHolder keyHolder = new GeneratedKeyHolder();
        jdbcTemplate.update(connection -> {
            PreparedStatement statement = connection.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS);
            statement.setString(1, username);
            statement.setString(2, email);
            statement.setString(3, encodedPassword);
            statement.setString(4, confirmationToken);
            return statement;
        }, keyHolder);
        return keyHolder.getKey().longValue();
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
}
