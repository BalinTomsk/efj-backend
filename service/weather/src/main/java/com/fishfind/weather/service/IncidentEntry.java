package com.fishfind.weather.service;

import java.time.LocalDateTime;

/** One detected unclean-shutdown (crash) incident, as recorded for the weekly report email. */
public record IncidentEntry(
        LocalDateTime detectedAt,
        LocalDateTime downtimeStart,
        LocalDateTime downtimeEnd,
        String description) {
}
