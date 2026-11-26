# water-station-pusher — Claude Context

> This file captures the full specification and architectural rules needed to recreate,
> extend, or debug the `water-station-pusher` Spring Boot service.
> Source: `efj-backend/service/waterservice/docs/specification.md`

---

## Dual-service redundancy (Java + C#) — do NOT retire either

**Two independent implementations of this service run in parallel in production, by design.** This Java
(Spring Boot) service and a **C# / .NET 10 port** (`efcs-backend/service/waterservice`) both poll the same
Environment Canada / USGS feeds *independently* and upsert into the **same** database. This is an
**intentional "double warranty"** on incoming data — redundancy, **not** a migration. **Keep both running;
do not decommission either one to "avoid double-writes."**

Since 2.0.0 (2026-11-25) both write the MySQL **`envdata`** database on debian-mysql (env_service plan,
`efcs-backend/service/env_service/docs/env_service_plan.md`), and this service is a functional copy of the C#
11.0.0 one: same keys (`MYSQL_URL` / `MYSQL_USERNAME` / `MYSQL_PASSWORD`), same procedures, same `job_run`
records. Why running both is safe: `sp_water_save_ca` / `sp_water_save_us` upsert by `(station, time)`, so
concurrent writes from the two services collapse to the same rows; the HTTP 503 back-off lives in envdata's
`station` row, shared by both. If one pipeline is down, slow, or a feed fetch fails on one side, the other still
lands the data. The post-cycle steps (`sp_job_run_record`, `sp_clean_old_water_data`) run once per service per
cycle; env_service hands over each recorded cycle, so the duplication is expected and tolerated. SQL Server's
water tables are frozen; nothing here writes SQL Server any more. The Java pair uses its own `USGS_API_KEY`
(plan decision 3).

Deployments: this Java service runs on droplet **`debian-jnode`** (`68.183.196.166`); the C# port runs on
**`debian-csnode`** (`137.184.218.128`). Each repo has its own `docs/do-update.md`.

## Keeping docs in sync — IMPORTANT

`docs/specification.md` is the **single source of truth** used to recreate this service from scratch.
It must always reflect the current state of the code.

**Rules:**

- Whenever **any source file** (`*.java`, `pom.xml`, `application.yml`, `logback-spring.xml`,
  `Dockerfile`, etc.) is created, modified, or deleted — update `docs/specification.md` to match.
- Whenever **this `AGENTS.md`** is updated — apply the same change to `docs/specification.md`
  if it affects behaviour, structure, or configuration.
- `docs/specification.md` must be sufficient on its own for a developer (or Claude) to
  **fully recreate the service from scratch** with no other context. Keep it complete and accurate.
- Do not leave `docs/specification.md` describing behaviour that no longer exists, or omitting
  behaviour that was added.
- Treat every code change as a two-step commit: ① change the code, ② update `docs/specification.md`.


---

##IMPORTANT
Explicitly follows database schema at:
- @srv/../../envfish-db

- **DO NOT COMMIT without explicit user permission.**
- **DO NOT PUSH without explicit user permission.**
- **DO NOT CREATE, MERGE, OR CLOSE PULL REQUESTS without explicit user permission.**
- When code changes are requested, make the file edits and stop with a status summary unless the
  user explicitly asks for Git actions.

- Local project skills live under `.claude/skills` inside this service. When the user asks to run or
  use a skill by name, you MUST first look for and use `.claude/skills/<skill-name>/SKILL.md`.
  Only search repo-level `Skills` directories or global skill registries if that project-level file
  does not exist.

- **Before making ANY database change** (schema, stored proc, function, view, seed data, or any
bug fix that touches the DB), **read `c:\envoinx\fishfind\envfish-db\AGENTS.md `
first** — it is the authoritative DB workflow (never edit the generated `ffi2.sql`; edit the
`scriptNN_*.sql` sources; test-first: a FAILING unit test to confirm the bug, then a PASSING one
to verify the fix; run `mssql\UNIT_TESTS\autorun.bat`). That file lives in the separate
`efj-backend` repo and does NOT auto-load in this project, so it must be opened explicitly.



