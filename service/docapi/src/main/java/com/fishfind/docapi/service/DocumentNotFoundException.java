package com.fishfind.docapi.service;

import com.fishfind.docapi.domain.DocumentType;

/**
 * Thrown when a requested document id has no stored JSON document. Mapped to HTTP 404 by
 * {@code ApiExceptionHandler}.
 */
public class DocumentNotFoundException extends RuntimeException {

    public DocumentNotFoundException(DocumentType type, String id) {
        super("No " + type.label() + " document found for id '" + id + "'");
    }
}
