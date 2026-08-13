# Changelog

All notable changes for this service must be recorded in this file.

## Unreleased

- **weather.gov now fetches the GRIDPOINT FORECAST instead of the latest observation**, so it finally
  produces forecast rows. The service was calling `/stations/{id}/observations/latest` -- current
  conditions, which no converter could honestly turn into a multi-day forecast no matter what parsed
  it. It now calls `/points/{lat},{lon}` for the grid cell's forecast URL and then that URL, with
  `units=si` so temperatures arrive in degC and winds in km/h and nothing needs converting.

  `WeatherGovConverter` assembles NWS **periods** into calendar days: each period covers about half a
  day and is flagged `isDaytime`, so the daytime one carries the high and the night one the low. A
  response issued in the evening starts with "Tonight", giving a day with no daytime half at all --
  that case is covered by a test rather than left to chance. `windSpeed` is a human string
  ("10 to 15 km/h"), so the upper bound is parsed out.

  Two honest gaps, both deliberate: `/forecast` publishes a precipitation CHANCE but never a QUANTITY
  (that lives in the raw `/gridpoints` document), so `precipMm` stays null rather than being invented
  as 0 -- which would read as "no rain fell". And NWS gives a cardinal direction, never a bearing, so
  `windDegrees` is null while `windDirection` is set.

  Costs one extra call per station: the forecast URL is not derivable from a coordinate. Same shape as
  Wunderground, which has always cost two.

  `WeatherGovStationResolver` and its `dbo.weather_gov_station` cache are no longer on this path -- a
  forecast is keyed by grid cell, not by observation station. Both are left in place for the
  observation endpoint but now have no caller here.

- **CA daily limits raised to 2,300** (`open-meteo`, `weather-canada` in `application.yml`, and the
  `weather-canada` `@Value` fallback) so one day's work reaches every Canadian station rather than
  rotating a slice -- below the eligible count the view's `ORDER BY NEWID()` merely shuffles which
  stations get weather. Both are free public feeds and the worker never requests more stations than
  exist, so the higher cap costs nothing. Mirrors the same change in the C# port.

  Note `WeatherStationRepository.DEFAULT_STATION_LIMIT` (1400) and `US_WEATHER_GOV_STATION_LIMIT` (900)
  are dead: the worker always calls the two-argument `findSupportedStations(country, stationLimit)` with
  a limit derived from the provider budget. They are left in place but would silently cap a pass if a
  caller ever used the one-argument overload; the C# port has already removed its equivalents.

- **Weather payloads are now converted to a canonical envelope before they are stored**, instead of
  the raw provider document being parsed by T-SQL inside a database trigger. Each provider gets a
  `ForecastConverter` (`canonical/` package) producing `fishfind.weather.forecast/v1`: `schema`,
  `provider`, `providerType`, `mli`, `fetchedUtc`, `days[]` already metric and already one object
  per day, and `raw` -- the provider's own document, embedded so a stored payload can still be
  inspected and replayed.

  Why: parsing lived in `dbo.TR_ows_meteo`, which **cannot raise** -- an error there aborts this
  service's `UPDATE` and discards the payload just fetched -- so a document no parser understood
  produced no rows and no error. A whole provider (Visual Crossing, ~230 US stations) went unnoticed
  that way. A converter runs here, so it **throws**, and the station is counted as failed in the
  cycle report like any other failure. Adding a provider now needs no database change.

  Converters in this change: `OpenMeteoConverter` (already metric; performs the hourly-to-daily
  reduction the database used to do -- latest hour of each day wins, rainfall splits at 06:00-17:59,
  daytime temperature is a mean) and `VisualCrossingConverter` (converts F to C, mph to km/h,
  inches to mm; clips the 15-day document to today..today+6; splits daily rainfall evenly because a
  daily document has no hourly resolution). Both reproduce the T-SQL arithmetic exactly so station
  numbers do not shift during the rollout.

