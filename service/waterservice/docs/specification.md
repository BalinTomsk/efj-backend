Recreate this project as a Java 21 Spring Boot background service named `water-station-pusher`.

Goal
- Poll supported Canadian and US water stations from MSSQL.
- Download each CA station's hourly hydrometric CSV from Environment Canada.
- Read each US station's latest values from one USGS Water Data API snapshot per cycle.
- Parse readings and upsert them into `dbo.WaterData`.
- After each worker cycle, synchronously run `dbo.sp_clean_old_water_data`.
- When at least one station succeeds in a cycle, also run `dbo.spPushSpeciesFromLakeToStation`.
- Log processing failures and skipped unpublished-source events, but do not disable stations automatically.

Tech stack
- Java 21
- Maven
- Spring Boot 3.3.x
- `spring-boot-starter`
- `spring-boot-starter-web`
- `spring-boot-starter-jdbc`
- `spring-boot-starter-aop`
- `spring-boot-starter-actuator`
- `io.micrometer:micrometer-registry-prometheus` (runtime)
- MSSQL JDBC driver (Boot-managed version overridden via `<mssql-jdbc.version>` to the current 12.8.x line)
- Resilience4j Spring Boot 3 integration for SQL retry/circuit breaker
- `commons-csv` is used for CA CSV parsing (quoted-field-safe, fault-tolerant)
- `dotenv-java` for local credential loading
- SLF4J + Logback
- `logstash-logback-encoder` 7.4 for structured JSON logging

Project structure
- Maven project
- Main class: `com.fishfind.water.WaterStationPusherApplication`
- Packages:
  - `com.fishfind.water.domain`
  - `com.fishfind.water.repo`
  - `com.fishfind.water.service`
  - `com.fishfind.water.web`
- Include `application.yml` and `logback-spring.xml` under `src/main/resources`
- Do not place the real `.env` file in `src/main/resources`
- The real `.env` file belongs in the project root
- Keep a `.env.example` in the project root with placeholder values only

Main application behavior
- `WaterStationPusherApplication.main` only calls `SpringApplication.run`; credential loading is delegated to a Spring `EnvironmentPostProcessor`.
- DB credentials are resolved by Spring from the process environment (`DB_URL`, `DB_USERNAME`, `DB_PASSWORD`) or JVM system properties.
- For local development, `com.fishfind.water.config.DotenvEnvironmentPostProcessor` loads a `.env` file (via `dotenv-java`) and registers its declared entries as the LOWEST-precedence Spring property source (`addLast`).
  - Real OS environment variables and JVM system properties always win over the `.env` file.
  - Only keys declared in the `.env` file are imported (`Dotenv.Filter.DECLARED_IN_ENV_FILE`); the OS environment is not copied.
  - Support optional `DOTENV_PATH` env var to point to a custom `.env` file; otherwise a root-level `.env` is used if present.
  - Encrypted `.env` values require either `FF_MASTER_KEY_FILE` (preferred for Docker secret/file mounts) or
    `FF_MASTER_KEY`; production mounts `/mnt/volume_jnode/waterservice/master.key` to `/run/secrets/master.key`
    and sets `FF_MASTER_KEY_FILE=/run/secrets/master.key`.
  - SECURITY: credentials are NEVER copied into JVM-global system properties (no `System.setProperty`), so they do not leak into `System.getProperties()`, heap dumps, or diagnostic tooling.
- Required keys:
  - `DB_URL`
  - `DB_USERNAME`
  - `DB_PASSWORD`
- Register the post-processor in `src/main/resources/META-INF/spring/org.springframework.boot.env.EnvironmentPostProcessor.imports`.

Datasource config
- Configure Spring datasource from:
  - `${DB_URL}`
  - `${DB_USERNAME}`
  - `${DB_PASSWORD}`
