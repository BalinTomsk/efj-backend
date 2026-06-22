package com.fishfind.water.service;

import com.fishfind.water.domain.Reading;
import com.fishfind.water.repo.WaterDataRepository;
import io.micrometer.core.instrument.MeterRegistry;
import org.apache.commons.csv.CSVFormat;
import org.apache.commons.csv.CSVParser;
import org.apache.commons.csv.CSVRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.io.StringReader;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * Coordinates fetch, parse, save, and shared exception handling for one CA station at a time.
 */
@Service
public class StationProcessorCA extends StationProcessorBase {
    private static final Logger log = LoggerFactory.getLogger(StationProcessorCA.class);
    private static final int MIN_COLUMNS = 7;
    private static final String ROWS_SKIPPED_METRIC = "water.csv.rows.skipped";

    private final CsvFetcherCA fetcher;
    private final WaterDataRepository dataRepo;
    private final MeterRegistry meterRegistry;

    /**
     * Creates a processor with the collaborators required for station handling.
     *
     * @param fetcher CSV fetcher used to download source data
     * @param dataRepo repository used to persist parsed readings
     * @param meterRegistry registry used to record skipped-row counts
     */
    public StationProcessorCA(CsvFetcherCA fetcher,
                              WaterDataRepository dataRepo,
                              MeterRegistry meterRegistry) {
        this.fetcher = fetcher;
        this.dataRepo = dataRepo;
        this.meterRegistry = meterRegistry;
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
        String csv = fetcher.fetch(state, mli);
        var readings = parse(csv, mli);

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
     * Parses the downloaded CSV into domain readings using commons-csv.
     *
     * <p>Parsing is fault-tolerant: the header row, short rows, rows missing the station id/timestamp, and
     * individual rows that fail to parse (e.g. an unparseable timestamp) are skipped rather than aborting the
     * whole station's batch. Skipped rows are counted on the {@code water.csv.rows.skipped} metric.
     *
     * @param csv raw CSV document body
     * @param mli station identifier, for logging
     * @return parsed readings ready for persistence
     */
    private List<Reading> parse(String csv, String mli) throws Exception {
        List<Reading> list = new ArrayList<>();
        if (csv == null || csv.isBlank()) {
            return list;
        }

        int skipped = 0;
        CSVFormat format = CSVFormat.DEFAULT.builder().setTrim(true).build();
        try (CSVParser parser = CSVParser.parse(new StringReader(csv), format)) {
            boolean first = true;
            for (CSVRecord row : parser) {
                if (first) {
                    first = false;   // skip header
                    continue;
                }

                if (row.size() < MIN_COLUMNS) {
                    skipped++;
                    continue;
                }

                try {
                    String stationId = row.get(0);
                    String stampText = row.get(1);
                    if (stationId.isEmpty() || stampText.isEmpty()) {
                        skipped++;
                        continue;
                    }

                    OffsetDateTime stamp = OffsetDateTime.parse(stampText);
                    Double waterLevel = parseDouble(row.get(2));
                    Double discharge = parseDouble(row.get(6));

                    list.add(new Reading(stationId, stamp, waterLevel, discharge));
                } catch (RuntimeException ex) {
                    // A single malformed row must not discard the rest of the station's readings.
                    skipped++;
                    log.debug("Skipping malformed CSV row. station={} row={}", mli, row.getRecordNumber(), ex);
                }
            }
        }

        if (skipped > 0) {
            meterRegistry.counter(ROWS_SKIPPED_METRIC, "country", country()).increment(skipped);
            log.info("Skipped malformed CSV rows. station={} skipped={}", mli, skipped);
        }
        return list;
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
