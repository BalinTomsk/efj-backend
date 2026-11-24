package com.fishfind.docapi.repo;

import com.fishfind.docapi.service.ApiProblemException;
import org.springframework.http.HttpStatus;

/**
 * csnews-env (the news database's only client) is down, slow, behind an open breaker, or its MySQL is: a
 * {@code 503 unavailable} to the caller, never a 500, with a generic message (the detail is logged). Counts against the {@code csnewsBreaker}.
 */
public class CsNewsUnavailableException extends ApiProblemException {

    /** What the public sees: no internal host, path or status. */
    static final String PUBLIC_MESSAGE = "News is temporarily unavailable";

    private final String detail;

    /** @param detail what failed, for the log only */
    public CsNewsUnavailableException(String detail, Throwable cause) {
        super(HttpStatus.SERVICE_UNAVAILABLE, "unavailable", PUBLIC_MESSAGE);
        this.detail = detail;
        if (cause != null) {
            initCause(cause);
        }
    }

    public String detail() {
        return detail;
    }
}
