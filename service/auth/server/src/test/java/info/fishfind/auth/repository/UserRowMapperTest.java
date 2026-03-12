package info.fishfind.auth.repository;

import info.fishfind.auth.domain.User;
import org.junit.jupiter.api.Test;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.OffsetDateTime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class UserRowMapperTest {

    private final UserRowMapper userRowMapper = new UserRowMapper();

    @Test
    void mapRowMapsAllColumnsToUser() throws SQLException {
        ResultSet resultSet = mock(ResultSet.class);
        OffsetDateTime createdAt = OffsetDateTime.parse("2026-03-12T00:00:00Z");
        OffsetDateTime updatedAt = OffsetDateTime.parse("2026-03-12T01:00:00Z");

        when(resultSet.getLong("id")).thenReturn(7L);
        when(resultSet.getString("username")).thenReturn("alice");
        when(resultSet.getString("email")).thenReturn("alice@example.com");
        when(resultSet.getString("password")).thenReturn("encoded");
        when(resultSet.getBoolean("confirmed")).thenReturn(true);
        when(resultSet.getString("confirmation_token")).thenReturn("token-123");
        when(resultSet.getObject("created_at", OffsetDateTime.class)).thenReturn(createdAt);
        when(resultSet.getObject("updated_at", OffsetDateTime.class)).thenReturn(updatedAt);

        User user = userRowMapper.mapRow(resultSet, 0);

        assertThat(user.id()).isEqualTo(7L);
        assertThat(user.username()).isEqualTo("alice");
        assertThat(user.email()).isEqualTo("alice@example.com");
        assertThat(user.password()).isEqualTo("encoded");
        assertThat(user.confirmed()).isTrue();
        assertThat(user.confirmationToken()).isEqualTo("token-123");
        assertThat(user.createdAt()).isEqualTo(createdAt);
        assertThat(user.updatedAt()).isEqualTo(updatedAt);
    }
}
