package com.fishfind.weather.repo;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.fishfind.weather.canonical.WeatherSourceType;
import com.fishfind.weather.config.SqlFailures;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Types;
import java.time.LocalDateTime;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.jdbc.UncategorizedSQLException;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;

/**
 * Pins the SQL text, the bound parameters and the 45000 rule. A mock never parses SQL: {@link WeatherEngineTest} runs
 * the same repositories against a real MySQL engine.
 */
class WeatherDataRepositoryTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final WeatherDataRepository repository = new WeatherDataRepository(jdbc);

    private final Logger repoLogger = (Logger) LoggerFactory.getLogger(WeatherDataRepository.class);
    private final ListAppender<ILoggingEvent> logs = new ListAppender<>();

    @BeforeEach
    void captureLogs() {
        logs.start();
        repoLogger.addAppender(logs);
    }

    @AfterEach
    void releaseLogs() {
        repoLogger.detachAppender(logs);
    }

    /** Runs the repository's ConnectionCallback against a mocked connection whose SELECT @out_days returns {@code days}. */
    @SuppressWarnings("unchecked")
    private PreparedStatement runSaveAgainst(Integer days) throws Exception {
        Connection connection = mock(Connection.class);
        PreparedStatement call = mock(PreparedStatement.class);
        Statement select = mock(Statement.class);
        ResultSet rs = mock(ResultSet.class);
        when(connection.prepareStatement("CALL sp_weather_save(?, ?, ?, @out_days)")).thenReturn(call);
        when(connection.createStatement()).thenReturn(select);
        when(select.executeQuery("SELECT @out_days")).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getInt(1)).thenReturn(days == null ? 0 : days);
        when(rs.wasNull()).thenReturn(days == null);
        when(jdbc.execute(any(ConnectionCallback.class))).thenAnswer(inv ->
                ((ConnectionCallback<Integer>) inv.getArgument(0)).doInConnection(connection));

        repository.saveStationData("MLI-1", "{\"schema\":\"x\"}", WeatherSourceType.OPEN_METEO);
        return call;
    }

    @Test
    void saveStationDataCallsSpWeatherSaveAndReadsTheOutParameterOnTheSameConnection() throws Exception {
        PreparedStatement call = runSaveAgainst(8);

        verify(call).setString(1, "MLI-1");
        verify(call).setInt(2, WeatherSourceType.OPEN_METEO);
        verify(call).setString(3, "{\"schema\":\"x\"}");
        verify(call).execute();
        assertThat(logs.list).noneMatch(e -> e.getLevel() == Level.WARN);
    }

    @Test
    void aPayloadStoredButNotShreddedIsLogged() throws Exception {
        runSaveAgainst(-1);

        assertThat(logs.list).anyMatch(e -> e.getLevel() == Level.WARN
                && e.getFormattedMessage().contains("Payload stored but not shredded"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void anUnknownStationIsLoggedAndDroppedNotThrown() {
        when(jdbc.execute(any(ConnectionCallback.class))).thenThrow(new UncategorizedSQLException("CALL", "CALL",
                new SQLException("sp_weather_save: unknown station mli", "45000", 1644)));

        repository.saveStationData("NOPE", "{}", WeatherSourceType.WEATHER_GOV);

        assertThat(logs.list).anyMatch(e -> e.getLevel() == Level.WARN
                && e.getFormattedMessage().contains("Station unknown to envdata; payload dropped. mli=NOPE"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void anOutageIsRethrownForTheRetryAndBreaker() {
        DataAccessResourceFailureException outage = new DataAccessResourceFailureException("link failure");
        when(jdbc.execute(any(ConnectionCallback.class))).thenThrow(outage);

        assertThatThrownBy(() -> repository.saveStationData("MLI-1", "{}", WeatherSourceType.OPEN_METEO))
                .isSameAs(outage);
        assertThat(SqlFailures.isSqlFailure(outage)).isTrue();
    }

    @Test
    void saveStationDataRejectsBlankMliAndSkipsBlankPayload() {
        assertThatThrownBy(() -> repository.saveStationData(" ", "{}", WeatherSourceType.OPEN_METEO))
                .isInstanceOf(IllegalArgumentException.class);
        repository.saveStationData("MLI-1", "  ", WeatherSourceType.OPEN_METEO);

        verifyNoInteractions(jdbc);
    }

    @Test
    void recordCycleBindsEveryParameterAndTheOutParameterIsASessionVariable() throws Exception {
        LocalDateTime started = LocalDateTime.of(2026, 11, 25, 0, 0);
        LocalDateTime finished = started.plusHours(8);

        repository.recordCycle("open-meteo-ca", started, finished, "ok", 1150, null);

        ArgumentCaptor<PreparedStatementSetter> setter = ArgumentCaptor.forClass(PreparedStatementSetter.class);
        verify(jdbc).update(eq("CALL sp_job_run_record(?, ?, ?, ?, ?, ?, ?, @out_job_run_id)"), setter.capture());
        PreparedStatement ps = mock(PreparedStatement.class);
        setter.getValue().setValues(ps);
        verify(ps).setString(1, "weather");
        verify(ps).setString(2, "open-meteo-ca");
        verify(ps).setObject(3, started);
        verify(ps).setObject(4, finished);
        verify(ps).setString(5, "ok");
        verify(ps).setInt(6, 1150);
        verify(ps).setNull(7, Types.VARCHAR);
    }

    @Test
    void cleanOldWeatherDataCallsTheRetentionProcedure() {
        repository.cleanOldWeatherData();

        verify(jdbc).update("CALL sp_clean_old_weather_data(NULL)");
    }

    @Test
    void sqlFailureRuleIgnoresAProcedureRefusal() {
        SQLException refusal = new SQLException("unknown station mli", "45000", 1644);

        assertThat(SqlFailures.isSqlFailure(new UncategorizedSQLException("x", "x", refusal))).isFalse();
        assertThat(SqlFailures.isSqlFailure(new SQLException("Communications link failure", "08S01"))).isTrue();
        assertThat(SqlFailures.isSqlFailure(new IllegalStateException())).isFalse();
    }

    @Test
    void fallbacksWrapTheCause() {
        RuntimeException cause = new RuntimeException("boom");

        assertThatThrownBy(() -> repository.fallbackSave("MLI-1", "{}", WeatherSourceType.OPEN_METEO, cause))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("MLI-1")
                .hasCause(cause);
        assertThatThrownBy(() -> repository.fallbackRecord("open-ca", null, null, "ok", 1, null, cause))
                .hasCause(cause);
        assertThatThrownBy(() -> repository.fallbackProcedure(cause))
                .isInstanceOf(RuntimeException.class)
                .hasCause(cause);
    }
}
