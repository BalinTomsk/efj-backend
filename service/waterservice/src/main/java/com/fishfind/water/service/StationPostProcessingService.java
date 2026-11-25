package com.fishfind.water.service;

import com.fishfind.water.repo.WaterDataRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

/**
 * Runs the synchronous database steps that must happen after a station-processing cycle completes.
 *
 * <p>Since 2.0.0 nothing here touches SQL Server: the fish hand-over (species push, probability update) belongs to
 * env_service, which reads the cycles this service records in envdata's {@code job_run}. Same as the C# twin 11.0.0.
 */
@Service
public class StationPostProcessingService {
    private static final Logger log = LoggerFactory.getLogger(StationPostProcessingService.class);

    private final WaterDataRepository waterDataRepository;

    public StationPostProcessingService(WaterDataRepository waterDataRepository) {
        this.waterDataRepository = waterDataRepository;
    }

    /**
     * Records a cycle that processed at least one station ({@code sp_job_run_record}), so env_service knows new
     * readings are in.
     *
     * @param job {@code water-ca}, {@code water-us} or {@code water} (both passes)
     * @param started cycle start
     * @param succeeded stations processed successfully
     * @param failed stations that failed; status is {@code ok} when 0, else {@code partial}
     */
    public void recordCycle(String job, Instant started, int succeeded, int failed) {
        String status = failed == 0 ? "ok" : "partial";
        log.info("Recording cycle in job_run. job={} status={} succeeded={} failed={}", job, status, succeeded, failed);
        waterDataRepository.recordCycle(job,
                LocalDateTime.ofInstant(started, ZoneOffset.UTC),
                LocalDateTime.now(ZoneOffset.UTC),
                status, succeeded, failed == 0 ? null : "failed=" + failed);
    }

    /**
     * Executes cleanup that must run after every cycle, even if no station was processed successfully.
     */
    public void cleanOldWaterData() {
        log.info("Running post-processing procedure {}", "sp_clean_old_water_data");
        waterDataRepository.cleanOldWaterData();
    }
}
