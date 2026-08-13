package com.fishfind.weather.canonical;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * Converts an Open-Meteo document ({@code $.hourly} + {@code $.daily}) into the canonical envelope.
 *
 * <p>Open-Meteo is already metric — °C, km/h, mm, hPa — so nothing is converted here. What this does is
 * the <em>reduction</em> that used to happen in T-SQL: the hourly arrays are parallel lists indexed by
 * position, and the database picked the latest hour of each day, summed rainfall into a 06:00–17:59
 * daytime bucket and everything else into a night bucket, and averaged the daytime temperature. That
 * arithmetic is reproduced exactly, so a station keeps reporting the same numbers across the rollout.
 *
 * <p>The daily arrays carry only {@code temperature_2m_max} / {@code temperature_2m_min}; every other
 * value comes from the chosen hour, which is why a day with no hourly rows is skipped rather than
 * emitted half-empty.
 */
@Component
public class OpenMeteoConverter implements ForecastConverter {

    private static final int DAY_START_HOUR = 6;
    private static final int DAY_END_HOUR = 17;

    /** WMO code → the text the legacy branch stored, kept identical so nothing downstream shifts. */
    private static final Map<Integer, String[]> CODE_TEXT = buildCodeText();

    private final ObjectMapper mapper;
    private final Clock clock;

    public OpenMeteoConverter(ObjectMapper mapper) {
        this(mapper, Clock.systemUTC());
    }

    /** Visible for tests, which pin the clock so the horizon and fetchedUtc are deterministic. */
    public OpenMeteoConverter(ObjectMapper mapper, Clock clock) {
        this.mapper = mapper;
        this.clock = clock;
    }

    @Override
    public String provider() {
        return "open-meteo";
    }

    @Override
    public int providerType() {
        return WeatherSourceType.OPEN_METEO;
    }

    @Override
    public CanonicalForecast convert(String rawJson, String mli) throws ForecastConversionException {
        JsonNode root;
        try {
            root = mapper.readTree(rawJson);
        } catch (Exception ex) {
            throw new ForecastConversionException("Open-Meteo payload is not valid JSON", ex);
        }

        JsonNode hourly = root.path("hourly");
        JsonNode times = hourly.path("time");
        if (!times.isArray() || times.isEmpty()) {
            throw new ForecastConversionException("Open-Meteo payload has no hourly.time[]");
        }

        Map<LocalDate, Double> maxByDay = dailyValues(root, "temperature_2m_max");
        Map<LocalDate, Double> minByDay = dailyValues(root, "temperature_2m_min");

        // one bucket per day, in the order the hours appear
        Map<LocalDate, DayBucket> buckets = new LinkedHashMap<>();
        for (int i = 0; i < times.size(); i++) {
            String stamp = times.get(i).asText(null);
            if (stamp == null) {
                continue;
            }
            LocalDateTime at;
            try {
                at = LocalDateTime.parse(stamp);
            } catch (Exception ex) {
                continue;
            }
            DayBucket bucket = buckets.computeIfAbsent(at.toLocalDate(), d -> new DayBucket());
            bucket.accept(at, i, hourly);
        }

        List<ForecastDay> out = new ArrayList<>();
        for (Map.Entry<LocalDate, DayBucket> entry : buckets.entrySet()) {
            LocalDate date = entry.getKey();
            DayBucket bucket = entry.getValue();
            if (bucket.latestIndex < 0) {
                continue;
            }
            Integer code = intAt(hourly, "weather_code", bucket.latestIndex);
            String[] words = CODE_TEXT.getOrDefault(code, new String[]{"Unknown", "Unknown weather condition"});
            Double windDeg = doubleAt(hourly, "wind_direction_10m", bucket.latestIndex);
            Double airTemp = doubleAt(hourly, "temperature_2m", bucket.latestIndex);

            out.add(new ForecastDay(
                    date,
                    bucket.latestTime.toLocalTime().toString().length() == 5
                            ? bucket.latestTime.toLocalTime() + ":00"
                            : bucket.latestTime.toLocalTime().toString(),
                    maxByDay.get(date),
                    minByDay.get(date),
                    airTemp == null ? null : (int) Math.round(airTemp),
                    bucket.daytimeMeanTemp(),
                    doubleAt(hourly, "relative_humidity_2m", bucket.latestIndex),
                    doubleAt(hourly, "wind_speed_10m", bucket.latestIndex),
                    windDeg,
                    ForecastDay.compass(windDeg),
                    intAt(hourly, "pressure_msl", bucket.latestIndex),
                    intAt(hourly, "precipitation_probability", bucket.latestIndex),
                    (int) Math.round(bucket.rainDay + bucket.rainNight),
                    bucket.rainDay,
                    bucket.rainNight,
                    code,
                    "om_" + (code == null ? "na" : code) + ".png",
                    words[0],
                    words[1]));
        }

        if (out.isEmpty()) {
            throw new ForecastConversionException("Open-Meteo payload produced no usable forecast day");
        }

        return new CanonicalForecast(provider(), providerType(), mli, clock.instant(), out, root);
    }

