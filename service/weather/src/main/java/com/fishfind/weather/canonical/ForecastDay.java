package com.fishfind.weather.canonical;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.time.LocalDate;

/**
 * One forecast day in the canonical envelope, already reduced and already metric.
 *
 * <p>Every member maps 1:1 onto a {@code dbo.weather_Forecast} column, which is what lets
 * {@code dbo.sp_ows_meteo_canonical} be {@code OPENJSON … WITH … MERGE} and nothing else. Anything that
 * used to be decided in T-SQL — unit conversion, picking one row per day, splitting rainfall between day
 * and night, mapping a provider icon to a weather code — is decided here instead, where it is
 * unit-testable and where a bad payload can throw.
 *
 * <p>Nulls are omitted from the JSON: the database column is nullable and {@code OPENJSON} yields NULL
 * for an absent member, so a missing reading stays missing rather than becoming a fabricated zero.
 * {@code tempHighC} and {@code tempLowC} are the exception the database defaults to 0, because
 * {@code weather_Forecast} declares them NOT NULL.
 *
 * @param date            forecast day, local to the station
 * @param time            hour the values describe, or {@code 00:00:00} for a daily summary. Never null:
 *                        {@code dbo.fnWeatherForecast} selects {@code WHERE tm IS NULL}, so a null here
 *                        would expose these rows to a caller no other forecast row reaches.
 * @param tempHighC       daily maximum, °C
 * @param tempLowC        daily minimum, °C
 * @param tempC           representative temperature, °C, rounded — {@code air_temperature}
 * @param tempDayC        mean daytime temperature, °C — {@code tmDay}
 * @param humidityPct     relative humidity, %
 * @param windSpeedKmh    wind speed, km/h
 * @param windDegrees     wind direction in degrees
 * @param windDirection   compass abbreviation derived from {@code windDegrees}
 * @param pressureHpa     mean sea-level pressure, hPa (= mb)
 * @param precipChancePct probability of precipitation, %
 * @param precipMm        total precipitation for the day, mm — {@code rain_today}
 * @param precipDayMm     precipitation falling 06:00–17:59, mm — {@code gpfDay}
 * @param precipNightMm   precipitation falling outside that window, mm — {@code gpfNight}
 * @param weatherCode     WMO-style code, the vocabulary already stored by the Open-Meteo path
 * @param icon            icon file name, e.g. {@code om_2.png}
 * @param conditionsShort short condition text, ≤ 64 chars
 * @param conditionsLong  long condition text, ≤ 255 chars
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ForecastDay(
        LocalDate date,
        String time,
        Double tempHighC,
        Double tempLowC,
        Integer tempC,
        Double tempDayC,
        Double humidityPct,
        Double windSpeedKmh,
        Double windDegrees,
        String windDirection,
        Integer pressureHpa,
        Integer precipChancePct,
        Integer precipMm,
        Double precipDayMm,
        Double precipNightMm,
        Integer weatherCode,
        String icon,
        String conditionsShort,
        String conditionsLong) {

    /** Daily summaries have no hour of their own; see {@link #time}. */
    public static final String DAILY_SUMMARY_TIME = "00:00:00";

    /** Compass abbreviation for a bearing, matching the text the legacy T-SQL branches produced. */
    public static String compass(Double degrees) {
        if (degrees == null) {
            return null;
        }
        double d = degrees % 360;
        if (d < 0) {
            d += 360;
        }
        if (d >= 337.5 || d < 22.5) {
            return "N";
        } else if (d < 67.5) {
            return "NE";
        } else if (d < 112.5) {
            return "E";
        } else if (d < 157.5) {
            return "SE";
        } else if (d < 202.5) {
            return "S";
        } else if (d < 247.5) {
            return "SW";
        } else if (d < 292.5) {
            return "W";
        }
        return "NW";
    }
}
