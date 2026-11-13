package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Read-only queries behind {@code /api/v1/forecast/*} (1.31.0): the website's forecast pages as JSON for the
 * envfish-droid Forecast tab. Every method returns the database's own document, so the numbers are the
 * website's numbers:
 * <ul>
 *   <li>{@link #stations} — {@code dbo.fn_forecast_stations_json}, the Planning.aspx map
 *       ({@code dbo.fn_map_location}) cut to a radius;</li>
 *   <li>{@link #plot} — {@code dbo.fn_forecast_plot_json} (Plot.aspx's chart), {@code dbo.fn_plot_weather}
 *       (its day/weather calendar) and the 7-day score week of {@code dbo.fn_fish_reasoning_json};</li>
 *   <li>{@link #reasoning} — {@code dbo.fn_fish_reasoning_json} (Reasoning.aspx).</li>
 * </ul>
 * Arguments arrive validated and normalized by {@code ForecastController}.
 */
public interface ForecastQueryRepository {

    /**
     * @param fishId   canonical lower-case GUID
     * @param lat      -90..90
     * @param lon      -180..180
     * @param radiusKm 1..500
     * @param country  {@code CA}, {@code US} or {@code null} for both
     * @param limit    1..200
     * @return {@code {fishId, fish, lat, lon, radiusKm, country, limit, total, stations}}, or {@code null} for an
     *         unknown fish
     */
    JsonNode stations(String fishId, double lat, double lon, int radiusKm, String country, int limit);

    /**
     * @return {@code {sid, fishId, plot, calendar, week}}, or {@code null} when the station is unknown or the fish
     *         is not listed there (the map never links such a pair)
     */
    JsonNode plot(int sid, String fishId);

    /**
     * @param day 0..6 days from now (0 = today, the map's value)
     * @return the reasoning document, or {@code null} when the station is unknown or the fish is not listed there
     */
    JsonNode reasoning(int sid, String fishId, int day);
}
