package com.fishfind.water.domain;

import java.time.OffsetDateTime;

/**
 * Parsed hydrometric reading for a station timestamp.
 *
 * @param stationId source station identifier from the CSV payload
 * @param stamp reading timestamp with offset information
 * @param waterLevel water level value mapped to the legacy elevation column
 * @param discharge discharge value from the CSV payload
 */
public record Reading(
        String stationId,
        OffsetDateTime stamp,
        Double waterLevel,
        Double discharge
) {}