## Local Claude skills

- Deployment skill: `.claude/skills/update-water/SKILL.md`
- Use `update-water` when asked to deploy/update/release `water-station-pusher`, build and push a tagged Docker image, install it on the DigitalOcean droplet, or verify the deployed service.
- A version tag is required. If the user does not provide one, ask for it before running deployment commands.
- The deployment runbook/source of truth is `docs/do-update.md`; keep it aligned with the skill before deploying.

---

## Project identity

| Key | Value |
|-----|-------|
| Service name | `water-station-pusher` |
| Language | Java 21 |
| Build | Maven |
| Framework | Spring Boot 3.3.x |
| Main class | `com.fishfind.water.WaterStationPusherApplication` |

---

## Goal

- Poll supported Canadian and US water stations from envdata (`v_station_water_due`).
- Download each **CA** station's hourly hydrometric CSV from Environment Canada.
- Read each **US** station's latest values from one USGS Water Data API snapshot per cycle
  (`latest-continuous`; key in `USGS_API_KEY`). The legacy WaterServices feed dies 2027-02-22.
- Parse readings and upsert them into envdata (`sp_water_save_ca`, 500 readings as one JSON array per call;
  `sp_water_save_us`, all series of a station in one call; pressure stored in mm Hg).
- When at least one station succeeds in a cycle, record it in envdata `job_run` (`sp_job_run_record`; job
  `water-ca` / `water-us`, or `water` for a console cycle; status `ok` / `partial`). env_service then does the fish
  hand-over in SQL Server (species push + probability update); this service no longer touches SQL Server.
- After each worker cycle, synchronously run retention: `sp_clean_old_water_data(NULL)`.
- Log failures and skipped unpublished-source events; **do not disable stations automatically**.

---

## Package layout

```
com.fishfind.water
├── domain
│   ├── Reading.java            # stationId, stamp (OffsetDateTime), waterLevel, discharge
│   ├── StationRef.java         # mli, state, tz  (record)
│   └── UsSeriesReading.java    # name, unit, local day, value (one point per USGS series)
├── repo
│   ├── WaterDataRepository.java
│   ├── StationHttp503BackoffRepository.java
│   └── WaterStationRepository.java
├── config
│   ├── EnvdataDataSourceConfig.java         # Hikari datasource + JdbcTemplate from MYSQL_* (2.0.0)
│   ├── MySqlUrl.java                        # MYSQL_URL defaults (sslMode=REQUIRED, connectTimeout, UTC)
│   ├── SqlFailures.java                     # sqlRetry/sqlBreaker ignore SQLSTATE 45000
│   ├── DotenvEnvironmentPostProcessor.java  # local .env → low-precedence property source
│   ├── WorkerConfig.java                     # cycleScheduler + countryPassExecutor beans
│   └── HttpClientConfig.java                 # pooled RestClient (JDK HttpClient) for source feeds
├── service
│   ├── CsvFetcherCA.java
│   ├── UsgsWaterDataClient.java    # USGS Water Data API snapshot + site time zones
│   ├── UsgsParameterMap.java       # USGS parameter code -> legacy name/unit for the proc
│   ├── StationProcessorCA.java
│   ├── StationProcessorUS.java
│   ├── StationProcessorBase.java   # shared exception handling; process() returns success boolean
│   ├── StationWorker.java          # ApplicationRunner: schedules + runs the hourly cycle
│   ├── ConsoleDebugRunner.java     # --console: runs one cycle via StationWorker.runCycle
│   └── StationPostProcessingService.java
└── web
    └── HealthController.java       # GET /health → { status, version, uptime }
```

---

## Required files (complete list)

