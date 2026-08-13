package com.fishfind.weather.canonical;

/**
 * Provider identity stored in {@code dbo.ows_meteo.type}.
 *
 * <p>This column used to be a routing key: the database chose a T-SQL parser from it, and because every
 * provider was stamped {@code 2} the parser had to guess the document's shape. Four providers' payloads
 * were indistinguishable from Open-Meteo and were silently discarded. It is now <em>provenance</em> —
 * which provider served this station — while the shape is declared by the canonical envelope itself.
 *
 * <p>The values are a contract with {@code dbo.TR_ows_meteo}; see {@code envfish-db/CLAUDE.md}. Types
 * {@link #WEATHER_GOV} onward carry observations rather than forecasts on the legacy path and are
 * deliberately unrouted there, so a payload only becomes forecast rows once its converter emits an
 * envelope.
 */
public final class WeatherSourceType {

    /** The Weather Company / Weather Underground v3 daily forecast ({@code $.daypart[]}). */
    public static final int TWC_DAILY = 1;

    /** Open-Meteo ({@code $.hourly} + {@code $.daily}). Metric at source. */
    public static final int OPEN_METEO = 2;

    /** Visual Crossing timeline ({@code $.days[]}). Requested in US units. */
    public static final int VISUAL_CROSSING = 4;

    /** weather.gov / NWS gridpoint forecast (GeoJSON). */
    public static final int WEATHER_GOV = 5;

    /** Environment Canada / MSC SWOB observations. */
    public static final int ENVIRONMENT_CANADA = 6;

    /** Weather Underground personal-station observations ({@code $.observations[]}). */
    public static final int WUNDERGROUND_OBSERVATIONS = 7;

    /** Google Weather. */
    public static final int GOOGLE_WEATHER = 8;

    private WeatherSourceType() {
    }
}
