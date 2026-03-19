package com.fishfind.water.repo;

import com.fishfind.water.domain.StationRef;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * Loads and updates station metadata stored in the {@code WaterStation} table.
 */
@Repository
public class WaterStationRepository {

    private final JdbcTemplate jdbc;

    /**
     * Creates a repository backed by Spring JDBC.
     *
     * @param jdbc JDBC template used for SQL operations
     */
    public WaterStationRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * Returns all supported Canadian stations that should be processed by the worker.
     *
     * @return list of supported station references
     */
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

    /**
     * Disables a station after repeated failures so future worker cycles skip it.
     *
     * @param mli station identifier to disable
     */
    public void disableStation(String mli) {
        jdbc.update("UPDATE WaterStation SET supported = 0 WHERE mli=?", mli);
    }
}
