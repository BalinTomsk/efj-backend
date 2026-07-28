package com.fishfind.docapi.web;

import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * Translates exceptions into the {@link ApiResponse} error envelope with an appropriate HTTP status.
 *
 * <p>Client mistakes (unknown id, malformed/blank body) become 4xx with a descriptive message; anything
 * else is logged and returned as a generic 500 so internal details (SQL, stack traces) never leak to callers.
 */
@RestControllerAdvice
public class ApiExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(DocumentNotFoundException.class)
    public ResponseEntity<ApiResponse<Void>> handleNotFound(DocumentNotFoundException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(ApiResponse.fail("not_found", ex.getMessage()));
    }

    @ExceptionHandler({InvalidDocumentException.class, HttpMessageNotReadableException.class})
    public ResponseEntity<ApiResponse<Void>> handleBadRequest(Exception ex) {
        return ResponseEntity.badRequest()
                .body(ApiResponse.fail("invalid_document", ex.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<Void>> handleUnexpected(Exception ex) {
        log.error("Unhandled error serving document request", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiResponse.fail("internal_error", "An unexpected error occurred"));
    }
}
