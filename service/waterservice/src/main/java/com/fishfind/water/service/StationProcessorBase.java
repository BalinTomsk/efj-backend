package com.fishfind.water.service;

import org.slf4j.Logger;

import java.io.FileNotFoundException;

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
        try {
            processStation(mli, state, tz);
            return true;
        } catch (Exception ex) {
            handleProcessingException(mli, state, tz, ex);
            return false;
        }
    }

    protected abstract void processStation(String mli, String state, int tz) throws Exception;

    protected abstract Logger logger();

    protected abstract String country();

    protected abstract String missingSourceDescription();

    protected void handleProcessingException(String mli, String state, int tz, Exception ex) {
        if (ex instanceof FileNotFoundException) {
            logger().debug(
                    "Skipping {} with no published {}. station={} state={}",
                    stationLabel(),
                    missingSourceDescription(),
                    mli,
                    state
            );
            return;
        }
        logger().warn("{} processing failed. station={} state={}.", stationLabel(), mli, state, ex);
    }

    private String stationLabel() {
        return country() + " station";
    }
}
