package com.fishfind.docapi.repo;

import com.fishfind.docapi.domain.DocumentType;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;

/**
 * News document reads backed by the MySQL {@code news} table (Winhost, migrated 2026-08-31; see
 * {@code envfish-db/mysql/script02_Proc.sql} -> {@code sp_news_doc_get}).
 *
 * <p><strong>Read-only.</strong> Since docapi 1.16.0 news writes do not go through a
 * {@link DocumentStore}: {@code NewsDocumentService} overrides {@code add}/{@code update} and sends
 * them, parsed and validated, to {@link MySqlNewsWriteRepository}. The two write methods below only
 * exist because the interface requires them; they throw, so a future caller that bypasses the
 * service fails loudly instead of writing somewhere unexpected. Before 1.16.0 they delegated to a
 * SQL Server store, which was docapi's last path into {@code dbo.news}.
 */
public class MySqlNewsDocumentRepository implements DocumentStore {

    static final String GET_SQL = "CALL sp_news_doc_get(?)";

    private final JdbcTemplate mysqlJdbc;

    public MySqlNewsDocumentRepository(JdbcTemplate mysqlJdbc) {
        this.mysqlJdbc = mysqlJdbc;
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

    /** Never called -- news writes go through {@code NewsDocumentService}; see the class doc. */
    @Override
    public String addDocument(String json) {
        throw new UnsupportedOperationException(
                "news writes go through NewsDocumentService -> NewsWriteRepository, not the document store");
    }

    /** Never called -- news writes go through {@code NewsDocumentService}; see the class doc. */
    @Override
    public String updateDocument(String id, String json) {
        throw new UnsupportedOperationException(
                "news writes go through NewsDocumentService -> NewsWriteRepository, not the document store");
    }

    /**
     * Circuit-breaker fallback for reads: surfaces the failure as an unchecked exception.
     */
    @SuppressWarnings("unused")
    public String readFallback(String id, Throwable ex) {
        throw new RuntimeException("MySQL read failed for " + DocumentType.NEWS.label() + " document " + id, ex);
    }
}