```
pom.xml
src/main/java/com/fishfind/water/WaterStationPusherApplication.java
src/main/java/com/fishfind/water/domain/Reading.java
src/main/java/com/fishfind/water/domain/StationRef.java
src/main/java/com/fishfind/water/domain/UsSeriesReading.java
src/main/java/com/fishfind/water/repo/WaterDataRepository.java
src/main/java/com/fishfind/water/repo/WaterStationRepository.java
src/main/java/com/fishfind/water/service/CsvFetcherCA.java
src/main/java/com/fishfind/water/service/UsgsWaterDataClient.java
src/main/java/com/fishfind/water/service/UsgsParameterMap.java
src/main/java/com/fishfind/water/domain/UsgsObservation.java
src/main/java/com/fishfind/water/service/StationProcessorCA.java
src/main/java/com/fishfind/water/service/StationProcessorUS.java
src/main/java/com/fishfind/water/service/StationWorker.java
src/main/java/com/fishfind/water/service/ConsoleDebugRunner.java
src/main/java/com/fishfind/water/service/StationPostProcessingService.java
src/main/java/com/fishfind/water/web/HealthController.java
src/main/java/com/fishfind/water/config/DotenvEnvironmentPostProcessor.java
src/main/java/com/fishfind/water/config/EnvdataDataSourceConfig.java
src/main/java/com/fishfind/water/config/MySqlUrl.java
src/main/java/com/fishfind/water/config/SqlFailures.java
src/main/java/com/fishfind/water/config/WorkerConfig.java
src/main/java/com/fishfind/water/config/HttpClientConfig.java
src/main/resources/META-INF/spring/org.springframework.boot.env.EnvironmentPostProcessor.imports
src/main/resources/application.yml
src/main/resources/logback-spring.xml
.env.example          (project root, placeholder values only)
Dockerfile
.dockerignore
```

**Never include:** real `.env`, secrets, or `.env` under `src/main/resources`.

---

## Dependencies (pom.xml)

- `spring-boot-starter`
- `spring-boot-starter-web`
- `spring-boot-starter-jdbc`
- `spring-boot-starter-aop`
- `spring-boot-starter-actuator`
- `io.micrometer:micrometer-registry-prometheus` (runtime)
- MySQL Connector/J (`com.mysql:mysql-connector-j`, Boot-managed; replaced `mssql-jdbc` in 2.0.0)
- `io.github.resilience4j:resilience4j-spring-boot3`
- `commons-csv` (used for CA CSV parsing)
- `io.github.cdimascio:dotenv-java`
- SLF4J + Logback (via Spring Boot default)

---

## Startup / credential loading

1. `main()` only calls `SpringApplication.run`. Credential loading is handled by a Spring
   `EnvironmentPostProcessor` (`com.fishfind.water.config.DotenvEnvironmentPostProcessor`), registered in
   `src/main/resources/META-INF/spring/org.springframework.boot.env.EnvironmentPostProcessor.imports`.
2. Spring resolves `MYSQL_URL`, `MYSQL_USERNAME`, `MYSQL_PASSWORD` from the process environment / JVM system
   properties / the `.env` file. `DB_URL` / `DB_USERNAME` / `DB_PASSWORD` stay in the env file as the SQL Server
   connection (a rollback to 1.14.0 needs no file change) but are not read since 2.0.0.
3. For local dev, the post-processor loads a `.env` file and registers it as the **lowest-precedence** property
   source (`addLast`):
   - Default location: project root; override with `DOTENV_PATH` env var.
   - Only keys declared in the file are imported (`Dotenv.Filter.DECLARED_IN_ENV_FILE`).
   - Real env vars / system properties always win over `.env`.
4. **SECURITY:** credentials are **never** copied into JVM-global system properties (no `System.setProperty`),
   so they cannot leak via `System.getProperties()`, heap dumps, or diagnostic tooling.

---

## Datasource config (`EnvdataDataSourceConfig`, 2.0.0)

