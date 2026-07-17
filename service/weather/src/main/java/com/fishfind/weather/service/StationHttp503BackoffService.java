package com.fishfind.weather.service;

import com.fishfind.weather.domain.StationRef;
import com.fishfind.weather.repo.StationHttp503BackoffRepository;
import java.time.LocalDate;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Maintains per-station HTTP 503 backoff state so repeatedly unavailable stations are
 * checked less often, and immediately return to normal after a successful processing run.
 */
@Component
public class StationHttp503BackoffService {
    private static final Logger log = LoggerFactory.getLogger(StationHttp503BackoffService.class);

    private final StationHttp503BackoffRepository repository;

    public StationHttp503BackoffService(StationHttp503BackoffRepository repository) {
        this.repository = repository;
    }

    public void refreshDue(LocalDate today) {
        repository.refreshDue(today);
    }

    public void recordHttp503(String provider, String country, StationRef station, LocalDate today) {
        repository.recordHttp503(provider, country, station.mli(), station.state(), today);
        log.warn("Recorded station HTTP 503. provider={} country={} station={} state={}",
                provider, country, station.mli(), station.state());
    }

    public void recordProcessed(String provider, String country, StationRef station) {
        repository.reset(provider, country, station.mli());
        log.info("Reset station HTTP 503 backoff after successful processing. provider={} country={} station={} "
                        + "state={}",
                provider, country, station.mli(), station.state());
    }

    public List<StationHttp503BackoffRepository.BackoffSummary> summaryByState() {
        return repository.summaryByState();
    }
}