- Driver class: `com.microsoft.sqlserver.jdbc.SQLServerDriver`
- HikariCP tuning (in `application.yml` under `spring.datasource.hikari`):
  - `pool-name: water-hikari`
  - `maximum-pool-size: 4` (two parallel country passes + post-processing, with headroom)
  - `minimum-idle: 1`
  - `connection-timeout: 30000`
  - `max-lifetime: 1740000` (29 min — retire connections before the server/network idle timeout)
  - `keepalive-time: 300000` (5 min)
  - `validation-timeout: 5000`

Worker behavior
- Lifecycle is Spring-managed; no hand-managed `Thread`s.
  - `WorkerConfig` defines two Spring beans (so the container shuts them down gracefully on context close):
    - `cycleScheduler`: a 2-thread `ThreadPoolTaskScheduler` (prefix `water-cycle-`,
      `waitForTasksToCompleteOnShutdown=true`, `awaitTerminationSeconds=60`), one thread per country cron
      task. A cron task is rescheduled only after its run finishes, so a cycle that overruns its hour delays
      that country's next trigger instead of overlapping, and never blocks the other country.
    - `countryPassExecutor`: a 2-thread `ThreadPoolTaskExecutor` (prefix `water-pass-`) used to run the CA and
      US passes in parallel within a console-mode `runCycle`.
- `StationWorker` implements `ApplicationRunner`:
  - If started with `--console`, schedule nothing.
  - Otherwise register TWO independent recurring tasks on `cycleScheduler`, one per country (`CA`, `US`),
    each with a `CronTrigger` from `water.worker.cron` (default `0 0 * * * *` — top of every hour, Spring
    6-field cron), running `runScheduledCycle(country)` -> `runCountryCycle(country)`. Independent tasks so a
    slow CA pass (one HTTP request per station) cannot hold back the US refresh: with one task awaiting both
    passes, a ~28 h CA pass held US data to one refresh per ~28 h.
- `StationWorker.runCountryCycle(country)` (scheduled): run that country's pass on the scheduler thread (a
  pass failure is logged and treated as an empty pass), then post-processing, then log
  `Station cycle completed. country=...`.
- Post-processing (`postProcess(succeeded)`), shared by both cycle kinds and serialised by a lock so the two
  country tasks never run the procedures concurrently: species push only when at least one station
  succeeded in the triggering cycle; stale-data cleanup always. With independent schedules each country
  post-processes after its own pass (twice per hour when both fit); the procedures are idempotent.
- `StationWorker.runCycle(requestedMli)` (console mode):
  - Run the CA and US passes in parallel on `countryPassExecutor`.
  - A failure of one country's pass is isolated (logged) and does not abort the other.
  - Run species post-processing EXACTLY ONCE for the combined result, and ONLY when at least one station
    was processed successfully.
  - Run stale-data cleanup EXACTLY ONCE after the cycle by executing `dbo.sp_clean_old_water_data`.
  - Post-processing failure semantics: a species post-processing failure never prevents cleanup from running;
    if cleanup ALSO fails, the species exception propagates with the cleanup exception attached as suppressed
    (a cleanup failure must not mask the species failure). The cycle-completed summary log is always emitted.
  - Pass startup is shutdown-safe: an executor `RejectedExecutionException` (e.g. during context shutdown) is
    converted into a failed future, so the cycle degrades to an empty pass instead of throwing out of the
    scheduler. `awaitPass` handles both `CompletionException` and `CancellationException`.
  - This replaces the previous design where each of the two worker threads ran post-processing independently,
    causing the same stored procedure to execute twice concurrently every hour.
- `StationWorker.runOnce(country, requestedMli)`:
  - Load supported stations for the country, process matching stations one by one, sleeping
    `pause-between-stations-ms` BETWEEN CA stations only (US stations come from one snapshot and never pause) (never after the final station) (interrupt-aware: stops the pass early if interrupted).
  - Returns the number of stations processed SUCCESSFULLY. Does NOT run post-processing.
- `StationProcessorBase.process(...)` returns `boolean` — `true` on success, `false` when an exception was
  handled (failure or unpublished/skipped source) — so the cycle can decide whether to post-process.
