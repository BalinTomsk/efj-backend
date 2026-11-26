package com.fishfind.weather.service;

import com.fishfind.weather.repo.WeatherDataRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Locale;

/**
 * Runs the database steps that must happen, in order, after a healthy station-processing cycle: record the cycle in
 * envdata's {@code job_run}, then the weather retention.
 *
 * <p>Since 2.0.0 nothing here touches SQL Server. The fish hand-over this service used to run itself
 * ({@code spPushSpeciesFromLakeToStation}, {@code spTotalUpdateProbability}) belongs to env_service, which reads the
 * cycles recorded here. Same as the C# twin 11.0.0.
 *
 * <p>{@code synchronized}: the provider workers finish their cycles independently, and the retention deletes shared
 * rows.
 */
@Service
public class StationPostProcessingService {
    private static final Logger log = LoggerFactory.getLogger(StationPostProcessingService.class);

    private final WeatherDataRepository weatherDataRepository;

    public StationPostProcessingService(WeatherDataRepository weatherDataRepository) {
        this.weatherDataRepository = weatherDataRepository;
    }

    /**
     * Records the cycle ({@code sp_job_run_record}; job {@code {provider}-{country}}, lower case, e.g.
     * {@code open-meteo-ca}; only when at least one station was saved, so env_service hands over only cycles that
     * brought weather), then runs {@code sp_clean_old_weather_data}. A failure stops the run and surfaces to the
     * caller.
     *
     * @param provider the worker's report name, as the C# twin passes it
     * @param country {@code CA} / {@code US}
     * @param started cycle start
     * @param succeeded stations saved
     * @param failed stations that failed; status is {@code ok} when 0, else {@code partial}
     */
    public synchronized void runAfterStationProcessing(String provider, String country, Instant started,
                                                       int succeeded, int failed) {
        if (succeeded > 0) {
            String job = jobName(provider, country);
            String status = failed == 0 ? "ok" : "partial";
            log.info("Recording cycle in job_run. job={} status={} succeeded={} failed={}",
                    job, status, succeeded, failed);
            weatherDataRepository.recordCycle(job,
                    LocalDateTime.ofInstant(started, ZoneOffset.UTC),
                    LocalDateTime.now(ZoneOffset.UTC),
                    status, succeeded, failed == 0 ? null : "failed=" + failed);
        }

        log.info("Running post-processing procedure {}", "sp_clean_old_weather_data");
        weatherDataRepository.cleanOldWeatherData();
    }

    /** {@code job_run.job} of a provider/country cycle: lower case, at most 32 characters. */
    static String jobName(String provider, String country) {
        String job = (provider + "-" + country).toLowerCase(Locale.ROOT);
        return job.length() > 32 ? job.substring(0, 32) : job;
    }
}
