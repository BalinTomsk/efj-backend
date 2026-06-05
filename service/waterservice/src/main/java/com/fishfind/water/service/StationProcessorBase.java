package com.fishfind.water.service;

import org.slf4j.Logger;

import java.io.FileNotFoundException;

/**
 * Shared processing template for station processors.
 */
public abstract class StationProcessorBase {

    public final void process(String mli, String state, int tz) {
        try {
            processStation(mli, state, tz);
        } catch (Exception ex) {
            handleProcessingException(mli, state, tz, ex);
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
