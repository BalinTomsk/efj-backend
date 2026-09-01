package com.fishfind.docapi.repo;

import com.fishfind.docapi.domain.DocumentType;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;

/**
 * News document reads backed by the MySQL {@code news} table (Winhost, migrated 2026-08-31; see
 * {@code envfish-db/mysql/script02_Proc.sql} -> {@code sp_news_doc_get}). Writes stay on the
 * SQL-Server-backed delegate: {@code sp_news_doc_add}/{@code sp_news_doc_update} and the admin
 * edit flow haven't moved, and this MySQL database currently backs only reads for News.aspx /
 * docapi's read endpoints.
 */
public class MySqlNewsDocumentRepository implements DocumentStore {

    static final String GET_SQL = "CALL sp_news_doc_get(?)";

    private final JdbcTemplate mysqlJdbc;
    private final DocumentStore sqlServerDelegate;

    public MySqlNewsDocumentRepository(JdbcTemplate mysqlJdbc, DocumentStore sqlServerDelegate) {
        this.mysqlJdbc = mysqlJdbc;
        this.sqlServerDelegate = sqlServerDelegate;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "readFallback")
    public String getDocument(String id) {
        List<String> rows = mysqlJdbc.query(
                GET_SQL,
                ps -> ps.setString(1, id),
                (rs, i) -> rs.getString(1));
        return rows.isEmpty() ? null : rows.get(0);
    }

    /** Not in scope for the MySQL move -- delegates to the SQL-Server-backed store unchanged. */
    @Override
    public String addDocument(String json) {
        return sqlServerDelegate.addDocument(json);
    }

    /** Not in scope for the MySQL move -- delegates to the SQL-Server-backed store unchanged. */
    @Override
    public String updateDocument(String id, String json) {
        return sqlServerDelegate.updateDocument(id, json);
    }

    /**
     * Circuit-breaker fallback for reads: surfaces the failure as an unchecked exception.
     */
    @SuppressWarnings("unused")
    public String readFallback(String id, Throwable ex) {
        throw new RuntimeException("MySQL read failed for " + DocumentType.NEWS.label() + " document " + id, ex);
    }
}
