package com.fishfind.docapi.repo;

/**
 * Storage abstraction for one entity's JSON documents. Two implementations exist:
 *
 * <ul>
 *   <li>{@link InMemoryDocumentStore} — the default, so the service runs with no database
 *       (active unless the {@code jdbc} Spring profile is set);</li>
 *   <li>{@link JdbcDocumentRepository} — the SQL Server / stored-procedure backing, wired only under
 *       the {@code jdbc} profile once the per-entity DB objects exist.</li>
 * </ul>
 *
 * <p>Documents are opaque JSON strings; ids are strings so each backing can use whatever key type it
 * likes (an in-memory sequence, or SQL Server's {@code int}/{@code uniqueidentifier}).
 */
public interface DocumentStore {

    /**
     * @param id the document id
     * @return the stored JSON document, or {@code null} if no document exists for the id
     */
    String getDocument(String id);

    /**
     * @param json a well-formed JSON body (validated upstream)
     * @return the id assigned to the newly stored document
     */
    String addDocument(String json);

    /**
     * @param id the document id to update
     * @param json a well-formed JSON body (validated upstream)
     * @return the affected document id, or {@code null} if the backing reports nothing
     */
    String updateDocument(String id, String json);
}
