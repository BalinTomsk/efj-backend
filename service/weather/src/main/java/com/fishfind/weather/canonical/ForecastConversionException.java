package com.fishfind.weather.canonical;

/**
 * A provider document could not be converted into the canonical envelope.
 *
 * <p>Checked on purpose. The station processors already turn a checked failure into a counted, logged
 * {@code ProcessingOutcome}, so a provider that changes its response shape shows up as failing stations
 * in the cycle report instead of disappearing into a silent no-op the way it did when parsing happened
 * inside a database trigger.
 */
public class ForecastConversionException extends Exception {

    public ForecastConversionException(String message) {
        super(message);
    }

    public ForecastConversionException(String message, Throwable cause) {
        super(message, cause);
    }
}
