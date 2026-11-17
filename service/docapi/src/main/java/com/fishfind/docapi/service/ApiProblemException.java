package com.fishfind.docapi.service;

import org.springframework.http.HttpStatus;

/**
 * A refusal with its own HTTP status and error code (1.36.0, the catch log): 401 {@code sign_in_required} when
 * cproxy named no account, 403 {@code locked} past the 60-day edit window, 404 {@code not_found} for a log that is
 * not the caller's. Mapped by {@code ApiExceptionHandler}; never logged as an error.
 */
public class ApiProblemException extends RuntimeException {

    private final HttpStatus status;
    private final String code;

    public ApiProblemException(HttpStatus status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public HttpStatus status() {
        return status;
    }

    public String code() {
        return code;
    }
}
