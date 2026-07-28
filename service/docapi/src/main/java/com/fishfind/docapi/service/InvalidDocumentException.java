package com.fishfind.docapi.service;

/**
 * Thrown when a request body is missing, blank, or not well-formed JSON. Mapped to HTTP 400 by
 * {@code ApiExceptionHandler}.
 */
public class InvalidDocumentException extends RuntimeException {

    public InvalidDocumentException(String message) {
        super(message);
    }

    public InvalidDocumentException(String message, Throwable cause) {
        super(message, cause);
    }
}
