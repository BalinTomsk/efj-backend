package com.fishfind.weather.canonical;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.stereotype.Component;

/**
 * Converts a weather.gov (NWS) gridpoint forecast into the canonical envelope.
 *
 * <p><b>The shape is unlike the other providers': periods, not days.</b> NWS returns
 * {@code properties.periods[]}, each covering roughly half a day and flagged {@code isDaytime}. A
 * calendar day is therefore assembled from up to two periods — the daytime one carries the day's high,
 * the night one the low — and the first period of a response is frequently a night, because a forecast
 * issued in the evening starts with "Tonight".
 *
 * <p>Requested with {@code units=si}, so temperatures arrive in degC and wind speeds in km/h and
 * nothing is converted here. {@code windSpeed} is still a HUMAN STRING like {@code "10 to 15 km/h"};
 * the upper bound is taken, matching the "daily maximum wind" the other providers report.
 *
 * <p>Precipitation AMOUNT is deliberately absent: {@code /forecast} publishes only
 * {@code probabilityOfPrecipitation}. The quantity lives in the raw {@code /gridpoints} document, which
 * this does not fetch, so {@code precipMm} stays null rather than being invented — the database
 * defaults the NOT NULL rainfall columns to 0.
 */
@Component
public class WeatherGovConverter implements ForecastConverter {

    /** "10 to 15 km/h" / "15 km/h" -- the last number is the upper bound. */
    private static final Pattern WIND_SPEED = Pattern.compile("(\\d+)(?!.*\\d)");

    /** NWS icon URLs carry the condition as a token: .../icons/land/day/tsra,40?size=medium */
    private static final Pattern ICON_TOKEN = Pattern.compile("/icons/land/(?:day|night)/([a-z_]+)");

    /** NWS icon token -> the WMO-style codes the Open-Meteo path already stores. */
    private static final Map<String, Integer> TOKEN_TO_CODE = Map.ofEntries(
            Map.entry("skc", 0), Map.entry("few", 1), Map.entry("sct", 2), Map.entry("bkn", 3),
            Map.entry("ovc", 3), Map.entry("wind_skc", 0), Map.entry("wind_few", 1),
            Map.entry("wind_sct", 2), Map.entry("wind_bkn", 3), Map.entry("wind_ovc", 3),
            Map.entry("fog", 45), Map.entry("dust", 45), Map.entry("haze", 45), Map.entry("smoke", 45),
            Map.entry("rain", 63), Map.entry("rain_showers", 80), Map.entry("rain_showers_hi", 80),
            Map.entry("snow", 73), Map.entry("rain_snow", 71), Map.entry("snow_fzra", 71),
            Map.entry("sleet", 65), Map.entry("fzra", 65), Map.entry("rain_fzra", 65),
            Map.entry("tsra", 95), Map.entry("tsra_sct", 95), Map.entry("tsra_hi", 95),
            Map.entry("hot", 0), Map.entry("cold", 0), Map.entry("blizzard", 75));

    private final ObjectMapper mapper;
    private final Clock clock;

    public WeatherGovConverter(ObjectMapper mapper) {
        this(mapper, Clock.systemUTC());
    }

    /** Visible for tests, which pin the clock so fetchedUtc is deterministic. */
    public WeatherGovConverter(ObjectMapper mapper, Clock clock) {
        this.mapper = mapper;
        this.clock = clock;
    }

    @Override
    public String provider() {
        return "weather-gov";
    }

    @Override
    public int providerType() {
        return WeatherSourceType.WEATHER_GOV;
    }

