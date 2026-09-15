package com.fishfind.docapi.repo;

import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.CallableStatementCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCallback;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.RowMapper;

import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Types;

/**
 * News-admin writes backed by the MySQL {@code news} table (Winhost) -- see
 * {@code envfish-db/mysql/script02_Proc.sql} for {@code sp_news_admin_draft_create} /
 * {@code sp_news_admin_publish} / {@code sp_news_admin_photo_update}, and that file's header for why
 * the app's {@code portos} credential cannot create these procedures itself (no {@code CREATE
 * ROUTINE}) even though it can {@code EXECUTE} them once created via the Winhost control panel.
 *
 * <p>{@code publish}/{@code updatePhoto} use the same "drain every result set manually" pattern as
 * {@link JdbcRiverFishCommandRepository}/{@link JdbcRiverDescriptionCommandRepository}: each
 * procedure's body runs DML before its single result-row {@code SELECT}, and a plain
 * {@code PreparedStatement.executeQuery()} cannot be trusted to skip over the DML's update count
 * first. This is standard JDBC, not MSSQL-specific, so the same shape works unchanged against
 * MySQL Connector/J.
 */
public class MySqlNewsAdminCommandRepository implements NewsAdminCommandRepository {

    static final String DRAFT_CREATE_SQL = "{call sp_news_admin_draft_create(?)}";
    static final String PUBLISH_SQL = "CALL sp_news_admin_publish(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";
    static final String PHOTO_UPDATE_SQL = "CALL sp_news_admin_photo_update(?,?,?,?,?)";

    private final JdbcTemplate mysqlJdbc;

    public MySqlNewsAdminCommandRepository(JdbcTemplate mysqlJdbc) {
        this.mysqlJdbc = mysqlJdbc;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "createDraftFallback")
    public String createDraft() {
        return mysqlJdbc.execute(DRAFT_CREATE_SQL, (CallableStatementCallback<String>) cs -> {
            cs.registerOutParameter(1, Types.CHAR);
            cs.execute();
            return cs.getString(1);
        });
    }

    /** Circuit-breaker fallback for {@link #createDraft}. */
    @SuppressWarnings("unused")
    public String createDraftFallback(Throwable ex) {
        throw new RuntimeException("MySQL news-admin draft create failed", ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "publishFallback")
    public PublishResult publish(NewsAdminPublishRequest request) {
        return executeReturningOneRow(PUBLISH_SQL, ps -> {
            int i = 1;
            ps.setString(i++, request.newsId());
            ps.setString(i++, request.title());
            ps.setString(i++, request.author());
            ps.setString(i++, request.source());
            ps.setString(i++, request.sourceLink());
            ps.setString(i++, request.authorLink());
            if (request.stamp() == null) {
                ps.setNull(i++, Types.TIMESTAMP);
            } else {
                ps.setTimestamp(i++, request.stamp());
            }
            ps.setString(i++, request.videoLink());
            ps.setString(i++, request.paragraph0());
            ps.setString(i++, request.paragraph1());
            ps.setString(i++, request.paragraph2());
            ps.setString(i++, request.country());
            ps.setString(i++, request.lakeId());
            ps.setString(i++, request.fish1Id());
            ps.setString(i++, request.fish2Id());
            ps.setString(i, request.fish3Id());
        }, (rs, rowNum) -> new PublishResult(rs.getString("news_id"), rs.getString("action")));
    }

    /** Circuit-breaker fallback for {@link #publish}. */
    @SuppressWarnings("unused")
    public PublishResult publishFallback(NewsAdminPublishRequest request, Throwable ex) {
        throw new RuntimeException("MySQL news-admin publish failed for id " + request.newsId(), ex);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "updatePhotoFallback")
    public PhotoUpdateResult updatePhoto(String newsId, int index, byte[] photo, String author, String alt) {
        PhotoUpdateResult result = executeReturningOneRow(PHOTO_UPDATE_SQL, ps -> {
            ps.setString(1, newsId);
            ps.setInt(2, index);
            ps.setBytes(3, photo);
            if (author == null) {
                ps.setNull(4, Types.VARCHAR);
            } else {
                ps.setString(4, author);
            }
            if (alt == null) {
                ps.setNull(5, Types.VARCHAR);
            } else {
                ps.setString(5, alt);
            }
        }, (rs, rowNum) -> new PhotoUpdateResult(rs.getBoolean("found"), rs.getBoolean("updated")));

        return result == null ? new PhotoUpdateResult(false, false) : result;
    }

    /** Circuit-breaker fallback for {@link #updatePhoto}. */
    @SuppressWarnings("unused")
    public PhotoUpdateResult updatePhotoFallback(String newsId, int index, byte[] photo, String author,
                                                 String alt, Throwable ex) {
        throw new RuntimeException("MySQL news-admin photo update failed for id " + newsId, ex);
    }

    /**
     * Runs a {@code CALL} whose procedure body may execute DML before its single result-row
     * {@code SELECT}, draining every intermediate result via {@code getMoreResults()} and returning
     * the first row of the first real result set (or {@code null} if none was produced).
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
