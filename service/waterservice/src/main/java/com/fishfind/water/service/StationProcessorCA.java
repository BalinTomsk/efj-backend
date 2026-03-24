package com.fishfind.water.service;

import com.fishfind.water.domain.Reading;
import com.fishfind.water.repo.WaterDataRepository;
import com.fishfind.water.repo.WaterStationRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Coordinates fetch, parse, save, and failure tracking for one station at a time.
 */
@Service
public class StationProcessorCA {
    private static final Logger log = LoggerFactory.getLogger(StationProcessorCA.class);
    private final Map<String, FailureState> failureStates = new ConcurrentHashMap<>();

    private final CsvFetcherCA fetcher;
    private final WaterDataRepository dataRepo;
    private final WaterStationRepository stationRepo;

    /**
     * Creates a processor with the collaborators required for station handling.
     *
     * @param fetcher CSV fetcher used to download source data
     * @param dataRepo repository used to persist parsed readings
     * @param stationRepo repository used to disable failing stations
     */
    public StationProcessorCA(CsvFetcherCA fetcher,
                              WaterDataRepository dataRepo,
                              WaterStationRepository stationRepo) {
        this.fetcher = fetcher;
        this.dataRepo = dataRepo;
        this.stationRepo = stationRepo;
    }

    /**
     * Processes one station by downloading its CSV, parsing readings, and persisting them.
     * Repeated failures are tracked per day and disable the station after three failures.
     *
     * @param mli station identifier
     * @param state Canadian province code used in the CSV URL
     * @param tz station timezone metadata from the database
     */
    public void process(String mli, String state, int tz) {
        try {
            var csv = fetcher.fetch(state, mli);
            var readings = parse(csv);

            log.info("Saving station readings. station={} state={} readings={}", mli, state, readings.size());
            dataRepo.saveStationData(mli, readings);
            failureStates.remove(mli);
            log.info("Saved station readings. station={} state={} readings={}", mli, state, readings.size());

        } catch (Exception ex) {
            int failures = incrementFailureCount(mli);
            log.warn("Station processing failed. station={} state={} failuresToday={}", mli, state, failures, ex);
            if (failures >= 3) {
                stationRepo.disableStation(mli);
                failureStates.remove(mli);
                log.error("Disabled station after repeated failures. station={} state={} failuresToday={}", mli, state, failures);
            }
        }
    }

    /**
     * Increments the per-day failure counter for a station.
     *
     * @param mli station identifier
     * @return the updated number of failures for the current day
     */
    private int incrementFailureCount(String mli) {
        LocalDate today = LocalDate.now();
        return failureStates.compute(mli, (key, existing) -> {
            if (existing == null || !existing.day().equals(today)) {
                return new FailureState(today, 1);
            }

            return new FailureState(today, existing.count() + 1);
        }).count();
    }

    /**
     * Parses downloaded CSV rows into domain readings while skipping the header and malformed rows.
     *
     * @param csv CSV rows split into columns
     * @return parsed readings ready for persistence
     */
    private List<Reading> parse(List<String[]> csv) {
        List<Reading> list = new ArrayList<>();

        boolean first = true;
        for (String[] row : csv) {
            if (first) {
                first = false;   // skip header
                continue;
            }

            if (row.length < 7) {
                continue;
            }

            String stationId = trim(row[0]);
            String stampText = trim(row[1]);
            Double waterLevel = parseDouble(row[2]);
            Double discharge = parseDouble(row[6]);

            if (stationId == null || stationId.isEmpty() || stampText == null || stampText.isEmpty()) {
                continue;
            }

            OffsetDateTime stamp = OffsetDateTime.parse(stampText);

            list.add(new Reading(stationId, stamp, waterLevel, discharge));
        }

        return list;
    }

    /**
     * Trims a string value, preserving {@code null}.
     *
     * @param s raw input value
     * @return trimmed value or {@code null}
     */
    private String trim(String s) {
        return s == null ? null : s.trim();
    }

    /**
     * Parses a numeric string into a {@link Double}.
     *
     * @param s raw numeric text
     * @return parsed number, or {@code null} for blank input
     */
    private Double parseDouble(String s) {
        if (s == null || s.trim().isEmpty()) {
            return null;
        }
        return Double.parseDouble(s.trim());
    }

    /**
     * Tracks failure count for a station on a specific calendar day.
     *
     * @param day day the failures apply to
     * @param count number of failures recorded on that day
     */
    private record FailureState(LocalDate day, int count) {
    }
}
