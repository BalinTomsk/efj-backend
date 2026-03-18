package com.fishfind.water.service;

import com.fishfind.water.domain.Reading;
import com.fishfind.water.repo.*;
import org.springframework.stereotype.Service;

import java.time.OffsetDateTime;
import java.util.*;

@Service
public class StationProcessor {

    private final CsvFetcher fetcher;
    private final WaterDataRepository dataRepo;
    private final FailureRepository failureRepo;
    private final WaterStationRepository stationRepo;

    public StationProcessor(CsvFetcher fetcher,
                            WaterDataRepository dataRepo,
                            FailureRepository failureRepo,
                            WaterStationRepository stationRepo) {
        this.fetcher = fetcher;
        this.dataRepo = dataRepo;
        this.failureRepo = failureRepo;
        this.stationRepo = stationRepo;
    }

    public void process(String mli, String state, int tz) {

        try {
            var csv = fetcher.fetch(state, mli);
            var readings = parse(csv);

            dataRepo.saveStationData(mli, readings);

        } catch (Exception ex) {

            int failures = failureRepo.countToday(mli);
            failureRepo.insert(mli);

            if (failures >= 2) {
                stationRepo.disableStation(mli);
            }
        }
    }

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

    private String trim(String s) {
        return s == null ? null : s.trim();
    }

    private Double parseDouble(String s) {
        if (s == null || s.trim().isEmpty()) {
            return null;
        }
        return Double.parseDouble(s.trim());
    }
}
