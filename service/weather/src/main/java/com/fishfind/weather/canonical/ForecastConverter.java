package com.fishfind.weather.canonical;

/**
 * Converts one provider's raw document into the canonical envelope.
 *
 * <p>This is where provider knowledge now lives. Previously each provider needed its own T-SQL parser
 * inside a trigger, which could not raise — an error there would abort the worker's {@code UPDATE} and
 * discard the payload it had just fetched — so an unparseable document produced no rows and no error.
 * A converter runs in the worker, so it <b>throws</b>, and the failure is logged, counted and retried
 * like any other station failure.
 *
 * <p>Implementations must be pure: given the same raw document and station they produce the same
 * envelope, with no I/O and no clock beyond the {@code fetchedUtc} passed in. That is what makes them
 * testable against recorded provider payloads.
 */
public interface ForecastConverter {

    /** Stable provider name recorded in the envelope, e.g. {@code visual-crossing}. */
    String provider();

    /** Provider identity stored in {@code dbo.ows_meteo.type}; see {@link WeatherSourceType}. */
    int providerType();

    /**
     * Converts a raw provider document into the canonical envelope.
     *
     * @param rawJson the provider's response, verbatim — embedded in the envelope as {@code raw}
     * @param mli     the water gauge this payload was fetched for
     * @throws ForecastConversionException if the document is not the shape this provider produces, or
     *                                     carries no usable forecast day
     */
    CanonicalForecast convert(String rawJson, String mli) throws ForecastConversionException;
}
