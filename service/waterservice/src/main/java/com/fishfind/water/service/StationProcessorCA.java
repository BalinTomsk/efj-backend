package com.fishfind.water.service;

import com.fishfind.water.domain.Reading;
import com.fishfind.water.repo.WaterDataRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.OffsetDateTime;
import java.util.*;

/**
 * Coordinates fetch, parse, save, and shared exception handling for one station at a time.
 */
@Service
public class StationProcessorCA extends StationProcessorBase {
    private static final Logger log = LoggerFactory.getLogger(StationProcessorCA.class);

    private final CsvFetcherCA fetcher;
    private final WaterDataRepository dataRepo;

    /**
     * Creates a processor with the collaborators required for station handling.
     *
     * @param fetcher CSV fetcher used to download source data
     * @param dataRepo repository used to persist parsed readings
     */
    public StationProcessorCA(CsvFetcherCA fetcher,
                              WaterDataRepository dataRepo) {
        this.fetcher = fetcher;
        this.dataRepo = dataRepo;
    }

    /**
     * Processes one station by downloading its CSV, parsing readings, and persisting them.
     *
     * @param mli station identifier
     * @param state Canadian province code used in the CSV URL
     * @param tz station timezone metadata from the database
     */
    @Override
    protected void processStation(String mli, String state, int tz) throws Exception {
        var csv = fetcher.fetch(state, mli);
        var readings = parse(csv);

        log.debug("Saving station readings. country={} station={} state={} readings={}", country(), mli, state, readings.size());
        dataRepo.saveStationData(mli, readings);
        log.debug("Saved station readings. country={} station={} state={} readings={}", country(), mli, state, readings.size());
    }

    @Override
    protected Logger logger() {
        return log;
    }

    @Override
    protected String country() {
        return "CA";
    }

    @Override
    protected String missingSourceDescription() {
        return "hydrometric CSV";
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
}
