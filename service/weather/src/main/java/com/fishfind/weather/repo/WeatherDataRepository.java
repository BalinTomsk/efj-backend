package com.fishfind.weather.repo;

import com.fishfind.weather.config.SqlFailures;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Types;
import java.time.LocalDateTime;

/**
 * Persists weather payloads into the MySQL {@code envdata} database through its procedures
 * ({@code envfish-db/mysql/envdata/script02_Proc.sql}; no table is touched directly), records each finished cycle in
 * {@code job_run} and runs the weather retention. A functional copy of the C# twin's {@code WeatherDataRepository}
 * (11.0.0).
 *
 * <p>Until 1.18.0 this wrote {@code dbo.ows_meteo} on SQL Server with a raw {@code UPDATE} and a trigger shredded it;
 * {@code sp_weather_save} now does both in one call, and stores pressure in mm Hg.
 */
@Repository
public class WeatherDataRepository {
    private static final Logger log = LoggerFactory.getLogger(WeatherDataRepository.class);

    /** {@code job_run.service} of this service's cycles (the same as the C# twin's). */
    public static final String SERVICE_NAME = "weather";

    static final String SAVE = "CALL sp_weather_save(?, ?, ?, @out_days)";
    static final String SAVED_DAYS = "SELECT @out_days";
    static final String RECORD_CYCLE = "CALL sp_job_run_record(?, ?, ?, ?, ?, ?, ?, @out_job_run_id)";
    static final String CLEAN_OLD = "CALL sp_clean_old_weather_data(NULL)";

    private final JdbcTemplate jdbc;

    public WeatherDataRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * Stores one station's payload and the PROVIDER that produced it ({@code sp_weather_save(mli, type, json)}): the
     * raw document is kept in {@code weather_raw} (newest per station), and a canonical
     * {@code fishfind.weather.forecast/v1} envelope is shredded into {@code weather_day} (one row per date;
     * {@code pressureHpa} converted to mm Hg). A blank payload is a no-op. A station envdata does not know
     * (SQLSTATE 45000) is logged and the payload dropped, as an unmatched {@code ows_meteo} row was before; it is
     * caught here, so it is neither retried nor counted by the breaker.
     *
     * @param sourceType provider identity; see {@code WeatherSourceType}
     */
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fallbackSave")
    public void saveStationData(String mli, String jsonData, int sourceType) {
        if (mli == null || mli.isBlank()) {
            throw new IllegalArgumentException("mli must not be null or blank");
        }
        if (jsonData == null || jsonData.isBlank()) {
            return;
        }

        Integer days;
        try {
            // The OUT parameter is read as a session variable on the SAME connection: the EXECUTE-only account may not
            // read the procedure metadata a CallableStatement OUT parameter needs (same as the C# twin).
            days = jdbc.execute((ConnectionCallback<Integer>) connection -> {
                try (PreparedStatement call = connection.prepareStatement(SAVE)) {
                    call.setString(1, mli);
                    call.setInt(2, sourceType);
                    call.setString(3, jsonData);
                    call.execute();
                }
                try (Statement select = connection.createStatement(); ResultSet rs = select.executeQuery(SAVED_DAYS)) {
                    if (!rs.next()) {
                        return null;
                    }
                    int value = rs.getInt(1);
                    return rs.wasNull() ? null : value;
                }
            });
        } catch (DataAccessException ex) {
            if (SqlFailures.isProcedureRefusal(ex)) {
                log.warn("Station unknown to envdata; payload dropped. mli={} bytes={}", mli, jsonData.length());
                return;
            }
            throw ex;
        }

        if (days == null || days < 0) {
            log.warn("Payload stored but not shredded (not a fishfind.weather.forecast/v1 envelope). "
                    + "mli={} type={} bytes={}", mli, sourceType, jsonData.length());
        }
    }

    /**
     * Records one finished cycle in envdata's {@code job_run} ({@code sp_job_run_record}). env_service picks unhanded
     * cycles up and does the fish hand-over to SQL Server, which this service did itself until 1.18.0.
     */
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fallbackRecord")
    public void recordCycle(String job, LocalDateTime startedUtc, LocalDateTime finishedUtc, String status,
                            int items, String note) {
        jdbc.update(RECORD_CYCLE, ps -> {
            ps.setString(1, SERVICE_NAME);
            ps.setString(2, job);
            ps.setObject(3, startedUtc);
            ps.setObject(4, finishedUtc);
            ps.setString(5, status);
            ps.setInt(6, items);
            if (note == null) {
                ps.setNull(7, Types.VARCHAR);
            } else {
                ps.setString(7, note.length() > 255 ? note.substring(0, 255) : note);
            }
        });
    }

    /** Weather retention: {@code sp_clean_old_weather_data(NULL)} deletes days older than 15 days back. */
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fallbackProcedure")
    public void cleanOldWeatherData() {
        jdbc.update(CLEAN_OLD);
    }

    /** Must mirror {@link #saveStationData}'s parameters plus the throwable, or resilience4j cannot bind it. */
    @SuppressWarnings("unused")
    public void fallbackSave(String mli, String jsonData, int sourceType, Throwable ex) {
        throw new RuntimeException("SQL save failed for station " + mli, ex);
    }

    @SuppressWarnings("unused")
    public void fallbackRecord(String job, LocalDateTime startedUtc, LocalDateTime finishedUtc, String status,
                               int items, String note, Throwable ex) {
        throw new RuntimeException("Recording cycle " + job + " in job_run failed", ex);
    }

    @SuppressWarnings("unused")
    public void fallbackProcedure(Throwable ex) {
        throw new RuntimeException("SQL stored procedure execution failed", ex);
    }
}
