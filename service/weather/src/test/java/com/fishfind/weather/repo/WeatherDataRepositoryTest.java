package com.fishfind.weather.repo;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCallback;

@ExtendWith(MockitoExtension.class)
class WeatherDataRepositoryTest {

    @Mock
    private JdbcTemplate jdbc;

    @InjectMocks
    private WeatherDataRepository repository;

    @Test
    void saveStationDataUpdatesRowWithExpectedSql() {
        repository.saveStationData("MLI-1", "{\"x\":1}");

        verify(jdbc).update(
                "UPDATE dbo.ows_meteo SET type = ?, ows = ?, stamp = GETDATE() WHERE mli = ?",
                2,
                "{\"x\":1}",
                "MLI-1");
    }

    @Test
    void saveStationDataRejectsBlankMli() {
        assertThatThrownBy(() -> repository.saveStationData("  ", "{}"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> repository.saveStationData(null, "{}"))
                .isInstanceOf(IllegalArgumentException.class);
        verifyNoInteractions(jdbc);
    }

    @Test
    void saveStationDataSkipsBlankPayload() {
        repository.saveStationData("MLI-1", "   ");
        repository.saveStationData("MLI-1", null);

        verify(jdbc, never()).update(anyString(), any(), any(), any());
    }

    @Test
    void pushSpeciesProcedureExecutesAndDrainsResultSets() throws Exception {
        ResultSet rs = org.mockito.Mockito.mock(ResultSet.class);
        PreparedStatement ps = org.mockito.Mockito.mock(PreparedStatement.class);
        // One result set, then nothing more.
        when(ps.execute()).thenReturn(true);
        when(ps.getResultSet()).thenReturn(rs);
        when(ps.getMoreResults(Statement.CLOSE_CURRENT_RESULT)).thenReturn(false);
        when(ps.getUpdateCount()).thenReturn(-1);

        when(jdbc.execute(eq("EXEC dbo.spPushSpeciesFromLakeToStation"), any(PreparedStatementCallback.class)))
                .thenAnswer(inv -> ((PreparedStatementCallback<?>) inv.getArgument(1)).doInPreparedStatement(ps));

        repository.pushSpeciesFromLakeToStation();

        verify(ps).execute();
        verify(rs).close();
    }

    @Test
    void totalUpdateProbabilityExecutesProcedure() {
        when(jdbc.execute(eq("EXEC dbo.spTotalUpdateProbability"), any(PreparedStatementCallback.class)))
                .thenReturn(null);

        repository.totalUpdateProbability();

        verify(jdbc).execute(eq("EXEC dbo.spTotalUpdateProbability"), any(PreparedStatementCallback.class));
    }

    @Test
    void fallbackSaveWrapsCause() {
        RuntimeException cause = new RuntimeException("boom");

        assertThatThrownBy(() -> repository.fallbackSave("MLI-1", "{}", cause))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("MLI-1")
                .hasCause(cause);
    }

    @Test
    void fallbackProcedureWrapsCause() {
        RuntimeException cause = new RuntimeException("boom");

        assertThatThrownBy(() -> repository.fallbackProcedure(cause))
                .isInstanceOf(RuntimeException.class)
                .hasCause(cause);
    }
}
