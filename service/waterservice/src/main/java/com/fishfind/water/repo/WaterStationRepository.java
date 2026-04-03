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
     * Returns all supported stations for the requested country that should be processed by the worker.
     *
     * @param country country code used to filter stations
     * @return list of supported station references
     */
    public List<StationRef> findSupported(String country) {
        return jdbc.query(
            "SELECT mli, state, tz FROM vwWaterStation WHERE country = ?",
            (ps) -> ps.setString(1, country),
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
        jdbc.update("EXEC dbo.sp_DisableWaterStation ?", mli);
    }
}
