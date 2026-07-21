package com.fishfind.weather.service;

/**
 * Result of processing a single station, used by the worker to decide — at the end of a
 * cycle — whether the run was healthy enough to trigger post-processing.
 */
public enum ProcessingOutcome {
    /** Forecast was fetched and persisted. */
    PROCESSED,
    /** Station has no published Open-Meteo feed (HTTP 404); a normal, expected skip. */
    SKIPPED,
    /** Processing failed (network error, rate limit, SQL failure, open circuit, ...). */
    FAILED
}