- Configurable properties:
  - `water.worker.cron` default `0 0 * * * *`
  - `water.worker.pause-between-stations-ms` default `1000`
  - `water.worker.connect-timeout-ms` default `15000`
  - `water.worker.read-timeout-ms` default `30000`

Console mode
- Add a console/debug runner activated by `--console` (`ConsoleDebugRunner`, `@Order(0)`).
- Optional arg: `--station=<MLI>`.
- Delegates to `StationWorker.runCycle(station)`, so console mode runs exactly one cycle: both countries in
  parallel followed by a single post-processing run.

WaterStation query rules
- Read from view `vwWaterStation`
- Select columns:
  - `mli`
  - `state`
  - `tz`
- Filter:
  - `country = 'CA'` for the CA worker
  - `country = 'US'` for the US worker
- Represent each row as a simple record like `StationRef(String mli, String state, int tz)`

HTTP transport (shared)
- A single Spring `RestClient` bean (`HttpClientConfig.waterSourceRestClient`) over the JDK `HttpClient`
  (connection pooling / keep-alive), replacing the previous per-request `HttpURLConnection`.
- Connect timeout (`water.worker.connect-timeout-ms`) on the client; read timeout
  (`water.worker.read-timeout-ms`) on the request factory.
- Honest identifying `User-Agent` default header (`water.worker.user-agent`, default
  `water-station-pusher/1.0.0 (+https://fishfind.info)`), NOT a spoofed browser string.
- Resilience is declarative on the fetcher methods (see Resilience4j config): `@Retry(name="httpRetry")` retries
  only transient failures (network errors / 5xx); a per-feed `@CircuitBreaker` (`caFeed` / `usFeed`) protects
  each downstream independently. Note: no `@TimeLimiter` — the call is blocking, so the transport connect/read
  timeouts serve as the time bound (TimeLimiter would require an async/`CompletableFuture` return type).

CSV fetch rules (`CsvFetcherCA`)
- URL pattern:
  - `https://dd.weather.gc.ca/today/hydrometric/csv/{STATE}/hourly/{STATE}_{MLI}_hourly_hydrometric.csv`
- SECURITY: build the URL as a RestClient URI template with `{state}`/`{mli}` variables so values are
  strictly URL-encoded; never interpolate DB values into the URL string (second-order path injection).
- `fetch` returns the raw CSV body as a `String`.
- HTTP 404 -> `FileNotFoundException` so the station is skipped (ignored by retry and breaker). The exception message names the feed, station, and state (self-sufficient without caller context).
- Other non-2xx / network errors propagate (5xx and network errors are retried by `httpRetry`).

US fetch rules (`UsgsWaterDataClient`)
- The legacy WaterServices `nwis/iv` feed is decommissioned on 2027-02-22 (slowed from 2026-11-16). US data
  comes from the USGS Water Data API (OGC API), rate-limited per API key, so the service makes ONE snapshot
  per US pass instead of one request per station.
- `fetchLatest(mli)` pages `{usgs-base-url}/latest-continuous/items?f=json&skipGeometry=true&limit=50000
  &properties=monitoring_location_id,parameter_code,statistic_id,time,value`, following each `rel=next` link
  until a page is empty or has no `next` (hard stop at 20 pages). About 2-3 requests cover all ~25k US sites.
  Returns observations keyed by bare site number (`USGS-` stripped = the `vwWaterStation` MLI). With `mli`
  set (startup verification) it adds `&monitoring_location_id=USGS-{mli}` (URL-encoded).
- `ensureTimeZones(mlis)` looks up `time_zone_abbreviation` + `uses_daylight_savings` from
  `{usgs-base-url}/monitoring-locations/items?id=USGS-a,USGS-b,...` in batches of 200, ONCE per process
  (cached; undescribed sites cached as UTC). `resolveTimeZone` maps EST/CST/MST/PST/AKST/AST to the IANA zone
  when DST is observed, else a fixed offset; HST -10, SST -11, ChST/GST +10, anything else UTC.
