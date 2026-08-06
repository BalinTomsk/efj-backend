package com.fishfind.water.service;

import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import org.slf4j.Logger;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.ResourceAccessException;

import java.io.FileNotFoundException;
import java.io.IOException;

/**
 * Shared processing template for station processors.
 */
public abstract class StationProcessorBase {

    /**
     * Processes a single station, converting any failure into a logged, handled outcome.
     *
     * @return {@code true} when the station was processed without error; {@code false} when an exception
     *         was handled (e.g. a failure or an unpublished/skipped source)
     */
    public final boolean process(String mli, String state, int tz) {
        return processWithOutcome(mli, state, tz) == ProcessingOutcome.PROCESSED;
    }

    /**
     * Processes a single station and returns the handled outcome.
     */
    public final ProcessingOutcome processWithOutcome(String mli, String state, int tz) {
        try {
            processStation(mli, state, tz);
            return ProcessingOutcome.PROCESSED;
        } catch (Exception ex) {
            return handleProcessingException(mli, state, tz, ex);
        }
    }

    protected abstract void processStation(String mli, String state, int tz) throws Exception;

    protected abstract Logger logger();

    protected abstract String country();

    protected abstract String missingSourceDescription();

    protected ProcessingOutcome handleProcessingException(String mli, String state, int tz, Exception ex) {
        if (ex instanceof FileNotFoundException) {
            logger().debug(
                    "Skipping {} with no published {}. station={} state={}",
                    stationLabel(),
                    missingSourceDescription(),
                    mli,
                    state
            );
            return ProcessingOutcome.SKIPPED;
        }

        if (ex instanceof CallNotPermittedException) {
            logger().warn(
                    "{} processing stopped because upstream circuit breaker is open. station={} state={} error={}: {}",
                    stationLabel(),
                    mli,
                    state,
                    ex.getClass().getSimpleName(),
                    ex.getMessage()
            );
            return ProcessingOutcome.FAILED_UPSTREAM_OPEN;
        }

        if (ex instanceof IOException || ex instanceof ResourceAccessException || isHttp503(ex)) {
            logger().warn(
                    "{} processing failed. station={} state={} error={}: {}",
                    stationLabel(),
                    mli,
                    state,
                    ex.getClass().getSimpleName(),
                    ex.getMessage()
            );
            return isHttp503(ex) ? ProcessingOutcome.FAILED_HTTP_503 : ProcessingOutcome.FAILED;
        }

        logger().warn("{} processing failed. station={} state={}.", stationLabel(), mli, state, ex);
        return ProcessingOutcome.FAILED;
    }

    private String stationLabel() {
        return country() + " station";
    }

    private static boolean isHttp503(Exception ex) {
        if (ex instanceof HttpStatusCodeException statusException
                && statusException.getStatusCode().value() == 503) {
            return true;
        }

        String message = ex.getMessage();
        return message != null && message.contains("HTTP 503");
    }
}