- Built in code, not from `spring.datasource.*`: `application.yml` is git-ignored and still maps
  `spring.datasource` to the SQL Server `DB_*` keys. Declaring the `DataSource` bean makes Boot's datasource
  auto-configuration back off, so those keys are never used. A missing `MYSQL_URL` fails startup.
- `MYSQL_URL` is a JDBC URL, `jdbc:mysql://10.118.0.6:3306/envdata?sslMode=REQUIRED`. `MySqlUrl.normalize` adds,
  only when the URL names none: `sslMode=REQUIRED` (the accounts are REQUIRE SSL), `connectTimeout=15000`,
  `connectionTimeZone=UTC`. A native MySqlConnector string (accepted by the C# twin) is refused.
- Hikari: `water-hikari`, max 4, min idle 1, connection timeout 30 s, max lifetime 29 min, keepalive 5 min,
  validation 5 s. `JdbcTemplate` query timeout 120 s (the C# twin's command timeout).
- The `waterservice` MySQL account has EXECUTE on `envdata.*` and SELECT on `v_station_water_due` only: every
  call is a view read or a `CALL`. OUT parameters are passed as session variables (`@out_job_run_id`), never read
  through a `CallableStatement` (which needs procedure metadata the account cannot read).

---

## Worker behaviour

### Lifecycle (Spring-managed — no hand-managed threads)

- `WorkerConfig` provides two Spring beans (graceful shutdown on context close):
  - `cycleScheduler` — 2-thread `ThreadPoolTaskScheduler` (`water-cycle-`), one thread per country task. A
    cron task is rescheduled only after its run ends ⇒ an overrunning cycle delays that country's next
    trigger instead of overlapping, and never blocks the other country.
  - `countryPassExecutor` — 2-thread `ThreadPoolTaskExecutor` (`water-pass-`) for parallel CA/US passes in
    console mode.
- `StationWorker` (`ApplicationRunner`): if `--console`, schedule nothing; otherwise register **two
  independent** recurring tasks on `cycleScheduler`, one per country, each via a `CronTrigger` from
  `water.worker.cron` (default `0 0 * * * *`), running `runCountryCycle(country)`: that country's pass, then
  post-processing. A slow CA pass must not hold back the US refresh (one task awaiting both passes once held
  US data to a refresh per ~28 h). Post-processing is lock-serialised between the two tasks.
- A scheduled pass that fails **before its first station** (backoff refresh, station list, USGS snapshot) is
  retried in the same cycle (`pass-start-retries` x `pass-start-retry-delay-ms`); a DB outage at the top of the
  hour used to cost that country the whole cycle (2026-11-20). A later failure is never retried.

### Console cycle (`runCycle`)

1. Run CA and US passes **in parallel** on `countryPassExecutor`; a failure of one country is isolated/logged.
2. Each pass (`runOnce`) loads its stations, processes them one by one sleeping `pause-between-stations-ms`
   **between** stations only — never after the last (interrupt-aware), and returns the count processed **successfully**.
3. Record the cycle in envdata `job_run` **once** for the combined result (job `water`), and **only if ≥1
   station succeeded** (scheduled country cycles apply the same rule to their own pass, jobs `water-ca` /
   `water-us`). Status `ok` when no station failed, else `partial` with note `failed=<n>`; `items` = stations
   processed successfully.
4. Run retention **after every cycle** (console or scheduled) through `sp_clean_old_water_data(NULL)`.
5. Failure semantics: a `job_run` failure never blocks cleanup; if cleanup **also** fails, the record
   exception propagates with the cleanup exception as **suppressed** (no finally-masking). The
   cycle-completed summary log is always emitted.
6. Shutdown-safe pass startup: executor rejection ⇒ failed future (empty pass), and `awaitPass` handles
   `CompletionException` **and** `CancellationException`.
- `StationProcessorBase.process(...)` returns `boolean` so the cycle knows whether anything succeeded.

### Configurable properties

```yaml
water:
  worker:
    cron: "0 0 * * * *"               # default — top of every hour (Spring 6-field cron)
    pause-between-stations-ms: 500    # default (1000 made the CA pass overrun the hour)
    connect-timeout-ms: 15000         # default
    read-timeout-ms: 30000            # default
    pass-start-retries: 3             # default; retries of a scheduled pass that failed before its first station
    pass-start-retry-delay-ms: 60000  # default; longer than the 30 s sqlBreaker open state
```

---

## Console / debug mode (`--console`)

- Activated by `--console` command-line arg.
- Optional: `--station=<MLI>` to filter to one station.
- Delegates to `StationWorker.runCycle(station)` — one cycle: both countries in parallel + a single
  post-processing run. Identical to scheduled behavior.

---

## Station query (`WaterStationRepository`)

- View: envdata `v_station_water_due` (supported stations; port of MSSQL `vwWaterStation`)
- SQL: `SELECT mli, state, tz FROM v_station_water_due WHERE country = ? ORDER BY stamp DESC` (newest reading first)
- CA worker filter: `country = 'CA'`
- US worker filter: `country = 'US'`
- Model: `StationRef(String mli, String state, int tz)` — simple record.

---

## HTTP transport (`HttpClientConfig`)

- Shared `RestClient` bean over the JDK `HttpClient` (pooled/keep-alive) — replaces per-request `HttpURLConnection`.
- Connect timeout on the client, read timeout on the request factory (from `water.worker.*-timeout-ms`).
- Honest `User-Agent` (`water.worker.user-agent`), **not** a spoofed browser string.
- Resilience is declarative on the fetch methods (no `@TimeLimiter` — blocking call, transport timeouts bound it).

## CA fetch (`CsvFetcherCA`)

- URL: `https://dd.weather.gc.ca/today/hydrometric/csv/{STATE}/hourly/{STATE}_{MLI}_hourly_hydrometric.csv`
- SECURITY: built as a RestClient **URI template** — `state`/`mli` are strictly URL-encoded, so a hostile
  or corrupt DB row cannot rewrite the request path (second-order injection).
- `fetch` returns the raw CSV body `String`. `@Retry("httpRetry")` + `@CircuitBreaker("caFeed")`.
- HTTP 404 → `FileNotFoundException` → station skipped (ignored by retry + breaker). The exception message names the feed, station, and state (self-sufficient without caller context).
- 5xx / network errors are retried; sustained failures open `caFeed`.

---

## US fetch (`UsgsWaterDataClient`)

- The legacy WaterServices `nwis/iv` feed is decommissioned 2027-02-22 (slowed from 2026-11-16). US data
  comes from the USGS Water Data API, rate-limited per key (1,000/hour, shared with the C# service).
- `fetchLatest(mli)` pages `{water.worker.usgs-base-url}/latest-continuous/items` (limit 50000, follow
  `rel=next`) once per US pass: ~2-3 requests instead of ~9,500. `mli` restricts it to one site.
- `ensureTimeZones(mlis)` caches each site's local zone (from `monitoring-locations`) once per process.
- Key: `USGS_API_KEY` secret, sent as `X-Api-Key`. `@Retry("httpRetry")` + `@CircuitBreaker("usFeed")`;
  HTTP 429 -> `IOException` naming the key.

---

## CSV parse rules (`StationProcessorCA`, commons-csv)

- Parse the raw CSV body with commons-csv (`CSVFormat.DEFAULT`, `setTrim(true)`); skip row 0 (header).
- Column mapping: `[0]` station id, `[1]` timestamp (`OffsetDateTime`), `[2]` water level, `[6]` discharge
  (Double, null if empty).
- **Fault-tolerant:** a short row, blank station/timestamp, or unparseable value/timestamp skips just that row
  (does NOT discard the station's batch). Skipped rows → `water.csv.rows.skipped{country}` metric + log.
- Model: `Reading(String stationId, OffsetDateTime stamp, Double waterLevel, Double discharge)`

---

## US parse rules (`StationProcessorUS`)

- `StationWorker` calls `prepareCycle(mlis, requestedMli)` before the US loop (and before the US startup
  verification); a failed snapshot fails the US pass only. The US pass never pauses between stations.
- Each station is a snapshot lookup; absent -> `FileNotFoundException` -> skipped.
- `buildReadings` keeps instantaneous (`00011`/null), numeric values whose code `UsgsParameterMap` knows,
  named/united exactly as the legacy WaterML was (envdata `sp_water_save_us` converts units by that pair), dated
  by the station's local day: `UsSeriesReading(name, unit, day, value)`.

---

## Failure handling (shared — `StationProcessorBase`)

- On any station processing exception: log warning with country, station, state; continue.
- HTTP 404: log "source feed not published"; do not disable station.
- **Do not call** `dbo.sp_DisableWaterStation`.
- Log message format: `{country} station` (e.g., `"CA station"`, `"US station"`).

---

## HTTP 503 Station Backoff

- `StationProcessorBase` maps upstream HTTP 503 failures to `ProcessingOutcome.FAILED_HTTP_503`.
- `StationWorker` records HTTP 503 outcomes through `StationHttp503BackoffService.recordHttp503(...)` and
  resets backoff through `recordProcessed(...)` after a successful station result.
- `StationHttp503BackoffRepository` calls envdata procedures only (2.0.0):
  - `refreshDue(today)` -> `CALL sp_station_503_refresh_due(?)`
  - `recordHttp503(provider,country,stationMli,state,today)` -> `CALL sp_station_503_record(?, ?, ?, ?, ?)`
    (state cut to 2 characters)
  - `reset(provider,country,stationMli)` -> `CALL sp_station_503_reset(?, ?, ?)`
  - `summaryByState()` -> `CALL sp_station_503_summary_by_state()`
- The state lives in envdata's `station` row (`backoff_state`, `backoff_daily_503_count`,
  `backoff_weekly_503_count`, `backoff_last_503_date`, `backoff_next_date`, `supported`), shared with the C# twin.
  `v_station_water_due` returns only `supported = 1`, so weekly/monthly backoff rows are skipped. Procedures:
  `envfish-db/mysql/envdata/script02_Proc.sql`.
- Backoff rules:
  - `backoffstate`: 0 normal, 1 daily tracking, 2 weekly retry, 3 monthly retry.
  - 3 consecutive daily HTTP 503 final failures -> weekly retry, `backoff_next_date = today + 7 days`,
    `supported = 0`.
  - 4 weekly HTTP 503 final failures -> monthly retry, `backoff_next_date = today + 1 month`,
    `supported = 0`.
  - Repeated 503 recording on the same date is idempotent for counters.
  - Any successful station result resets counters/state and restores `supported = 1`.
  - `refreshDue()` restores due weekly/monthly rows before loading stations.

---

## Persistence (`WaterDataRepository`)

### `saveStationData(String mli, List<Reading> readings)`

- Reject blank `mli`; no-op if readings is null or empty. One transaction (`@Transactional`).
- Deduplicate readings by timestamp within the batch; **keep the last duplicate**; drop null readings/stamps.
- `CALL sp_water_save_ca(?, ?)` per **500 readings**, the readings as one JSON array
  `[{"s":"yyyy-MM-dd HH:mm:ss","e":level,"d":discharge}]` (time in UTC, missing / non-finite value = `null`).
  The procedure upserts by `(station, ts)`, stores `-999` discharge as NULL and refreshes `station_current`.

### `saveUsStationData(String mli, String state, List<UsSeriesReading> seriesList)`

- Reject blank `mli` / `state`; drop points without a name or day or with a non-finite value; no-op when none.
- ONE `CALL sp_water_save_us(?, ?, ?)` per station (state cut to 2 characters), series JSON
  `[{"name":"Streamflow","unit":"ft^3/s","points":[{"d":"yyyy-MM-dd","v":12.5}]}]`, grouped by name and unit.
  envdata merges every series of a day into one reading (so oxygen, pH, turbidity all reach the current state),
  stores pressure in **mm Hg**, pH as the real value, oxygen in mg/L only.

### `recordCycle(job, startedUtc, finishedUtc, status, items, note)`

- `CALL sp_job_run_record(?, ?, ?, ?, ?, ?, ?, @out_job_run_id)`, service `waterservice` (same as the C# twin),
  times as UTC `LocalDateTime`, note cut to 255 characters.

### `cleanOldWaterData()`

- `CALL sp_clean_old_water_data(NULL)`: raw readings 30 days by dropping whole day partitions, aggregates and job
  runs 30 days. Partition DDL commits implicitly, so it never runs inside a transaction.

Every save procedure refuses an unknown station with `SIGNAL SQLSTATE '45000'` (see Resilience4j below).

---

## Resilience4j configuration

- **Aspect order:** `circuit-breaker-aspect-order: 2` > `retry-aspect-order: 1` ⇒ the **breaker is outermost**
  (an open breaker fails fast without burning retries; all retries of one call = one breaker outcome).
- **SQL** (`WaterDataRepository`): retry `sqlRetry` (3×/2s), breaker `sqlBreaker` (window 10, min 5, 50%,
  open 30s). Which exceptions is set in code (`SqlFailures`: customizers that run after `application.yml` and
  clear its `retry-exceptions`): any `DataAccessException` / `SQLException` **except SQLSTATE 45000** (an envdata
  procedure's own refusal, e.g. unknown station): not retried, ignored by the breaker. Same rule as the C# twin.
- **HTTP fetches:** retry `httpRetry` (3×/2s; retry only `ResourceAccessException` + `HttpServerErrorException`;
  **ignore** `FileNotFoundException` so 404-skips aren't retried). Per-feed breakers `caFeed` / `usFeed`
  (window 20, min 10, 50%, open 30s; ignore `FileNotFoundException`) — separate so one feed's outage doesn't
  trip the other.

```yaml
resilience4j:
  retry:
    retry-aspect-order: 1
    instances:
      sqlRetry: { max-attempts: 3, wait-duration: 2s, retry-exceptions: [org.springframework.dao.DataAccessException, java.sql.SQLException] }
      httpRetry:
        max-attempts: 3
        wait-duration: 2s
        retry-exceptions: [org.springframework.web.client.ResourceAccessException, org.springframework.web.client.HttpServerErrorException]
        ignore-exceptions: [java.io.FileNotFoundException]
  circuitbreaker:
    circuit-breaker-aspect-order: 2
    instances:
      sqlBreaker: { sliding-window-size: 10, minimum-number-of-calls: 5, failure-rate-threshold: 50, wait-duration-in-open-state: 30s }
      caFeed: &feed { sliding-window-size: 20, minimum-number-of-calls: 10, failure-rate-threshold: 50, wait-duration-in-open-state: 30s, ignore-exceptions: [java.io.FileNotFoundException] }
      usFeed: *feed
```

---

## Logging (`logback-spring.xml`)

```
Root level:              INFO
com.fishfind.water:      INFO
```

Log the following events:
- CA worker start / US worker start
- Supported station count (per country)
- Each station being processed
- CSV fetch success / USGS fetch success
- Save start and end with reading counts
- Post-processing procedure execution
- Failures and skipped unpublished-source events

### Architectural logging rules

- Format: **structured JSON** with `timestamp`, `service`, `correlationId`, `level`.
- **Never log PII or sensitive water/sensor data in plain text.**
- All logs are **cyclic**: purge entries older than 7 days automatically.
- `correlationId` is set in MDC per cycle (`StationWorker` binds it on each parallel pass thread and around
  post-processing); a `station` MDC key is bound around each station.

---

## Observability & ops

- **Actuator on a private management port**: `management.server.port: 8081` — never publish/expose it
  publicly; only `/health` on 8080 is the external probe surface.
- **Actuator + Micrometer/Prometheus.** Exposed web endpoints ONLY: `health,info,prometheus,metrics`
  (never `env`/`beans`/`configprops` — would leak config/secrets). `health.show-details: never`.
- **Liveness vs readiness** (`management.endpoint.health.probes.enabled: true`):
  - `/actuator/health/liveness` — process alive, NOT DB-dependent (so a DB blip doesn't restart the pod).
  - `/actuator/health/readiness` — includes the `db` indicator ⇒ 503 when the datasource is unreachable.
  - Custom `/health` ({status,version,uptime}) stays lightweight = the Docker HEALTHCHECK target.
    `version` comes from Maven build info (`build-info` goal → `BuildProperties`), fallback "unknown".
- **Overrun visibility:** `water_cycle_overrun_total` + WARN log when a cycle finishes at/after the next
  cron fire (that trigger is silently skipped by the pool-size-1 scheduler); duration logged every cycle.
- **Metrics:** `/actuator/prometheus` serves JVM/HTTP + Resilience4j metrics + custom
  `water_station_processed_total{country,outcome}` (incremented per station in `runOnce`). Use it for a
  sustained-failure-ratio alert.
- **CI:** `.github/workflows/waterservice-ci.yml` runs `mvn test` + `package` on `service/waterservice/**` changes.

---

## Docker

```dockerfile
# Multi-stage: build with Maven, runtime launches:
CMD java $JAVA_OPTS -jar /app/water-station-pusher.jar
```

- Do **not** bake the real `.env` into the image or jar resources.
- `.dockerignore` must exclude `.env`, secrets, and local build artifacts.
- The temurin JRE image has **no wget/curl** — the runtime stage installs `wget` so the HEALTHCHECK
  (`wget -qO- http://localhost:8080/health`) can run; without it the container is permanently unhealthy.
- **SECURITY:** both base images are pinned by digest (`image@sha256:...`) with the human-readable tag in a
  comment; the runtime runs as a non-root user (`USER 10001:10001`) with `/app/logs` pre-created and owned by
  that user (read-only-rootfs friendly — mount a volume/tmpfs at `/app/logs`).

## Dependency scanning

- OWASP Dependency-Check runs via a Maven `security` profile: `mvn -Psecurity verify` (kept out of the default
  lifecycle). Fails on CVSS ≥ 7; set `NVD_API_KEY` for fast NVD updates.

---

## API / service architectural rules

> These apply across all services in the platform.

- All endpoints versioned: `/api/v1/...`
- Standard response envelope: `{ data, error, meta }`
- Idempotency keys on all write operations.
- Every external call: timeout + retry with exponential backoff.
- Circuit breaker on all downstream dependencies.
- Health check: `GET /health` → `{ status, version, uptime }`
- Services communicate via **async messaging** (events/queues) — never direct DB calls across service boundaries.
- No distributed/global transactions; use saga pattern or compensating transactions.
- Each service owns its data store exclusively.

---

## .env.example (project root)

```dotenv
# envdata (MySQL) since 2.0.0
MYSQL_URL=jdbc:mysql://10.118.0.6:3306/envdata?sslMode=REQUIRED
MYSQL_USERNAME=waterservice
MYSQL_PASSWORD=your_password
# SQL Server: kept for a rollback to 1.14.0, not read by 2.x
DB_URL=jdbc:sqlserver://localhost:1433;databaseName=fishfind
DB_USERNAME=your_username
DB_PASSWORD=your_password
USGS_API_KEY=your_usgs_api_key
# Optional: path to a custom .env file
DOTENV_PATH=
```
