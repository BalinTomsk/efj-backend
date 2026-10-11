package com.fishfind.water.domain;

import java.time.OffsetDateTime;

/**
 * One latest value of one USGS time series, from the Water Data API {@code latest-continuous} collection.
 *
 * @param parameterCode USGS parameter code, for example {@code 00060} (streamflow)
 * @param statisticId USGS statistic code; {@code 00011} is an instantaneous value. May be {@code null}
 * @param time observation time (the API reports UTC)
 * @param value value as published (a decimal string)
 */
public record UsgsObservation(
        String parameterCode,
        String statisticId,
        OffsetDateTime time,
        String value
) {}
