package com.fishfind.water.repo;

import com.fishfind.water.domain.StationRef;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.RowMapper;

import java.sql.ResultSet;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WaterStationRepositoryTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final WaterStationRepository repository = new WaterStationRepository(jdbc);

    @Test
    void findSupportedMapsRowsToStationRefs() throws Exception {
        when(jdbc.query(any(String.class), any(PreparedStatementSetter.class), any(RowMapper.class))).thenAnswer(invocation -> {
            @SuppressWarnings("unchecked")
            RowMapper<StationRef> mapper = invocation.getArgument(2);
            ResultSet rs = mock(ResultSet.class);
            when(rs.getString("mli")).thenReturn("02JE025");
            when(rs.getString("state")).thenReturn("QC");
            when(rs.getInt("tz")).thenReturn(-5);
            return List.of(mapper.mapRow(rs, 0));
        });

        List<StationRef> stations = repository.findSupported("CA");

        assertEquals(List.of(new StationRef("02JE025", "QC", -5)), stations);
        verify(jdbc).query(
                eq("SELECT mli, state, tz FROM vwWaterStation WHERE country = ?"),
                any(PreparedStatementSetter.class),
                any(RowMapper.class)
        );
    }
}
