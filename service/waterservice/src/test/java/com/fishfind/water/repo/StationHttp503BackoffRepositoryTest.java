package com.fishfind.water.repo;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.sql.ResultSet;
import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class StationHttp503BackoffRepositoryTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final StationHttp503BackoffRepository repository = new StationHttp503BackoffRepository(jdbc);

    @Test
    void recordHttp503CallsStoredProcedure() {
        LocalDate today = LocalDate.of(2026, 7, 18);

        repository.recordHttp503("usgs", "US", "08313000", "NY", today);

        verify(jdbc).update(
                "EXEC dbo.sp_water_station_503_record ?, ?, ?, ?, ?",
                "usgs",
                "US",
                "08313000",
                "NY",
                today);
    }

    @Test
    void refreshDueCallsStoredProcedure() {
        LocalDate today = LocalDate.of(2026, 7, 18);

        repository.refreshDue(today);

        verify(jdbc).update("EXEC dbo.sp_water_station_503_refresh_due ?", today);
    }

    @Test
    void resetCallsStoredProcedure() {
        repository.reset("environment-canada", "CA", "02JE025");

        verify(jdbc).update(
                "EXEC dbo.sp_water_station_503_reset ?, ?, ?",
                "environment-canada",
                "CA",
                "02JE025");
    }

    @Test
    @SuppressWarnings("unchecked")
    void summaryByStateMapsStoredProcedureRows() throws Exception {
        when(jdbc.query(anyString(), any(RowMapper.class))).thenReturn(List.of(
                new StationHttp503BackoffRepository.BackoffSummary("QC", "WEEKLY", 2)));

        List<StationHttp503BackoffRepository.BackoffSummary> result = repository.summaryByState();

        assertEquals(List.of(new StationHttp503BackoffRepository.BackoffSummary("QC", "WEEKLY", 2)), result);

        ArgumentCaptor<RowMapper<StationHttp503BackoffRepository.BackoffSummary>> mapper =
                ArgumentCaptor.forClass(RowMapper.class);
        verify(jdbc).query(eq("EXEC dbo.sp_water_station_503_summary_by_state"), mapper.capture());

        ResultSet rs = mock(ResultSet.class);
        when(rs.getString("state")).thenReturn("WA");
        when(rs.getString("backoff_stage")).thenReturn("MONTHLY");
        when(rs.getLong("station_count")).thenReturn(4L);

        assertEquals(
                new StationHttp503BackoffRepository.BackoffSummary("WA", "MONTHLY", 4),
                mapper.getValue().mapRow(rs, 0));
    }
}
