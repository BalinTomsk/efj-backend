# Changelog

All notable changes for `water-station-pusher` (Java) are recorded here. Earlier releases were recorded only in
`docs/specification.md` and `AGENTS.md`; this file starts at 2.0.0.

## [2.0.0] - 2026-11-25 (built, not deployed)

The water data leaves SQL Server: this service now writes the MySQL `envdata` database on debian-mysql, as a
functional copy of the C# twin `efcs-backend/service/waterservice` 11.0.0 (env_service plan,
`efcs-backend/service/env_service/docs/env_service_plan.md`). It was stopped at plan step 7 (2026-11-25) as a
"legacy writer"; it now runs beside the C# service again, both writing envdata. Deploy needs the `waterservice`
MySQL account for jnode's VPC address (10.118.0.3) and the `MYSQL_*` lines in the shared env file first.

### Changed
- **Database: MySQL `envdata` instead of SQL Server.** `mssql-jdbc` -> `mysql-connector-j`. The connection comes
  from the NEW keys `MYSQL_URL` (`jdbc:mysql://<host>:3306/envdata?sslMode=REQUIRED`) / `MYSQL_USERNAME` /
  `MYSQL_PASSWORD`, built in code (`EnvdataDataSourceConfig`, `MySqlUrl`), so the git-ignored `application.yml`
  needs no change. `DB_URL` / `DB_USERNAME` / `DB_PASSWORD` stay in the env file as the SQL Server connection, so a
  rollback to 1.14.0 needs no file change. Every call goes through an envdata view or procedure:
  `v_station_water_due`, `sp_water_save_ca`, `sp_water_save_us`, `sp_station_503_*`, `sp_job_run_record`,
  `sp_clean_old_water_data`.
- **CA: one call per 500 readings** with the readings as one JSON array, instead of one `sp_UpdateWaterData` per
  reading in a JDBC batch.
- **US: all series of a station in ONE call**, as `UsSeriesReading(name, unit, day, value)` points instead of a
  legacy XML document per series. envdata merges a day's series into one reading, so oxygen, turbidity, pH, etc.
  all reach the station's current state; it stores pressure in **mm Hg** (was hPa), pH as the real value and oxygen
  in mg/L only. This replaces the 1.14.0 text batch of `sp_push_us_water_data` EXECs.
- **HTTP 503 back-off state lives in envdata** (`station` row), the same rows the C# twin writes.
- **The SQL retry/breaker ignores SQLSTATE 45000** (an envdata procedure's own refusal, e.g. an unknown station):
  a bad request, not an outage, so it is neither retried nor counted toward opening the breaker (`SqlFailures`).
- `USGS_API_KEY`: the Java pair uses its own key (plan decision 3), already in jnode's env file.

### Removed
- **The fish hand-over** (`dbo.spPushSpeciesFromLakeToStation` after a successful cycle). A successful cycle is
  recorded in envdata `job_run` instead (service `waterservice`; job `water-ca`, `water-us`, or `water` for a
  console cycle; status `ok` / `partial`), and env_service pushes species and recomputes probabilities in SQL Server.

### Tests
- `WaterEngineTest`: the real repositories against a real MySQL engine (`WATER_TEST_MYSQL`, optional
  `WATER_TEST_MYSQL_APP` with production's grants). 106 tests, 6 of them on a local MySQL 8.0.46 with envdata built
  from `envfish-db/mysql/envdata`.

## [1.14.0] - 2026-11-20 (LIVE on debian-jnode until step 7, 2026-11-25)

- US series of a station sent in one round trip (text batch of `sp_push_us_water_data` EXECs).
