package com.fishfind.water.service;

import com.fishfind.water.domain.UsSeriesReading;
import com.fishfind.water.domain.UsgsObservation;
import com.fishfind.water.repo.WaterDataRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Map;

/**
 * Coordinates save and shared exception handling for one US station at a time, reading from a per-cycle
 * snapshot of the USGS Water Data API instead of calling USGS once per station.
 *
 * <p>The worker calls {@link #prepareCycle} once at the start of each US pass; each station is then a lookup
 * in that snapshot. A station with no current series is skipped, as a 404 used to be.
 */
@Service
public class StationProcessorUS extends StationProcessorBase {
    private static final Logger log = LoggerFactory.getLogger(StationProcessorUS.class);

    /** USGS statistic code for an instantaneous value — what the legacy {@code nwis/iv} feed served. */
    private static final String INSTANTANEOUS_STATISTIC = "00011";

    private final UsgsWaterDataClient client;
    private final WaterDataRepository dataRepo;

    private volatile Map<String, List<UsgsObservation>> snapshot;

    /**
     * Creates a processor with the collaborators required for US station handling.
     *
     * @param client USGS Water Data API client
     * @param dataRepo repository used to persist parsed series
     */
    public StationProcessorUS(UsgsWaterDataClient client,
                              WaterDataRepository dataRepo) {
        this.client = client;
        this.dataRepo = dataRepo;
    }

    /**
     * Loads this cycle's USGS snapshot and the time zones of the stations found in it. Throws when the
     * snapshot cannot be fetched, which fails the whole US pass.
     *
     * @param mlis the supported US stations for this pass
     * @param requestedMli a single requested station, or {@code null} for the full snapshot
     */
    public void prepareCycle(Collection<String> mlis, String requestedMli) throws IOException {
        Map<String, List<UsgsObservation>> fetched = client.fetchLatest(requestedMli);
        client.ensureTimeZones(mlis.stream().filter(fetched::containsKey).toList());
        snapshot = fetched;
    }

    /**
     * Processes one US station by looking it up in the cycle snapshot and persisting its readings.
     *
     * @param mli station identifier
     * @param state US state code
     * @param tz station timezone metadata from the database (unused: USGS publishes the site's own zone)
     */
    @Override
    protected void processStation(String mli, String state, int tz) throws Exception {
        Map<String, List<UsgsObservation>> current = snapshot;
        List<UsgsObservation> observations = current == null ? null : current.get(mli);
        if (observations == null) {
            throw new FileNotFoundException("No current USGS series for US station " + mli + " (state " + state + ")");
        }

        List<UsSeriesReading> seriesList = buildReadings(observations, client.timeZoneFor(mli));

        log.debug("Saving station readings. country={} station={} state={} series={}", country(), mli, state, seriesList.size());
        dataRepo.saveUsStationData(mli, state, seriesList);
        log.debug("Saved station readings. country={} station={} state={} series={}", country(), mli, state, seriesList.size());
    }

    @Override
    protected Logger logger() {
        return log;
    }

    @Override
    protected String country() {
        return "US";
    }

    @Override
    protected String missingSourceDescription() {
        return "USGS series";
    }

    /**
     * Turns a station's latest USGS values into stored-procedure payloads, one per series, named and united as
     * the legacy WaterML feed named them ({@link UsgsParameterMap}) and dated by the station's local day.
     * Unmapped parameters, non-instantaneous statistics and non-numeric values are dropped.
     *
     * @param observations the station's latest values
     * @param zone the station's local time zone
     * @return stored-procedure payloads
     */
    static List<UsSeriesReading> buildReadings(List<UsgsObservation> observations, ZoneId zone) {
        List<UsSeriesReading> results = new ArrayList<>();
        for (UsgsObservation observation : observations) {
            if (observation.statisticId() != null && !INSTANTANEOUS_STATISTIC.equals(observation.statisticId())) {
                continue;
            }

            UsgsParameterMap.LegacyName legacy = UsgsParameterMap.find(observation.parameterCode());
            String value = normalizeNumericValue(observation.value());
            if (legacy == null || value == null) {
                continue;
            }

            LocalDate day = observation.time().atZoneSameInstant(zone).toLocalDate();
            String xmlDoc = "<root><a d=\"" + day + "\" v=\"" + escapeXml(value) + "\" /></root>";
            results.add(new UsSeriesReading(legacy.name(), legacy.unit(), xmlDoc));
        }

        return results;
    }

    private static String normalizeNumericValue(String value) {
        if (value == null) {
            return null;
        }

        String trimmed = value.trim();
        if (trimmed.isEmpty()) {
            return null;
        }

        try {
            Double.parseDouble(trimmed);
            return trimmed;
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private static String escapeXml(String value) {
        return value
                .replace("&", "&amp;")
                .replace("\"", "&quot;")
                .replace("<", "&lt;")
                .replace(">", "&gt;");
    }
}
