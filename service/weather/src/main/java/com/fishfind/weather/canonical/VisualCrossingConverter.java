package com.fishfind.weather.canonical;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * Converts a Visual Crossing timeline document ({@code $.days[]}) into the canonical envelope.
 *
 * <p><b>Units are the trap.</b> {@code VisualCrossingFetcher} requests {@code unitGroup=us}, so the
 * document is °F, mph and inches while everything downstream expects metric. The request deliberately
 * stays in US units during the rollout: the legacy T-SQL branch converts the same way, so the embedded
 * {@code raw} document remains a valid fallback for exactly these bytes. Switching the fetcher to
 * {@code unitGroup=metric} would double-convert anything still taking the legacy path.
 *
 * <p>Two behaviours are carried over deliberately from that branch so the two paths agree during the
 * rollout: the horizon is clipped to today..today+6 (the document runs 15 days and its first day is
 * often <em>yesterday</em> in the station's time zone), and the day's rainfall is split evenly between
 * day and night because a daily document has no hourly resolution — the sum is what consumers use.
 */
@Component
public class VisualCrossingConverter implements ForecastConverter {

    /** Provider icon → the WMO-style codes the Open-Meteo path already stores, keeping one icon namespace. */
    private static final Map<String, Integer> ICON_TO_CODE = Map.ofEntries(
            Map.entry("clear-day", 0),
            Map.entry("clear-night", 0),
            Map.entry("wind", 1),
            Map.entry("partly-cloudy-day", 2),
            Map.entry("partly-cloudy-night", 2),
            Map.entry("cloudy", 3),
            Map.entry("fog", 45),
            Map.entry("rain", 63),
            Map.entry("showers-day", 80),
            Map.entry("showers-night", 80),
            Map.entry("snow", 73),
            Map.entry("snow-showers-day", 71),
            Map.entry("snow-showers-night", 71),
            Map.entry("sleet", 65),
            Map.entry("hail", 95),
            Map.entry("thunder-rain", 95),
            Map.entry("thunder-showers-day", 95),
            Map.entry("thunder-showers-night", 95));

    /** Same horizon the Open-Meteo document produces. */
    static final int HORIZON_DAYS = 7;

    private final ObjectMapper mapper;
    private final Clock clock;

    public VisualCrossingConverter(ObjectMapper mapper) {
        this(mapper, Clock.systemUTC());
    }

    /** Visible for tests, which pin the clock so the horizon and fetchedUtc are deterministic. */
    public VisualCrossingConverter(ObjectMapper mapper, Clock clock) {
        this.mapper = mapper;
        this.clock = clock;
    }

    @Override
    public String provider() {
        return "visual-crossing";
    }

    @Override
    public int providerType() {
        return WeatherSourceType.VISUAL_CROSSING;
    }

    @Override
    public CanonicalForecast convert(String rawJson, String mli) throws ForecastConversionException {
        JsonNode root;
        try {
            root = mapper.readTree(rawJson);
        } catch (Exception ex) {
            throw new ForecastConversionException("Visual Crossing payload is not valid JSON", ex);
        }

        JsonNode days = root.path("days");
        if (!days.isArray() || days.isEmpty()) {
            throw new ForecastConversionException(
                    "Visual Crossing payload has no days[]; got members " + fieldNames(root));
        }

        LocalDate today = LocalDate.now(clock.withZone(ZoneOffset.UTC));
        LocalDate last = today.plusDays(HORIZON_DAYS - 1L);

        List<ForecastDay> out = new ArrayList<>();
        for (JsonNode day : days) {
            String text = day.path("datetime").asText(null);
            if (text == null) {
                continue;
            }
            LocalDate date;
            try {
                date = LocalDate.parse(text);
            } catch (Exception ex) {
                continue;
            }
            if (date.isBefore(today) || date.isAfter(last)) {
                continue;
            }

            Double tempMaxC = fahrenheitToCelsius(number(day, "tempmax"));
            Double tempMinC = fahrenheitToCelsius(number(day, "tempmin"));
            Double tempMeanC = fahrenheitToCelsius(number(day, "temp"));
            Double precipMm = inchesToMillimetres(number(day, "precip"));
            Double windKmh = milesToKilometres(number(day, "windspeed"));
            Double windDeg = number(day, "winddir");
            Integer code = ICON_TO_CODE.get(day.path("icon").asText(""));

            out.add(new ForecastDay(
                    date,
                    ForecastDay.DAILY_SUMMARY_TIME,
                    tempMaxC,
                    tempMinC,
                    round(tempMeanC),
                    tempMeanC,
                    number(day, "humidity"),
                    windKmh,
                    windDeg,
                    ForecastDay.compass(windDeg),
                    round(number(day, "pressure")),
                    round(number(day, "precipprob")),
                    round(precipMm),
                    half(precipMm),
                    half(precipMm),
                    code,
                    "om_" + (code == null ? "na" : code) + ".png",
                    text(day, "conditions"),
                    text(day, "description")));
        }

        if (out.isEmpty()) {
            throw new ForecastConversionException(
                    "Visual Crossing payload has no day inside " + today + ".." + last
                            + "; the document may be entirely in the past");
        }

        return new CanonicalForecast(provider(), providerType(), mli, clock.instant(), out, root);
    }

    private static Double fahrenheitToCelsius(Double f) {
        return f == null ? null : (f - 32.0) * 5.0 / 9.0;
    }

    private static Double inchesToMillimetres(Double inches) {
        return inches == null ? null : inches * 25.4;
    }

    private static Double milesToKilometres(Double miles) {
        return miles == null ? null : miles * 1.609344;
    }

    /** A daily document cannot say when the rain fell, so the total is split rather than claimed for daylight. */
    private static Double half(Double total) {
        return total == null ? null : total / 2.0;
    }

    private static Integer round(Double value) {
        return value == null ? null : (int) Math.round(value);
    }

    private static Double number(JsonNode node, String field) {
        JsonNode value = node.get(field);
        return value == null || !value.isNumber() ? null : value.asDouble();
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node.get(field);
        return value == null || value.isNull() ? null : value.asText();
    }

    private static String fieldNames(JsonNode root) {
        List<String> names = new ArrayList<>();
        root.fieldNames().forEachRemaining(names::add);
        return names.toString();
    }
}
