package com.fishfind.docapi.repo;

import com.fishfind.docapi.domain.DocumentType;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * JSON-document access for water bodies (the legacy {@code dbo.lake} entity; SQL Server backing,
 * {@code jdbc} profile only).
 *
 * <p>DB contract (to be created in {@code envfish-db}): {@code dbo.fn_waterbody_doc(@id)} returns the
 * water body as JSON; {@code dbo.sp_waterbody_doc_add(@json)} inserts and returns the new id;
 * {@code dbo.sp_waterbody_doc_update(@id, @json)} updates and returns the id.
 */
public class WaterbodyDocumentRepository extends JdbcDocumentRepository {

    static final String GET_SQL = "SELECT dbo.fn_waterbody_doc(?)";
    static final String ADD_SQL = "EXEC dbo.sp_waterbody_doc_add ?";
    static final String UPDATE_SQL = "EXEC dbo.sp_waterbody_doc_update ?, ?";

    public WaterbodyDocumentRepository(JdbcTemplate jdbc) {
        super(jdbc, DocumentType.WATERBODY, GET_SQL, ADD_SQL, UPDATE_SQL);
    }
}
