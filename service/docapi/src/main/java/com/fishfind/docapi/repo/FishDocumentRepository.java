package com.fishfind.docapi.repo;

import com.fishfind.docapi.domain.DocumentType;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * JSON-document access for fish species (SQL Server backing, {@code jdbc} profile only).
 *
 * <p>DB contract (to be created in {@code envfish-db}): {@code dbo.fn_fish_doc(@id)} returns the species
 * as JSON; {@code dbo.sp_fish_doc_add(@json)} inserts and returns the new id;
 * {@code dbo.sp_fish_doc_update(@id, @json)} updates and returns the id. Distinct from the existing
 * {@code dbo.fn_fish_document} / {@code dbo.sp_add_fish_document} objects, which manage a PDF blob, not
 * the species JSON.
 */
public class FishDocumentRepository extends JdbcDocumentRepository {

    static final String GET_SQL = "SELECT dbo.fn_fish_doc(?)";
    static final String ADD_SQL = "EXEC dbo.sp_fish_doc_add ?";
    static final String UPDATE_SQL = "EXEC dbo.sp_fish_doc_update ?, ?";

    public FishDocumentRepository(JdbcTemplate jdbc) {
        super(jdbc, DocumentType.FISH, GET_SQL, ADD_SQL, UPDATE_SQL);
    }
}
