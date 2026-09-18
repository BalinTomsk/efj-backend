package com.fishfind.docapi.repo;

import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCallback;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.RowMapper;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Types;

/**
 * News-article writes against the MySQL {@code news} table (Winhost), through
 * {@code sp_news_doc_insert} / {@code sp_news_doc_update} ({@code envfish-db/mysql/script02_Proc.sql}).
 * These replace SQL Server's {@code dbo.sp_news_doc_add}, {@code dbo.sp_news_import} and
 * {@code dbo.sp_news_doc_update}, which were the last docapi paths into {@code dbo.news}.
 *
 * <p><strong>Typed parameters only.</strong> Parsing and validation happen before this class is
 * called ({@code NewsWriteParser}), so every exception thrown here is a genuine database fault. That
 * matters because this bean shares the {@code sqlBreaker} with every other repository: a client
 * sending a blank title must get a 400, not count toward opening the breaker on the whole API.
 *
 * <p>Like {@link MySqlNewsAdminCommandRepository}, results are read by draining every result set:
 * each procedure runs DML before its single result-row {@code SELECT}, and
 * {@code executeQuery()} cannot be trusted to step over the DML's update count first.
 *
 * <p>The app's MySQL account ({@code portos}) has no {@code INSERT}/{@code UPDATE}; both procedures
 * run with their definer's rights, and {@code portos} holds {@code EXECUTE}. They were created from
 * the Winhost control panel on 2026-09-18 (definitions in {@code envfish-db/mysql/script02_Proc.sql}).
 */
public class MySqlNewsWriteRepository implements NewsWriteRepository {

    static final String INSERT_SQL =
            "CALL sp_news_doc_insert(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";
    static final String UPDATE_SQL =
            "CALL sp_news_doc_update(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";

    private final JdbcTemplate mysqlJdbc;

    public MySqlNewsWriteRepository(JdbcTemplate mysqlJdbc) {
        this.mysqlJdbc = mysqlJdbc;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "insertFallback")
    public String insert(NewsWrite write) {
        String id = executeReturningOneRow(INSERT_SQL, ps -> {
            int i = bindFields(ps, 1, write);
            i = bindPhoto(ps, i, write.photo0());
            i = bindPhoto(ps, i, write.photo1());
            bindPhoto(ps, i, write.photo2());
        }, (rs, rowNum) -> rs.getString("news_id"));
        if (id == null) {
            throw new IllegalStateException("sp_news_doc_insert returned no id");
        }
        return id;
    }

    /** Circuit-breaker fallback for {@link #insert}. */
    @SuppressWarnings("unused")
    public String insertFallback(NewsWrite write, Throwable ex) {
        throw new RuntimeException("MySQL news insert failed", ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "updateFallback")
    public boolean update(String id, NewsWrite write) {
        Boolean found = executeReturningOneRow(UPDATE_SQL, ps -> {
            ps.setString(1, id);
            int i = bindFields(ps, 2, write);
            bindPhoto(ps, i, write.photo0());
        }, (rs, rowNum) -> rs.getInt("found") == 1);
        return Boolean.TRUE.equals(found);
    }

    /** Circuit-breaker fallback for {@link #update}. */
    @SuppressWarnings("unused")
    public boolean updateFallback(String id, NewsWrite write, Throwable ex) {
        throw new RuntimeException("MySQL news update failed for id " + id, ex);
    }

    /**
     * Binds the fifteen shared columns in the procedures' common order -- title through fish3 -- and
     * returns the next free parameter index.
     */
    private static int bindFields(PreparedStatement ps, int start, NewsWrite w) throws SQLException {
        int i = start;
        ps.setString(i++, w.title());
        setNullableString(ps, i++, w.author());
        setNullableString(ps, i++, w.authorLink());
        setNullableString(ps, i++, w.source());
        setNullableString(ps, i++, w.sourceLink());
        setNullableString(ps, i++, w.videoLink());
        setNullableString(ps, i++, w.paragraph0());
        setNullableString(ps, i++, w.paragraph1());
        setNullableString(ps, i++, w.paragraph2());
        setNullableString(ps, i++, w.country());
        if (w.stamp() == null) {
            ps.setNull(i++, Types.TIMESTAMP);
        } else {
            ps.setTimestamp(i++, w.stamp());
        }
        setNullableString(ps, i++, w.lakeId());
        setNullableString(ps, i++, w.fish1Id());
        setNullableString(ps, i++, w.fish2Id());
        setNullableString(ps, i++, w.fish3Id());
        return i;
    }

    /** Binds one photo slot as (bytes, author, alt) and returns the next free parameter index. */
    private static int bindPhoto(PreparedStatement ps, int start, NewsWrite.Photo photo) throws SQLException {
        int i = start;
        if (photo.bytes() == null) {
            ps.setNull(i++, Types.LONGVARBINARY);
        } else {
            ps.setBytes(i++, photo.bytes());
        }
        setNullableString(ps, i++, photo.author());
        setNullableString(ps, i++, photo.alt());
        return i;
    }

    private static void setNullableString(PreparedStatement ps, int index, String value) throws SQLException {
        if (value == null) {
            ps.setNull(index, Types.VARCHAR);
        } else {
            ps.setString(index, value);
        }
    }

    /**
     * Runs a {@code CALL} whose body executes DML before its single result-row {@code SELECT},
     * draining every intermediate result and returning the first row of the first real result set
     * (or {@code null} if none was produced). Same shape as {@link MySqlNewsAdminCommandRepository}.
     */
    private <T> T executeReturningOneRow(String sql, PreparedStatementSetter binder, RowMapper<T> mapper) {
        return mysqlJdbc.execute(sql, (PreparedStatementCallback<T>) ps -> {
            binder.setValues(ps);
            T result = null;
            int rowNum = 0;
            boolean hasResults = ps.execute();
            while (hasResults || ps.getUpdateCount() != -1) {
                if (hasResults) {
                    try (ResultSet rs = ps.getResultSet()) {
                        if (result == null && rs != null && rs.next()) {
                            result = mapper.mapRow(rs, rowNum++);
                        }
                        while (rs != null && rs.next()) {
                            // drain any remaining rows so MySQL can finish the procedure cleanly
                        }
                    }
                }
                hasResults = ps.getMoreResults(Statement.CLOSE_CURRENT_RESULT);
            }
            return result;
        });
    }
}
