package com.fishfind.weather.service;

import com.fishfind.weather.domain.StationRef;
import java.io.FileNotFoundException;
import java.io.IOException;
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
        if (ex instanceof IOException && isHttp503(ex)) {
            logger().warn(
                    "{} processing failed with upstream HTTP 503. station={} state={} error={}: {}",
                    stationLabel(country),
                    station.mli(),
                    station.state(),
                    ex.getClass().getSimpleName(),
                    ex.getMessage()
            );
            return ProcessingOutcome.FAILED_HTTP_503;
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

    private static boolean isHttp503(Exception ex) {
        String message = ex.getMessage();
        return message != null && message.contains("HTTP 503");
    }
}
