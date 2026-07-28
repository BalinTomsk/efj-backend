package com.fishfind.docapi.repo;

import com.fishfind.docapi.domain.DocumentType;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCallback;

import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.List;

/**
 * SQL Server-backed {@link DocumentStore} for a single entity's JSON documents. Wired only under the
 * {@code jdbc} Spring profile (see {@code JdbcStoreConfig}); the default profile uses
 * {@link InMemoryDocumentStore} so the service runs with no database.
 *
 * <p>Each concrete subclass binds three per-entity SQL statements (supplied to the constructor):
 * <ul>
 *   <li><b>get</b> — a scalar {@code SELECT dbo.fn_&lt;entity&gt;_doc(?)} returning the document as a
 *       JSON string (or {@code NULL} when the id is unknown);</li>
 *   <li><b>add</b> — {@code EXEC dbo.sp_&lt;entity&gt;_doc_add ?} taking the JSON body and returning the
 *       new document id as a single scalar;</li>
 *   <li><b>update</b> — {@code EXEC dbo.sp_&lt;entity&gt;_doc_update ?, ?} taking the id and JSON body and
 *       returning the affected id as a single scalar.</li>
 * </ul>
 *
 * <p>Reads go through a JSON <em>function</em> and writes through <em>procedures</em>, matching the
 * platform convention that application code never touches base tables directly. The id is passed as a
 * string and left to SQL Server to convert to the column's real type (int / {@code uniqueidentifier}),
 * so this layer stays agnostic to each entity's key type.
 *
 * <p>Resilience4j retry ({@code sqlRetry}) and circuit breaker ({@code sqlBreaker}) are applied to every
 * SQL call, exactly as in {@code waterservice}.
 */
public abstract class JdbcDocumentRepository implements DocumentStore {

    private final JdbcTemplate jdbc;
    private final DocumentType type;
    private final String getSql;
    private final String addSql;
    private final String updateSql;

    /**
     * @param jdbc JDBC template used for SQL operations
     * @param type the entity kind this repository serves (for messages/logging)
     * @param getSql scalar SELECT returning the document JSON for a given id
     * @param addSql EXEC statement inserting a new document and returning its id
     * @param updateSql EXEC statement updating an existing document and returning its id
     */
    protected JdbcDocumentRepository(JdbcTemplate jdbc, DocumentType type,
                                     String getSql, String addSql, String updateSql) {
        this.jdbc = jdbc;
        this.type = type;
        this.getSql = getSql;
        this.addSql = addSql;
        this.updateSql = updateSql;
    }

    /**
     * Returns the stored JSON document for an id, or {@code null} when no such document exists.
     *
     * @param id the entity id (string form; SQL Server converts to the real key type)
     * @return the document as a JSON string, or {@code null} if not found
     */
    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "readFallback")
    public String getDocument(String id) {
        List<String> rows = jdbc.query(
                getSql,
                (ps) -> ps.setString(1, id),
                (rs, i) -> rs.getString(1));
        return rows.isEmpty() ? null : rows.get(0);
    }

    /**
     * Inserts a new document and returns the id assigned by the stored procedure.
     *
     * @param json a well-formed JSON body (validated upstream)
     * @return the new document id as a string, or {@code null} if the procedure returns nothing
     */
    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "addFallback")
    public String addDocument(String json) {
        return executeReturningScalar(addSql, ps -> ps.setString(1, json));
    }

    /**
     * Updates an existing document and returns the id reported by the stored procedure.
     *
     * @param id the entity id to update
     * @param json a well-formed JSON body (validated upstream)
     * @return the affected document id as a string, or {@code null} if the procedure returns nothing
     */
    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "updateFallback")
    public String updateDocument(String id, String json) {
        return executeReturningScalar(updateSql, ps -> {
            ps.setString(1, id);
            ps.setString(2, json);
        });
    }

    /**
     * Executes a write procedure that may return the affected id as a single scalar and may also emit
     * incidental update counts or extra result sets (drained so the driver can complete cleanly).
     *
     * @param sql the {@code EXEC} statement to run
     * @param binder binds the statement's parameters
     * @return the first column of the first result row, as a string, or {@code null} when absent
     */
    private String executeReturningScalar(String sql, ParameterBinder binder) {
        return jdbc.execute(sql, (PreparedStatementCallback<String>) ps -> {
            binder.bind(ps);
            String scalar = null;
            boolean hasResults = ps.execute();
            while (hasResults || ps.getUpdateCount() != -1) {
                if (hasResults) {
                    try (var rs = ps.getResultSet()) {
                        if (scalar == null && rs != null && rs.next()) {
                            scalar = rs.getString(1);
                        }
                        // Drain any remaining rows so SQL Server can finish the procedure cleanly.
                        while (rs != null && rs.next()) {
                            // no-op
                        }
                    }
                }
                hasResults = ps.getMoreResults(Statement.CLOSE_CURRENT_RESULT);
            }
            return scalar;
        });
    }

    /**
     * Circuit-breaker fallback for reads: surfaces the failure as an unchecked exception.
     *
     * @param id the id that failed to load
     * @param ex the original SQL-related exception
     * @return never returns
     */
    @SuppressWarnings("unused")
    public String readFallback(String id, Throwable ex) {
        throw new RuntimeException("SQL read failed for " + type.label() + " document " + id, ex);
    }

    /**
     * Circuit-breaker fallback for inserts.
     *
     * @param json the body that failed to save
     * @param ex the original SQL-related exception
     * @return never returns
     */
    @SuppressWarnings("unused")
    public String addFallback(String json, Throwable ex) {
        throw new RuntimeException("SQL insert failed for " + type.label() + " document", ex);
    }

    /**
     * Circuit-breaker fallback for updates.
     *
     * @param id the id that failed to update
     * @param json the body that failed to save
     * @param ex the original SQL-related exception
     * @return never returns
     */
    @SuppressWarnings("unused")
    public String updateFallback(String id, String json, Throwable ex) {
        throw new RuntimeException("SQL update failed for " + type.label() + " document " + id, ex);
    }

    /**
     * Binds parameters onto a prepared statement, allowing a checked {@link SQLException}.
     */
    @FunctionalInterface
    private interface ParameterBinder {
        void bind(PreparedStatement ps) throws SQLException;
    }
}
