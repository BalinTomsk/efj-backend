package com.fishfind.water.service;

import com.fishfind.water.repo.WaterStationRepository;
import org.slf4j.Logger;

import java.time.LocalDate;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Shared processing template and failure-state tracking for station processors.
 */
public abstract class StationProcessorBase {
    private final Map<String, FailureState> failureStates = new ConcurrentHashMap<>();
    private final WaterStationRepository stationRepo;

    protected StationProcessorBase(WaterStationRepository stationRepo) {
        this.stationRepo = stationRepo;
    }

    public final void process(String mli, String state, int tz) {
        try {
            processStation(mli, state, tz);
            clearFailureState(mli);
        } catch (Exception ex) {
            handleProcessingException(mli, state, tz, ex);
        }
    }

    protected abstract void processStation(String mli, String state, int tz) throws Exception;

    protected abstract Logger logger();

    protected abstract String processingFailureMessage();

    protected abstract String disabledAfterFailuresMessage();

    protected void handleProcessingException(String mli, String state, int tz, Exception ex) {
        int failures = incrementFailureCount(mli);
        logger().warn(processingFailureMessage(), mli, state, failures, ex);
        if (failures >= 3) {
            disableStation(mli);
            clearFailureState(mli);
            logger().error(disabledAfterFailuresMessage(), mli, state, failures);
        }
    }

    protected final void disableStation(String mli) {
        stationRepo.disableStation(mli);
    }

    protected final void clearFailureState(String mli) {
        failureStates.remove(mli);
    }

    protected final int incrementFailureCount(String mli) {
        LocalDate today = LocalDate.now();
        return failureStates.compute(mli, (key, existing) -> {
            if (existing == null) {
                return new FailureState(today, 1);
            }

            if (existing.day().equals(today)) {
                return existing;
            }

            if (existing.day().plusDays(1).equals(today)) {
                return new FailureState(today, existing.count() + 1);
            }

            return new FailureState(today, 1);
        }).count();
    }

    protected final Map<String, FailureState> failureStates() {
        return failureStates;
    }

    /**
     * Tracks the current consecutive-day failure streak for a station.
     *
     * @param day most recent failed day for the station
     * @param count number of consecutive failed days
     */
    protected record FailureState(LocalDate day, int count) {
    }
}
