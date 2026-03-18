package com.fishfind.water.repo;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class FailureRepository {

    private final JdbcTemplate jdbc;

    public FailureRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public int countToday(String mli) {
        Integer cnt = jdbc.queryForObject(
            "SELECT COUNT(*) FROM StationFailure WHERE mli=? AND CAST(stamp AS DATE)=CAST(GETDATE() AS DATE)",
            Integer.class,
            mli
        );
        return cnt == null ? 0 : cnt;
    }

    public void insert(String mli) {
        jdbc.update("INSERT INTO StationFailure(mli, stamp) VALUES(?, GETDATE())", mli);
    }
}