- Properties: `water.worker.usgs-base-url` (default `https://api.waterdata.usgs.gov/ogcapi/v1/collections`);
  the key is the `USGS_API_KEY` secret (env / `.env`), sent as the `X-Api-Key` header when set. Keyed limit:
  1,000 requests/hour, shared by the Java and C# services.
- Both methods are `@Retry("httpRetry")` + `@CircuitBreaker("usFeed")`. HTTP 429 -> `IOException` naming
  `USGS_API_KEY` (not retried); a body cut off mid-read -> `ResourceAccessException` (retried).

CSV parse rules (`StationProcessorCA`, commons-csv)
- Parse the raw CSV body with commons-csv (`CSVFormat.DEFAULT` with `setTrim(true)`), handling quoted fields.
- Skip the first row as header.
- Parse:
  - column 0 -> station id
  - column 1 -> timestamp as `OffsetDateTime`
  - column 2 -> water level
  - column 6 -> discharge
- Empty numeric values map to `null`.
- FAULT TOLERANCE: a single malformed row (fewer than 7 columns, blank station id/timestamp, or an
  unparseable value/timestamp) is skipped — it does NOT abort the whole station's batch. Skipped rows are
  counted on the `water.csv.rows.skipped{country}` metric and logged.
- Model each reading as:
  - `Reading(String stationId, OffsetDateTime stamp, Double waterLevel, Double discharge)`

US parse rules (`StationProcessorUS`)
- At the start of each US pass (and before the US startup verification) `StationWorker` calls
  `prepareCycle(mlis, requestedMli)` (snapshot + time zones). An `IOException` there is rethrown as
  `UncheckedIOException` and fails the US pass only.
- Each station is a snapshot lookup; absent -> `FileNotFoundException` -> skipped.
- `buildReadings` emits one `UsSeriesReading` per observation, keeping only instantaneous values
  (`statistic_id` `00011` or null) with a numeric value and a parameter code known to `UsgsParameterMap`, which
  maps the code to the EXACT legacy WaterML name/unit pair (`00060` -> `Streamflow` / `ft^3/s`, `00065` ->
  `Gage height` / `ft`, ...; 128 codes harvested from live legacy responses) so `dbo.sp_push_us_water_data`
  and its unit conversions behave as before.
- The day is the observation time converted to the station's LOCAL date. Payload:
  `<root><a d="yyyy-MM-dd" v="..." /></root>`.

Failure handling
- On any station processing exception:
  - log a warning with country, station, and state
  - continue processing remaining stations
- For CA or US source HTTP 404 responses:
  - log that the source feed is not published
  - do not disable the station
- Do not execute `dbo.sp_DisableWaterStation` in the current project state

HTTP 503 station backoff
- `StationProcessorBase` maps upstream HTTP 503 failures to `ProcessingOutcome.FAILED_HTTP_503`.
- `StationWorker` records those failures through `StationHttp503BackoffService.recordHttp503(...)` and resets
  backoff through `recordProcessed(...)` after a successful station processing result.
- `StationHttp503BackoffRepository` is the Java SQL gateway. It calls stored procedures and does not directly
  update station tables:
  - `refreshDue(today)` -> `EXEC dbo.sp_water_station_503_refresh_due ?`
  - `recordHttp503(provider,country,stationMli,state,today)` -> `EXEC dbo.sp_water_station_503_record ?, ?, ?, ?, ?`
  - `reset(provider,country,stationMli)` -> `EXEC dbo.sp_water_station_503_reset ?, ?, ?`
  - `summaryByState()` -> `EXEC dbo.sp_water_station_503_summary_by_state`
