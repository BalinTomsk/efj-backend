package com.fishfind.weather.service;

import com.fishfind.weather.domain.StationRef;
import java.io.FileNotFoundException;
import org.slf4j.Logger;

/**
 * Shared processing template for station processors.
 */
public abstract class StationProcessorBase {

    public final ProcessingOutcome process(StationRef station) {
        return process(station, country());
    }

    public final ProcessingOutcome process(StationRef station, String country) {
        try {
            processStation(station);
            return ProcessingOutcome.PROCESSED;
        } catch (Exception ex) {
            return handleProcessingException(station, ex, country);
        }
    }

    protected abstract void processStation(StationRef station) throws Exception;

    protected abstract Logger logger();

    protected abstract String country();

    protected abstract String missingSourceDescription();

    protected ProcessingOutcome handleProcessingException(StationRef station, Exception ex) {
        return handleProcessingException(station, ex, country());
    }

    protected ProcessingOutcome handleProcessingException(StationRef station, Exception ex, String country) {
        if (ex instanceof FileNotFoundException) {
            logger().info(
                    "Skipping {} with no published {}. station={} state={}",
                    stationLabel(country),
                    missingSourceDescription(),
                    station.mli(),
                    station.state()
            );
            return ProcessingOutcome.SKIPPED;
        }

        logger().warn(
                "{} processing failed. station={} state={}",
                stationLabel(country),
                station.mli(),
                station.state(),
                ex
        );
        return ProcessingOutcome.FAILED;
    }

    private String stationLabel(String country) {
        return country + " station";
    }
}
