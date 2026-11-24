package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * {@code GET /api/v1/news/{id}}: csnews-env {@code GET /api/v1/csnews/doc/{id}} ({@code sp_news_doc_get}), docapi
 * 1.44.0. Replaces {@code MySqlNewsDocumentRepository}; docapi has no MySQL access.
 *
 * <p><strong>Read-only.</strong> News writes go through {@code NewsDocumentService} to
 * {@link NewsWriteRepository}; the two write methods throw so a caller that bypasses the service fails loudly.
 */
public class HttpNewsDocumentRepository implements DocumentStore {

    private final CsNewsClient csnews;

    public HttpNewsDocumentRepository(CsNewsClient csnews) {
        this.csnews = csnews;
    }

    @Override
    public String getDocument(String id) {
        JsonNode doc = csnews.get("/doc/" + CsNewsClient.enc(id));
        return doc == null || doc.isNull() ? null : doc.toString();
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
}