- Database schema lives in `envfish-db/mssql`:
  - `dbo.WaterStation` stores `backoffstate`, `backoff_daily_503_count`, `backoff_weekly_503_count`,
    `backoff_last_503_date`, `backoff_next_date`, and `supported`.
  - `vwWaterStation` returns only `supported = 1`, so weekly/monthly backoff rows are skipped by the worker.
  - Procedure definitions are in `mssql/script02_Proc.sql`; tests are in
    `mssql/UNIT_TESTS/unit_test@WaterStation503Backoff.sql`.
- Backoff rules:
  - `backoffstate`: 0 normal, 1 daily tracking, 2 weekly retry, 3 monthly retry.
  - 3 consecutive daily HTTP 503 final failures -> weekly retry, `backoff_next_date = today + 7 days`,
    `supported = 0`.
  - 4 weekly HTTP 503 final failures -> monthly retry, `backoff_next_date = today + 1 month`,
    `supported = 0`.
  - Repeated 503 recording on the same date is idempotent for counters.
  - Any successful station result resets counters/state and restores `supported = 1`.
  - `refreshDue()` restores due weekly/monthly rows before loading stations.

WaterData persistence rules
- Implement repository method `saveStationData(String mli, List<Reading> readings)`
- Reject blank `mli`
- If readings list is null or empty, do nothing
- Wrap save in one transaction
- Apply Resilience4j retry and circuit breaker around SQL operations
- Deduplicate readings by timestamp within the batch, keeping the last duplicate
- Upsert each reading by executing legacy stored procedure `dbo.sp_UpdateWaterData` as ONE JDBC batch
  (`JdbcTemplate.batchUpdate` with a ParameterizedPreparedStatementSetter), not one round-trip per reading
- Mapping:
  - CSV water level -> `dbo.WaterData.elevation`
  - CSV discharge -> `dbo.WaterData.discharge`
- Store timestamp as SQL `datetime2`
- Also implement `saveUsStationData(String mli, String state, List<UsSeriesReading> seriesList)`
- Use the legacy stored procedure `dbo.sp_push_us_water_data`
- Also implement post-processing repository methods:
  - `cleanOldWaterData()` -> `dbo.sp_clean_old_water_data`
  - `pushSpeciesFromLakeToStation()` -> `dbo.spPushSpeciesFromLakeToStation`

Important note about delete logic
- There was earlier intent to delete old `WaterData` rows older than 15 days for a station.
- In the current project state that delete is not active.
- Recreate the current behavior as-is unless explicitly told to restore the cleanup query.
- The cleanup now happens only through the post-cycle procedure `dbo.sp_clean_old_water_data`.

Resilience4j settings
- Aspect order: `circuit-breaker-aspect-order: 2` and `retry-aspect-order: 1` so the circuit breaker is the
  OUTERMOST aspect. An open breaker short-circuits immediately without burning retry attempts/backoff, and all
  retries of one call are recorded as a single breaker outcome.
- SQL (`WaterDataRepository`):
  - Retry `sqlRetry`: max attempts `3`, wait `2s`, retry `org.springframework.dao.DataAccessException` and
    `java.sql.SQLException`.
  - Circuit breaker `sqlBreaker`: sliding window `10`, min calls `5`, failure threshold `50%`, open wait `30s`.
- HTTP fetches:
  - Retry `httpRetry`: max attempts `3`, wait `2s`; retry-exceptions
    `org.springframework.web.client.ResourceAccessException` and `HttpServerErrorException` (5xx); ignore
    `java.io.FileNotFoundException` (404 skip is not transient).
  - Per-feed circuit breakers `caFeed` and `usFeed`: sliding window `20`, min calls `10`, failure threshold
    `50%`, open wait `30s`; ignore `java.io.FileNotFoundException`. Separate instances so one feed's outage
    does not open the breaker for the other.

Logging
- Root logging level `INFO`
- App logging level `INFO` for `com.fishfind.water`
- Format: structured JSON via logstash-logback-encoder with fields: `timestamp`, `level`, `service` (constant "water-station-pusher"), `correlationId` (from MDC), plus standard logback fields
- Output to console AND a rolling daily file under `logs/` with 7-day maxHistory (auto-purge entries older than 7 days)
- Log at INFO level:
  - CA worker start
  - US worker start
  - supported station count
  - post-processing procedure execution
