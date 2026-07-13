package com.fishfind.weather.service;

import java.time.LocalDate;

/** One day's completed-cycle summary, as recorded for the weekly report email. */
public record CycleReportEntry(
        LocalDate date,
        int successfulStations,
        int failedStations,
        String lastProcessedStation,
        String lastFailedStation) {
}
