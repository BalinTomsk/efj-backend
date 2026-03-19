package com.fishfind.water.domain;

import java.time.OffsetDateTime;

public record Reading(
        String stationId,
        OffsetDateTime stamp,
        Double waterLevel,
        Double discharge
) {}