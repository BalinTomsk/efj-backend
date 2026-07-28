package com.fishfind.docapi.repo;

import com.fishfind.docapi.domain.DocumentType;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * JSON-document access for water stations (SQL Server backing, {@code jdbc} profile only).
 *
 * <p>DB contract (to be created in {@code envfish-db}): {@code dbo.fn_station_doc(@id)} returns the
 * station as JSON; {@code dbo.sp_station_doc_add(@json)} inserts and returns the new id;
 * {@code dbo.sp_station_doc_update(@id, @json)} updates and returns the id.
 */
public class StationDocumentRepository extends JdbcDocumentRepository {

    static final String GET_SQL = "SELECT dbo.fn_station_doc(?)";
    static final String ADD_SQL = "EXEC dbo.sp_station_doc_add ?";
    static final String UPDATE_SQL = "EXEC dbo.sp_station_doc_update ?, ?";

    public StationDocumentRepository(JdbcTemplate jdbc) {
        super(jdbc, DocumentType.STATION, GET_SQL, ADD_SQL, UPDATE_SQL);
    }
}
