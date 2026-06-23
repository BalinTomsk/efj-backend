package com.fishfind.weather.service;

import com.fishfind.weather.domain.StationRef;
import org.slf4j.Logger;

import java.io.FileNotFoundException;

/**
 * Shared processing template for station processors.
 */
public abstract class StationProcessorBase {

    public final ProcessingOutcome process(StationRef station) {
        try {
            processStation(station);
            return ProcessingOutcome.PROCESSED;
        } catch (Exception ex) {
            return handleProcessingException(station, ex);
        }
    }

    protected abstract void processStation(StationRef station) throws Exception;

    protected abstract Logger logger();

    protected abstract String country();

    protected abstract String missingSourceDescription();

    protected ProcessingOutcome handleProcessingException(StationRef station, Exception ex) {
        if (ex instanceof FileNotFoundException) {
            logger().info(
                    "Skipping {} with no published {}. station={} state={}",
                    stationLabel(),
                    missingSourceDescription(),
                    station.mli(),
                    station.state()
            );
            return ProcessingOutcome.SKIPPED;
        }

        logger().warn(
                "{} processing failed. station={} state={}",
                stationLabel(),
                station.mli(),
                station.state(),
                ex
        );
        return ProcessingOutcome.FAILED;
    }

    private String stationLabel() {
        return country() + " station";
    }
}