- **`ows_meteo.type` now records WHICH PROVIDER served each station.** It was hardcoded to `2` for
  every provider, which made the column useless as provenance and forced the database to infer the
  document's shape. `WeatherDataRepository.saveStationData` takes the type, and callers pass their
  own `WeatherSourceType`: Open-Meteo 2, Visual Crossing 4, weather.gov 5, Environment Canada 6,
  Weather Underground 7, Google Weather 8. Note `fallbackSave` had to grow the same parameter, or
  resilience4j cannot bind the fallback.

  The four observation-only providers keep storing their raw document and simply gain a correct
  type; nothing they produce could become a forecast row either way. **weather.gov is fetched via
  `/observations`, not the gridpoint forecast**, so it is not forecast-capable as currently wired --
  making it so needs a fetcher change, not a converter.

  Requires the matching database change (`sp_ows_meteo_canonical` + `TR_ows_meteo` envelope
  routing), which is already applied to prod. The legacy per-provider branches remain, so this
  service and the C# port can be deployed independently and in any order.

- **Fix: every US station was being skipped.** `vwWeatherForecastToDay` is built from
  `dbo.WaterStation`, so `mli` is a WATER gauge id -- all 2,219 US rows are numeric USGS site
  numbers, never NWS call signs, so `/stations/{mli}/observations` returned 404 for every one of
  them, permanently. The gauge's COORDINATE is now resolved to a nearby NWS station via
  `/points/{lat},{lon}/stations` and the mapping cached in `dbo.weather_gov_station`
  (`WeatherGovStationResolver` + `WeatherGovStationRepository`). Measured on the C# port: 0/25
  sampled gauges resolved by mli, 25/25 by coordinate; live, 67/67 resolved with 2 skips.
  Two API details this depends on: coordinates must be rounded to 4 decimal places, and `/points`
  answers with a 301 that must be followed.

- **Fix: the daily API allowance was booked up front**, so any restart forfeited the rest of the
  day. `WeatherApiUsageTracker` now charges one station at a time immediately before each fetch
  (`snapshot` + `tryConsume` replace `reserve`), so an interrupted cycle costs only what it used --
  which also stays true after a hard kill, where nothing can credit anything back. Measured on the
  C# port: three restarts had burned 3,200 station-slots for ~154 stations of real work.

- **Flag which providers cannot serve which gauge.** New
  `dbo.weather_station_coverage` (+ `fn_weather_uncovered_stations`, `sp_save_weather_station_coverage`),
  written by `StationWorker` as each station completes. Only PROCESSED and SKIPPED are coverage
  facts; a FAILURE is transient and is deliberately not recorded. A fallback worker reads the gaps
  with their coordinates. SWOB has genuine geographic gaps -- roughly one Canadian gauge in six --
  which previously skipped silently forever, invisible because a fully-skipped cycle still reports
  healthy.

- **Weather Canada bbox radius 0.05 -> 0.5 degrees.** At 0.05 (~5.5 km) NO sampled station matched
  a SWOB site; 0.25 recovered 12/25 and 0.5 recovered 21/25.

- **Per-provider `<PROVIDER>_ENABLE` toggles and `<PROVIDER>_TIMEOUT` pacing.** A disabled worker,
  or a metered provider with a blank API key, is not started at all rather than started and failing
  every station (which would push the cycle's failure rate past the threshold and suppress
  post-processing for a country whose other providers were healthy). Pacing is now derived from the
  provider's own daily-limit over 12 hours instead of the day's station count over 8 hours, making
  the request rate predictable per provider.

- **A failed cycle now waits one minute before retrying.** Every failure at that level happens
  before the first station (the station COUNT query), so with the database down the loop spun at
  thousands of iterations a second across five workers, pinning a core and burying the log.

All of the above were first made and verified in the C# port (`efcs-backend/service/weather`,
releases 10.0.1-10.0.3) and are ported back here. 137 tests pass.


- Changed routine per-station success logs for fetch/save/processed events from INFO to DEBUG.
- Kept startup verification success logs at INFO so deployment startup checks remain visible.

## [1.0.0] - 2026-06-22

- Initial documented service version for `weather-station-pusher`.