- Log at DEBUG level:
  - each processed station
  - CSV fetch start and success
  - USGS fetch start and success
  - save start/end with reading counts
  - successful HTTP 503 station backoff resets
- Log failures at WARN and skipped unpublished-source events at DEBUG (via StationProcessorBase)
- `correlationId` MDC is populated per cycle: `StationWorker` generates a short id per `runCycle` and binds it
  to MDC on each parallel pass thread (and around post-processing), so all of a cycle's log lines share it.
  A `station` MDC key is bound around each station's processing.

Health endpoint
- `GET /health` returns HTTP 200 with JSON body: `{ "status": "UP", "version": <pom version>, "uptime": <seconds> }`
- The version comes from Maven build info (`spring-boot-maven-plugin` `build-info` goal ->
  `BuildProperties`), never a hardcoded constant; falls back to "unknown" when build info is absent
  (e.g. IDE runs).
- Implemented in `com.fishfind.water.web.HealthController`. Intentionally lightweight (liveness style) so the
  Docker HEALTHCHECK does NOT flap/restart the container during a transient DB outage.
- Server listens on port 8080 (`server.port=8080` in application.yml)

Observability and operations
- Spring Boot Actuator + Micrometer Prometheus registry.
  - Dependencies: `spring-boot-starter-actuator`, `io.micrometer:micrometer-registry-prometheus` (runtime).
  - SECURITY: actuator is served on a separate management port 8081 (`management.server.port: 8081`) that must
    NOT be published/exposed publicly — only `/health` on 8080 is the external probe surface. Scrape
    Prometheus over the private network / localhost only.
  - Exposed web endpoints ONLY: `health`, `info`, `prometheus`, `metrics`. Never expose `env`/`configprops`/
    `beans` (would leak configuration/secrets).
  - `management.endpoint.health.show-details: never` (aggregate status only).
- Liveness vs readiness split (`management.endpoint.health.probes.enabled: true`):
  - `/actuator/health/liveness` — process alive; does NOT depend on the database.
  - `/actuator/health/readiness` — includes the `db` indicator, so it reports DOWN (HTTP 503) when the
    datasource is unreachable. This is the real datasource probe; use it for orchestration readiness gating.
- Metrics:
  - `/actuator/prometheus` exposes JVM/HTTP metrics, Resilience4j metrics (auto-registered from the
    resilience4j-spring-boot3 + Micrometer integration), and the custom counter
    `water_station_processed_total{country,outcome}` (outcome = `success` | `failure`), incremented per station
    in `StationWorker.runOnce`.
  - `water_cycle_overrun_total`: incremented (with a WARN log) when a scheduled cycle finishes at or after
    the next cron fire time — the scheduler silently skips that country's trigger, so this is the only
    signal that cycles are being dropped. Cycle duration is logged after every scheduled cycle. Both lines
    carry `country`.
  - Recommended alert (in the monitoring stack, not this repo): sustained high failure ratio, e.g.
    `sum(rate(water_station_processed_total{outcome="failure"}[1h])) / sum(rate(water_station_processed_total[1h])) > 0.5`.
- CI: `.github/workflows/waterservice-ci.yml` runs `mvn -B test` then `mvn -B -DskipTests package` on any change
  under `service/waterservice/**`, gating changes on a green test run before packaging.

Docker expectations
- Multi-stage Dockerfile is acceptable
- Build jar with Maven
- SECURITY: both base images are pinned by digest (`image@sha256:...`), not floating tags, for reproducible,
  tamper-resistant builds. The human-readable tag is kept in a comment above each `FROM`.
- SECURITY: the runtime container runs as an unprivileged user (uid/gid 10001, `USER 10001:10001`), not root.
  `/app/logs` is pre-created and owned by that user so the container can run with a read-only root filesystem
  (mount a volume/tmpfs at `/app/logs` for the logback FILE appender).
