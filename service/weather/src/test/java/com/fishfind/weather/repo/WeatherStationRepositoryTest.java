package com.fishfind.weather.repo;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.fishfind.weather.domain.StationRef;
import java.sql.ResultSet;
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
class WeatherStationRepositoryTest {

    @Mock
    private JdbcTemplate jdbc;

    @InjectMocks
    private WeatherStationRepository repository;

    @Test
    @SuppressWarnings("unchecked")
    void queriesSupportedStationsWithExpectedSqlAndCountryParameter() {
        StationRef expected = new StationRef("MLI-1", 1.0, 2.0, "WA");
        when(jdbc.query(anyString(), any(RowMapper.class), eq(1400), eq("CA"))).thenReturn(List.of(expected));

        List<StationRef> result = repository.findSupportedStations("CA");

        assertThat(result).containsExactly(expected);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<RowMapper<StationRef>> mapper = ArgumentCaptor.forClass(RowMapper.class);
        org.mockito.Mockito.verify(jdbc).query(sql.capture(), mapper.capture(), eq(1400), eq("CA"));

        assertThat(sql.getValue())
                .contains("SELECT TOP (?)")
                .contains("dbo.vwWeatherForecastToDay")
                .contains("country = ?");
    }

    @Test
    @SuppressWarnings("unchecked")
    void usStationsAreCappedAtWeatherGovLimit() {
        when(jdbc.query(anyString(), any(RowMapper.class), eq(900), eq("US"))).thenReturn(List.of());

        repository.findSupportedUsStations();

        org.mockito.Mockito.verify(jdbc).query(anyString(), any(RowMapper.class), eq(900), eq("US"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void rowMapperMapsAllColumns() throws Exception {
        when(jdbc.query(anyString(), any(RowMapper.class), eq(900), eq("US"))).thenReturn(List.of());
        repository.findSupportedUsStations();

        ArgumentCaptor<RowMapper<StationRef>> mapper = ArgumentCaptor.forClass(RowMapper.class);
        org.mockito.Mockito.verify(jdbc).query(anyString(), mapper.capture(), eq(900), eq("US"));

        ResultSet rs = mock(ResultSet.class);
        when(rs.getString("mli")).thenReturn("MLI-9");
        when(rs.getDouble("lat")).thenReturn(47.5);
        when(rs.getDouble("lon")).thenReturn(-122.3);
        when(rs.getString("state")).thenReturn("WA");

        StationRef mapped = mapper.getValue().mapRow(rs, 0);

        assertThat(mapped).isEqualTo(new StationRef("MLI-9", 47.5, -122.3, "WA"));
    }
}
