package com.fishfind.weather.service;

import com.fishfind.weather.canonical.CanonicalForecast;
import com.fishfind.weather.canonical.PressureFill;
import com.fishfind.weather.domain.StationRef;
import java.time.LocalDate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Adds Open-Meteo pressure to a forecast whose provider sends none (Weather.gov). Feeds the FishFind
 * pressure forecast factor, which needs a daily pressure series for every station.
 *
 * <p>Best-effort by design: disabled, out of budget, or a failed call all return the forecast
 * unchanged, so a pressure problem can never cost a station its forecast. Each call is charged before
 * the fetch under {@link #USAGE_KEY}, like every other provider.
 *
 * <p>Mirrors {@code WeatherService.Processing.PressureBackfill} in efcs-backend.
 */
@Service
public class PressureBackfill {
    private static final Logger log = LoggerFactory.getLogger(PressureBackfill.class);

    /** Ledger key in {@link WeatherApiUsageTracker}, separate from the CA Open-Meteo worker. */
    public static final String USAGE_KEY = "OpenMeteoPressure";

    private final OpenMeteoFetcher fetcher;
    private final WeatherApiUsageTracker usage;
    private final boolean enabled;
    private final int dailyLimit;

    public PressureBackfill(OpenMeteoFetcher fetcher,
                            WeatherApiUsageTracker usage,
                            @Value("${weather.worker.pressure-backfill.enabled:true}") boolean enabled,
                            @Value("${weather.worker.pressure-backfill.daily-limit:1000}") int dailyLimit) {
        this.fetcher = fetcher;
        this.usage = usage;
        this.enabled = enabled;
        this.dailyLimit = dailyLimit;
    }

    /** Returns the forecast with missing {@code pressureHpa} filled where Open-Meteo has a value. */
    public CanonicalForecast fill(CanonicalForecast forecast, StationRef station) {
        if (!enabled || !PressureFill.anyMissing(forecast)) {
            return forecast;
        }
        if (!usage.tryConsume(USAGE_KEY, LocalDate.now(), dailyLimit)) {
            log.debug("Open-Meteo pressure budget spent; saving without pressure. station={}", station.mli());
            return forecast;
        }
        try {
            String json = fetcher.fetchPressure(station.latitude(), station.longitude());
            CanonicalForecast filled = PressureFill.fill(forecast, PressureFill.dailyPressure(json));
            log.debug("Open-Meteo pressure filled. station={} days={}", station.mli(),
                    filled.days().stream().filter(d -> d.pressureHpa() != null).count());
            return filled;
        } catch (Exception ex) {
            log.warn("Open-Meteo pressure backfill failed; saving without pressure. station={} error={}",
                    station.mli(), ex.getMessage());
            return forecast;
        }
    }
}
