package com.fishfind.weather.service;

import java.io.IOException;

/**
 * Raised when Open-Meteo keeps returning HTTP 429 after the configured number of
 * Retry-After honouring attempts. It is an {@link IOException} so the circuit breaker
 * records it as a failure, but it is excluded from Resilience4j retry (the Retry-After
 * waits have already been honoured inline).
 */
public class RateLimitedException extends IOException {
    public RateLimitedException(String message) {
        super(message);
    }

    public RateLimitedException(String message, Throwable cause) {
        super(message, cause);
    }
}
