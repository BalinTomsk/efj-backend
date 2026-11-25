package com.fishfind.docapi.repo;

import com.fishfind.docapi.service.ApiProblemException;
import org.springframework.http.HttpStatus;

/**
 * env_service (the water and weather data, 1.45.0) is down, slow, behind an open breaker, or its own databases are: a
 * {@code 503 unavailable} to the caller, never a 500, with a generic message (the detail is logged). Counts against the
 * {@code envBreaker}.
 */
public class EnvUnavailableException extends ApiProblemException {

    /** What the public sees: no internal host, path or status. */
    static final String PUBLIC_MESSAGE = "Water and weather data is temporarily unavailable";

    private final String detail;

    /** @param detail what failed, for the log only */
    public EnvUnavailableException(String detail, Throwable cause) {
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
