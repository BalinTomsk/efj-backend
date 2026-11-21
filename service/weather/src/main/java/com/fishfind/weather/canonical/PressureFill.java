package com.fishfind.weather.canonical;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Fills {@link ForecastDay#pressureHpa()} from an Open-Meteo {@code hourly=pressure_msl} document, for
 * providers whose forecast carries no pressure (Weather.gov {@code /forecast}).
 *
 * <p>Per local date the <strong>last</strong> hour is taken, the same sample {@link OpenMeteoConverter}
 * stores for Open-Meteo stations, so every station's daily pressure series is read at the same time of
 * day. Days that already have a pressure keep it.
 *
 * <p>Mirrors {@code WeatherService.Canonical.PressureFill} in efcs-backend.
 */
public final class PressureFill {
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private PressureFill() {
    }

    /** True when at least one day has no pressure. */
    public static boolean anyMissing(CanonicalForecast forecast) {
        return forecast.days().stream().anyMatch(d -> d.pressureHpa() == null);
    }

    /**
     * Last-hour {@code pressure_msl} per local date, rounded to whole hPa (half away from zero). A document
     * without {@code hourly.time} / {@code hourly.pressure_msl} yields an empty map.
     */
    public static Map<LocalDate, Integer> dailyPressure(String openMeteoJson) throws IOException {
        Map<LocalDate, String> latestTime = new HashMap<>();
        Map<LocalDate, Integer> byDay = new HashMap<>();
        JsonNode hourly = MAPPER.readTree(openMeteoJson).path("hourly");
        JsonNode times = hourly.path("time");
        JsonNode pressures = hourly.path("pressure_msl");
        if (!times.isArray() || !pressures.isArray()) {
            return byDay;
        }

        int count = Math.min(times.size(), pressures.size());
        for (int i = 0; i < count; i++) {
            String time = times.get(i).asText(null);
            JsonNode value = pressures.get(i);
            if (time == null || time.length() < 10 || !value.isNumber()) {
                continue;
            }
            LocalDate date;
            try {
                date = LocalDate.parse(time.substring(0, 10));
            } catch (DateTimeParseException ex) {
                continue;
            }
            String seen = latestTime.get(date);
            if (seen == null || time.compareTo(seen) > 0) {
                latestTime.put(date, time);
                double hpa = value.asDouble();
                byDay.put(date, (int) (Math.signum(hpa) * Math.round(Math.abs(hpa))));
            }
        }
        return byDay;
    }

    /** Returns {@code forecast} with each pressure-less day filled where a value exists. */
    public static CanonicalForecast fill(CanonicalForecast forecast, Map<LocalDate, Integer> pressureByDay) {
        if (pressureByDay.isEmpty() || !anyMissing(forecast)) {
            return forecast;
        }
        List<ForecastDay> days = forecast.days().stream()
                .map(d -> d.pressureHpa() == null && pressureByDay.containsKey(d.date())
                        ? withPressure(d, pressureByDay.get(d.date()))
                        : d)
                .toList();
        return new CanonicalForecast(forecast.schema(), forecast.provider(), forecast.providerType(),
                forecast.mli(), forecast.fetchedUtc(), days, forecast.raw());
    }

    private static ForecastDay withPressure(ForecastDay d, Integer hpa) {
        return new ForecastDay(d.date(), d.time(), d.tempHighC(), d.tempLowC(), d.tempC(), d.tempDayC(),
                d.humidityPct(), d.windSpeedKmh(), d.windDegrees(), d.windDirection(), hpa,
                d.precipChancePct(), d.precipMm(), d.precipDayMm(), d.precipNightMm(), d.weatherCode(),
                d.icon(), d.conditionsShort(), d.conditionsLong());
    }
}