    @Override
    public CanonicalForecast convert(String rawJson, String mli) throws ForecastConversionException {
        JsonNode root;
        try {
            root = mapper.readTree(rawJson);
        } catch (Exception ex) {
            throw new ForecastConversionException("Weather.gov payload is not valid JSON", ex);
        }

        JsonNode periods = root.path("properties").path("periods");
        if (!periods.isArray() || periods.isEmpty()) {
            throw new ForecastConversionException(
                    "Weather.gov payload has no properties.periods[]; this is not a gridpoint forecast");
        }

        Map<LocalDate, DayParts> byDay = new LinkedHashMap<>();
        for (JsonNode period : periods) {
            String start = period.path("startTime").asText(null);
            if (start == null) {
                continue;
            }
            LocalDate date;
            try {
                date = OffsetDateTime.parse(start).toLocalDate();
            } catch (Exception ex) {
                continue;
            }
            byDay.computeIfAbsent(date, d -> new DayParts()).accept(period);
        }

        List<ForecastDay> out = new ArrayList<>();
        for (Map.Entry<LocalDate, DayParts> entry : byDay.entrySet()) {
            DayParts parts = entry.getValue();
            JsonNode lead = parts.lead();
            if (lead == null) {
                continue;
            }

            Integer code = codeOf(lead.path("icon").asText(null));
            Double windKmh = windSpeedOf(lead.path("windSpeed").asText(null));

            out.add(new ForecastDay(
                    entry.getKey(),
                    ForecastDay.DAILY_SUMMARY_TIME,
                    parts.high(),
                    parts.low(),
                    parts.representativeTemperature(),
                    parts.daytimeTemperature(),
                    numberOf(lead.path("relativeHumidity")),
                    windKmh,
                    null,                                   // NWS gives a cardinal, never a bearing
                    trimToNull(lead.path("windDirection").asText(null)),
                    null,                                   // no pressure in /forecast
                    intOf(lead.path("probabilityOfPrecipitation")),
                    null,                                   // amount is not published by /forecast
                    null,
                    null,
                    code,
                    "om_" + (code == null ? "na" : code) + ".png",
                    trimToNull(lead.path("shortForecast").asText(null)),
                    trimToNull(lead.path("detailedForecast").asText(null))));
        }

        if (out.isEmpty()) {
            throw new ForecastConversionException("Weather.gov payload produced no usable forecast day");
        }

        return new CanonicalForecast(provider(), providerType(), mli, clock.instant(), out, root);
    }

    /** The up-to-two periods that make one calendar day. */
    private static final class DayParts {
        private JsonNode day;
        private JsonNode night;

        void accept(JsonNode period) {
            if (period.path("isDaytime").asBoolean(false)) {
                if (day == null) {
                    day = period;
                }
            } else if (night == null) {
                night = period;
            }
        }

        /** Daytime wins for the day's text and wind; a night-only day (the "Tonight" lead) uses that. */
        JsonNode lead() {
            return day != null ? day : night;
        }

        Double high() {
            return day != null ? temperature(day) : null;
        }

        Double low() {
            return night != null ? temperature(night) : null;
        }

        Double daytimeTemperature() {
            return day != null ? temperature(day) : null;
        }

        Integer representativeTemperature() {
            Double value = day != null ? temperature(day) : temperature(night);
            return value == null ? null : (int) Math.round(value);
        }

        private static Double temperature(JsonNode period) {
            if (period == null) {
                return null;
            }
            JsonNode value = period.path("temperature");
            return value.isNumber() ? value.asDouble() : null;
        }
    }

    private static Double numberOf(JsonNode measure) {
        JsonNode value = measure.path("value");
        return value.isNumber() ? value.asDouble() : null;
    }

    private static Integer intOf(JsonNode measure) {
        Double value = numberOf(measure);
        return value == null ? null : (int) Math.round(value);
    }

    static Double windSpeedOf(String text) {
        if (text == null || text.isBlank()) {
            return null;
        }
        Matcher matcher = WIND_SPEED.matcher(text);
        return matcher.find() ? Double.valueOf(matcher.group(1)) : null;
    }

    static Integer codeOf(String iconUrl) {
        if (iconUrl == null) {
            return null;
        }
        Matcher matcher = ICON_TOKEN.matcher(iconUrl);
        return matcher.find() ? TOKEN_TO_CODE.get(matcher.group(1)) : null;
    }

    private static String trimToNull(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }
}
