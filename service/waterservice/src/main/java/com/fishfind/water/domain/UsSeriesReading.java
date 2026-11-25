package com.fishfind.water.domain;

import java.time.LocalDate;

/**
 * One USGS parameter value for a station, named the way the legacy WaterML feed named it
 * ({@code UsgsParameterMap}): envdata's {@code sp_water_save_us} converts units by that name/unit pair.
 *
 * @param name legacy parameter name, for example {@code Streamflow}
 * @param unit legacy unit, for example {@code ft^3/s}; may be {@code null}
 * @param day the station's LOCAL day of the observation (one reading per day, as WaterData stored it)
 * @param value the numeric value, in {@code unit}
 */
public record UsSeriesReading(
        String name,
        String unit,
        LocalDate day,
        double value
) {}
