package com.fishfind.water.service;

import com.fishfind.water.domain.Reading;
import com.fishfind.water.repo.WaterDataRepository;
import com.fishfind.water.repo.WaterStationRepository;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class StationProcessor {
    private final Map<String, FailureState> failureStates = new ConcurrentHashMap<>();

    private final CsvFetcher fetcher;
    private final WaterDataRepository dataRepo;
    private final WaterStationRepository stationRepo;

    public StationProcessor(CsvFetcher fetcher,
                            WaterDataRepository dataRepo,
                            WaterStationRepository stationRepo) {
        this.fetcher = fetcher;
        this.dataRepo = dataRepo;
        this.stationRepo = stationRepo;
    }

    public void process(String mli, String state, int tz) {

        try {
            var csv = fetcher.fetch(state, mli);
            var readings = parse(csv);

            System.out.println("Saving station: " + mli + " in[" + state + "]");
            dataRepo.saveStationData(mli, readings);
            failureStates.remove(mli);

        } catch (Exception ex) {
            int failures = incrementFailureCount(mli);
            if (failures >= 3) {
                stationRepo.disableStation(mli);
                failureStates.remove(mli);
            }
        }
    }

    private int incrementFailureCount(String mli) {
        LocalDate today = LocalDate.now();
        return failureStates.compute(mli, (key, existing) -> {
            if (existing == null || !existing.day().equals(today)) {
                return new FailureState(today, 1);
            }

            return new FailureState(today, existing.count() + 1);
        }).count();
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

    private record FailureState(LocalDate day, int count) {
    }
}