- Runtime container:
  - Mount production env and secret files read-only: `/mnt/volume_jnode/waterservice/waterservice.env` to
    `/run/secrets/waterservice.env` with `DOTENV_PATH=/run/secrets/waterservice.env`, and
    `/mnt/volume_jnode/waterservice/master.key` to `/run/secrets/master.key` with
    `FF_MASTER_KEY_FILE=/run/secrets/master.key`.
  - Mount persistent logs at `/app/logs`, owned by uid/gid 10001.
  - The temurin JRE image ships WITHOUT wget/curl; the Dockerfile installs `wget` (apt, no-install-recommends)
    so the HEALTHCHECK can actually execute — without it the check exits 127 and the container is permanently
    reported unhealthy.
  - EXPOSE 8080
  - HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD wget -qO- http://localhost:8080/health || exit 1
  - Launches: `java $JAVA_OPTS -jar /app/water-station-pusher.jar`
- Do not bake the real `.env` into the jar or image resources

Dependency / supply-chain scanning
- A Maven `security` profile runs OWASP Dependency-Check: `mvn -Psecurity verify`.
- Kept out of the default lifecycle so normal builds stay fast.
- Fails the build on CVSS >= 7; emits HTML and SARIF reports.
- Set env `NVD_API_KEY` for fast, rate-limit-free NVD database updates.

Files to include
- `pom.xml`
- `src/main/java/com/fishfind/water/WaterStationPusherApplication.java`
- `src/main/java/com/fishfind/water/domain/Reading.java`
- `src/main/java/com/fishfind/water/domain/StationRef.java`
- `src/main/java/com/fishfind/water/domain/UsSeriesReading.java`
- `src/main/java/com/fishfind/water/repo/WaterDataRepository.java`
- `src/main/java/com/fishfind/water/repo/WaterStationRepository.java`
- `src/main/java/com/fishfind/water/service/CsvFetcherCA.java`
- `src/main/java/com/fishfind/water/service/UsgsWaterDataClient.java`
- `src/main/java/com/fishfind/water/service/UsgsParameterMap.java`
- `src/main/java/com/fishfind/water/domain/UsgsObservation.java`
- `src/main/java/com/fishfind/water/service/StationProcessorCA.java`
- `src/main/java/com/fishfind/water/service/StationProcessorUS.java`
- `src/main/java/com/fishfind/water/service/StationWorker.java`
- `src/main/java/com/fishfind/water/service/ConsoleDebugRunner.java`
- `src/main/java/com/fishfind/water/service/StationPostProcessingService.java`
- `src/main/java/com/fishfind/water/web/HealthController.java`
- `src/main/java/com/fishfind/water/config/DotenvEnvironmentPostProcessor.java`
- `src/main/java/com/fishfind/water/config/WorkerConfig.java`
- `src/main/java/com/fishfind/water/config/HttpClientConfig.java`
- `src/main/resources/META-INF/spring/org.springframework.boot.env.EnvironmentPostProcessor.imports`
- `src/main/resources/application.yml`
- `src/main/resources/logback-spring.xml`
- `.env.example`
- `.dockerignore`
- `Dockerfile`

Do not include
- Real secrets
- A committed production `.env`
- The real `.env` under `src/main/resources`

If rebuilding from this specification, reproduce current behavior faithfully rather than improving architecture unless asked.

Current implementation notes
- `WaterDataRepository.cleanOldWaterData()` and `pushSpeciesFromLakeToStation()` must tolerate procedures that emit incidental result sets or update counts.
- `saveStationData` deduplicates readings by timestamp within a batch and keeps the last duplicate.
- `saveUsStationData` ignores empty variable payloads instead of failing the full station save.
- Cycle threads use the prefixes `water-cycle-` (scheduler) and `water-pass-` (parallel country passes).
- `StationProcessorBase` centralizes the shared CA/US exception handling and formats messages as `{country} station`, and its `process(...)` returns a success boolean.
