package com.fishfind.water.service;

/**
 * Result of processing a single station.
 */
public enum ProcessingOutcome {
    /** Water data was fetched and persisted. */
    PROCESSED,
    /** Station has no published source feed, such as HTTP 404. */
    SKIPPED,
    /** Processing failed because the upstream provider returned HTTP 503. */
    FAILED_HTTP_503,
    /** Processing stopped because the shared upstream circuit breaker is open. */
    FAILED_UPSTREAM_OPEN,
    /** Processing failed for any other handled reason. */
    FAILED
}
