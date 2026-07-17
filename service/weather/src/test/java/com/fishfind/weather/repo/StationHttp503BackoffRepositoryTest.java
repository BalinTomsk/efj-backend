package com.fishfind.weather.repo;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.sql.ResultSet;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

@ExtendWith(MockitoExtension.class)
class StationHttp503BackoffRepositoryTest {

    @Mock
    private JdbcTemplate jdbc;

    @InjectMocks
    private StationHttp503BackoffRepository repository;

    @Test
    void recordHttp503CallsStoredProcedure() {
        LocalDate today = LocalDate.of(2026, 7, 17);

        repository.recordHttp503("weather-gov", "US", "06887500", "KS", today);

        verify(jdbc).update(
                "EXEC dbo.sp_weather_station_503_record ?, ?, ?, ?, ?",
                "weather-gov",
                "US",
                "06887500",
                "KS",
                today);
    }

    @Test
    void refreshDueCallsStoredProcedure() {
        LocalDate today = LocalDate.of(2026, 7, 17);

        repository.refreshDue(today);

        verify(jdbc).update("EXEC dbo.sp_weather_station_503_refresh_due ?", today);
    }

    @Test
    void resetCallsStoredProcedure() {
        repository.reset("weather-gov", "US", "06887500");

        verify(jdbc).update(
                "EXEC dbo.sp_weather_station_503_reset ?, ?, ?",
                "weather-gov",
                "US",
                "06887500");
    }

    @Test
    @SuppressWarnings("unchecked")
    void summaryByStateMapsStoredProcedureRows() throws Exception {
        when(jdbc.query(anyString(), org.mockito.ArgumentMatchers.any(RowMapper.class))).thenReturn(List.of(
                new StationHttp503BackoffRepository.BackoffSummary("KS", "WEEKLY", 2)));

        List<StationHttp503BackoffRepository.BackoffSummary> result = repository.summaryByState();

        assertThat(result).containsExactly(
                new StationHttp503BackoffRepository.BackoffSummary("KS", "WEEKLY", 2));

        ArgumentCaptor<RowMapper<StationHttp503BackoffRepository.BackoffSummary>> mapper =
                ArgumentCaptor.forClass(RowMapper.class);
        verify(jdbc).query(eq("EXEC dbo.sp_weather_station_503_summary_by_state"), mapper.capture());

        ResultSet rs = org.mockito.Mockito.mock(ResultSet.class);
        when(rs.getString("state")).thenReturn("WA");
        when(rs.getString("backoff_stage")).thenReturn("MONTHLY");
        when(rs.getLong("station_count")).thenReturn(4L);
        assertThat(mapper.getValue().mapRow(rs, 0))
                .isEqualTo(new StationHttp503BackoffRepository.BackoffSummary("WA", "MONTHLY", 4));
    }
}
