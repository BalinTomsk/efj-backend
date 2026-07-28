package com.fishfind.docapi.repo;

import com.fishfind.docapi.domain.DocumentType;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * JSON-document access for news articles (SQL Server backing, {@code jdbc} profile only).
 *
 * <p>DB contract (to be created in {@code envfish-db}): {@code dbo.fn_news_doc(@id)} returns the article
 * as JSON; {@code dbo.sp_news_doc_add(@json)} inserts and returns the new id;
 * {@code dbo.sp_news_doc_update(@id, @json)} updates and returns the id.
 */
public class NewsDocumentRepository extends JdbcDocumentRepository {

    static final String GET_SQL = "SELECT dbo.fn_news_doc(?)";
    static final String ADD_SQL = "EXEC dbo.sp_news_doc_add ?";
    static final String UPDATE_SQL = "EXEC dbo.sp_news_doc_update ?, ?";

    public NewsDocumentRepository(JdbcTemplate jdbc) {
        super(jdbc, DocumentType.NEWS, GET_SQL, ADD_SQL, UPDATE_SQL);
    }
}
