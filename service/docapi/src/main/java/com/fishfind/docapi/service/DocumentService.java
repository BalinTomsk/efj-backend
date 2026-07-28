package com.fishfind.docapi.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.DocumentStore;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Entity-agnostic business logic for the JSON-document endpoints: id/body validation, JSON well-formedness
 * checks, and translation of a missing document into a {@link DocumentNotFoundException}.
 *
 * <p>Concrete subclasses (one per entity) supply the matching {@link DocumentStore} and
 * {@link DocumentType}, giving Spring a distinct bean type to inject into each controller — the same
 * base-plus-subclass idiom {@code waterservice} uses for its station processors. The store is an
 * in-memory backing by default and the SQL Server backing only under the {@code jdbc} profile.
 */
public abstract class DocumentService {

    private static final Logger log = LoggerFactory.getLogger(DocumentService.class);

    private final DocumentStore store;
    private final ObjectMapper objectMapper;
    private final DocumentType type;

    protected DocumentService(DocumentStore store, ObjectMapper objectMapper, DocumentType type) {
        this.store = store;
        this.objectMapper = objectMapper;
        this.type = type;
    }

    /**
     * Returns the stored document parsed to a JSON tree so it nests as real JSON in the response envelope
     * (rather than an escaped string).
     *
     * @param id the entity id
     * @return the document as a JSON tree
     * @throws DocumentNotFoundException if no document exists for the id
     */
    public JsonNode get(String id) {
        requireId(id);
        String stored = store.getDocument(id);
        if (stored == null || stored.isBlank()) {
            throw new DocumentNotFoundException(type, id);
        }
        return parseStored(stored, id);
    }

    /**
     * Validates the body is well-formed JSON, then inserts it. The stored body is the normalized (re-serialized)
     * form so trailing whitespace and formatting differences do not reach the database.
     *
     * @param rawBody the raw request body
     * @return the id assigned by the insert procedure
     */
    public String add(String rawBody) {
        JsonNode node = requireValidJson(rawBody);
        String newId = store.addDocument(node.toString());
        log.info("Added {} document (id={})", type.label(), newId);
        return newId;
    }

    /**
     * Validates the id and body, then updates the stored document.
     *
     * @param id the entity id to update
     * @param rawBody the raw request body
     * @return the id reported by the update procedure, or the supplied id when the procedure returns nothing
     */
    public String update(String id, String rawBody) {
        requireId(id);
        JsonNode node = requireValidJson(rawBody);
        String updatedId = store.updateDocument(id, node.toString());
        log.info("Updated {} document (id={})", type.label(), id);
        return updatedId != null ? updatedId : id;
    }

    private JsonNode parseStored(String stored, String id) {
        try {
            return objectMapper.readTree(stored);
        } catch (JsonProcessingException ex) {
            // A malformed document coming back from the DB is a server-side data problem, not a client error.
            throw new IllegalStateException(
                    "Stored " + type.label() + " document for id '" + id + "' is not valid JSON", ex);
        }
    }

    private JsonNode requireValidJson(String rawBody) {
        if (rawBody == null || rawBody.isBlank()) {
            throw new InvalidDocumentException("Request body must be a non-empty JSON document");
        }
        try {
            return objectMapper.readTree(rawBody);
        } catch (JsonProcessingException ex) {
            throw new InvalidDocumentException("Request body is not well-formed JSON: " + ex.getOriginalMessage(), ex);
        }
    }

    private void requireId(String id) {
        if (id == null || id.isBlank()) {
            throw new InvalidDocumentException("Document id must not be blank");
        }
    }
}