    /** Accumulates one day's hours: which is latest, and how the rain and daytime temperature add up. */
    private static final class DayBucket {
        private int latestIndex = -1;
        private LocalDateTime latestTime;
        private double rainDay;
        private double rainNight;
        private double daytimeTempSum;
        private int daytimeTempCount;

        void accept(LocalDateTime at, int index, JsonNode hourly) {
            if (latestTime == null || at.isAfter(latestTime)) {
                latestTime = at;
                latestIndex = index;
            }
            boolean daytime = at.getHour() >= DAY_START_HOUR && at.getHour() <= DAY_END_HOUR;
            Double rain = doubleAt(hourly, "rain", index);
            if (rain != null) {
                if (daytime) {
                    rainDay += rain;
                } else {
                    rainNight += rain;
                }
            }
            Double temp = doubleAt(hourly, "temperature_2m", index);
            if (daytime && temp != null) {
                daytimeTempSum += temp;
                daytimeTempCount++;
            }
        }

        Double daytimeMeanTemp() {
            return daytimeTempCount == 0 ? null : daytimeTempSum / daytimeTempCount;
        }
    }

    private static Map<LocalDate, Double> dailyValues(JsonNode root, String field) {
        Map<LocalDate, Double> out = new HashMap<>();
        JsonNode daily = root.path("daily");
        JsonNode times = daily.path("time");
        JsonNode values = daily.path(field);
        if (!times.isArray() || !values.isArray()) {
            return out;
        }
        for (int i = 0; i < times.size() && i < values.size(); i++) {
            String stamp = times.get(i).asText(null);
            if (stamp == null) {
                continue;
            }
            try {
                JsonNode value = values.get(i);
                out.put(LocalDate.parse(stamp), value.isNumber() ? value.asDouble() : null);
            } catch (Exception ignored) {
                // a malformed daily entry just leaves that day without a max/min
            }
        }
        return out;
    }

    private static Double doubleAt(JsonNode hourly, String field, int index) {
        JsonNode array = hourly.path(field);
        if (!array.isArray() || index < 0 || index >= array.size()) {
            return null;
        }
        JsonNode value = array.get(index);
        return value != null && value.isNumber() ? value.asDouble() : null;
    }

    private static Integer intAt(JsonNode hourly, String field, int index) {
        Double value = doubleAt(hourly, field, index);
        return value == null ? null : (int) Math.round(value);
    }

    private static Map<Integer, String[]> buildCodeText() {
        Map<Integer, String[]> m = new HashMap<>();
        m.put(0, new String[]{"Clear", "Clear sky"});
        m.put(1, new String[]{"Mainly clear", "Mainly clear sky"});
        m.put(2, new String[]{"Partly cloudy", "Partly cloudy"});
        m.put(3, new String[]{"Overcast", "Overcast"});
        m.put(45, new String[]{"Fog", "Fog"});
        m.put(48, new String[]{"Rime fog", "Depositing rime fog"});
        m.put(51, new String[]{"Light drizzle", "Light drizzle"});
        m.put(53, new String[]{"Drizzle", "Moderate drizzle"});
        m.put(55, new String[]{"Dense drizzle", "Dense drizzle"});
        m.put(61, new String[]{"Light rain", "Slight rain"});
        m.put(63, new String[]{"Rain", "Moderate rain"});
        m.put(65, new String[]{"Heavy rain", "Heavy rain"});
        m.put(71, new String[]{"Light snow", "Slight snow fall"});
        m.put(73, new String[]{"Snow", "Moderate snow fall"});
        m.put(75, new String[]{"Heavy snow", "Heavy snow fall"});
        m.put(80, new String[]{"Rain showers", "Slight rain showers"});
        m.put(81, new String[]{"Rain showers", "Moderate rain showers"});
        m.put(82, new String[]{"Heavy showers", "Violent rain showers"});
        m.put(95, new String[]{"Thunderstorm", "Thunderstorm"});
        return Map.copyOf(m);
    }
}
