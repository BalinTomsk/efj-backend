package info.fishfind.auth.repository;

import info.fishfind.auth.domain.User;
import org.springframework.jdbc.core.RowMapper;

import java.sql.ResultSet;
import java.sql.SQLException;

public class UserRowMapper implements RowMapper<User> {
    /**
     * Maps a JDBC result row into a {@link User} record.
     *
     * @param rs current result set
     * @param rowNum current row number
     * @return mapped user
     * @throws SQLException when column access fails
     */
    @Override
    public User mapRow(ResultSet rs, int rowNum) throws SQLException {
        return new User(
                rs.getLong("id"),
                rs.getString("username"),
                rs.getString("email"),
                rs.getString("password"),
                rs.getBoolean("confirmed"),
                rs.getString("confirmation_token"),
                rs.getObject("created_at", java.time.OffsetDateTime.class),
                rs.getObject("updated_at", java.time.OffsetDateTime.class)
        );
    }
}
