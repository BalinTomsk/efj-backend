package info.fishfind.auth.repository;

import info.fishfind.auth.domain.User;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCreator;
import org.springframework.jdbc.support.KeyHolder;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class UserRepositoryTest {

    private JdbcTemplate jdbcTemplate;
    private UserRepository userRepository;

    @BeforeEach
    void setUp() {
        jdbcTemplate = mock(JdbcTemplate.class);
        userRepository = new UserRepository(jdbcTemplate);
    }

    @Test
    void findByEmailOrUsernameReturnsFirstMatchingUser() {
        User user = sampleUser();

        when(jdbcTemplate.query(anyString(), any(UserRowMapper.class), eq("login"), eq("login")))
                .thenReturn(List.of(user, sampleUser()));

        assertThat(userRepository.findByEmailOrUsername("login")).contains(user);
    }

    @Test
    void findByEmailOrUsernameReturnsEmptyWhenNothingMatches() {
        when(jdbcTemplate.query(anyString(), any(UserRowMapper.class), eq("login"), eq("login")))
                .thenReturn(List.of());

        assertThat(userRepository.findByEmailOrUsername("login")).isEmpty();
    }

    @Test
    void findByIdReturnsUserWhenPresent() {
        User user = sampleUser();

        when(jdbcTemplate.queryForObject(anyString(), any(UserRowMapper.class), eq(7L)))
                .thenReturn(user);

        assertThat(userRepository.findById(7L)).contains(user);
    }

    @Test
    void findByIdReturnsEmptyWhenNoRowExists() {
        when(jdbcTemplate.queryForObject(anyString(), any(UserRowMapper.class), anyLong()))
                .thenThrow(new EmptyResultDataAccessException(1));

        assertThat(userRepository.findById(7L)).isEmpty();
    }

    @Test
    void findByConfirmationTokenReturnsFirstMatchingUser() {
        User user = sampleUser();

        when(jdbcTemplate.query(anyString(), any(UserRowMapper.class), eq("token-123")))
                .thenReturn(List.of(user));

        assertThat(userRepository.findByConfirmationToken("token-123")).contains(user);
    }

    @Test
    void insertCreatesPreparedStatementAndReturnsGeneratedKey() throws SQLException {
        Connection connection = mock(Connection.class);
        PreparedStatement statement = mock(PreparedStatement.class);

        when(jdbcTemplate.update(any(PreparedStatementCreator.class), any(KeyHolder.class)))
                .thenAnswer(invocation -> {
                    PreparedStatementCreator creator = invocation.getArgument(0);
                    KeyHolder keyHolder = invocation.getArgument(1);

                    creator.createPreparedStatement(connection);
                    keyHolder.getKeyList().add(Map.of("id", 42L));
                    return 1;
                });
        when(connection.prepareStatement(anyString(), eq(Statement.RETURN_GENERATED_KEYS)))
                .thenReturn(statement);

        long id = userRepository.insert("alice", "alice@example.com", "encoded", "token-123");

        assertThat(id).isEqualTo(42L);
        verify(connection).prepareStatement(anyString(), eq(Statement.RETURN_GENERATED_KEYS));
        verify(statement).setString(1, "alice");
        verify(statement).setString(2, "alice@example.com");
        verify(statement).setString(3, "encoded");
        verify(statement).setString(4, "token-123");
    }

    @Test
    void activateUserDelegatesUpdateAndReturnsAffectedRows() {
        when(jdbcTemplate.update(anyString(), eq(9L))).thenReturn(1);

        assertThat(userRepository.activateUser(9L)).isEqualTo(1);
    }

    @Test
    void updateProfileDelegatesUpdateAndReturnsAffectedRows() {
        when(jdbcTemplate.update(anyString(), eq("alice"), eq("alice@example.com"), eq(9L)))
                .thenReturn(1);

        assertThat(userRepository.updateProfile(9L, "alice", "alice@example.com")).isEqualTo(1);
    }

    @Test
    void updatePasswordDelegatesUpdateAndReturnsAffectedRows() {
        when(jdbcTemplate.update(anyString(), eq("encoded"), eq(9L))).thenReturn(1);

        assertThat(userRepository.updatePassword(9L, "encoded")).isEqualTo(1);
    }

    @Test
    void deleteByIdDelegatesUpdateAndReturnsAffectedRows() {
        when(jdbcTemplate.update(anyString(), eq(9L))).thenReturn(1);

        assertThat(userRepository.deleteById(9L)).isEqualTo(1);
    }

    private static User sampleUser() {
        OffsetDateTime now = OffsetDateTime.now();
        return new User(7L, "alice", "alice@example.com", "encoded", false, "token-123", now, now);
    }
}
