package com.fishfind.water.repo;

import com.fishfind.water.domain.StationRef;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public class WaterStationRepository {

    private final JdbcTemplate jdbc;

    public WaterStationRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<StationRef> findSupported() {
        return jdbc.query(
            "SELECT mli, state, ISNULL(tz,0) tz FROM WaterStation WHERE country = 'CA' AND supported = 1",
            (rs, i) -> new StationRef(
                rs.getString("mli"),
                rs.getString("state"),
                rs.getInt("tz")
            )
        );
    }

    public void disableStation(String mli) {
        jdbc.update("UPDATE WaterStation SET supported = 0 WHERE mli=?", mli);
    }
}
