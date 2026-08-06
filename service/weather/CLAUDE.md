# CLAUDE.md
# weather-station-pusher — Claude Context

## Project
- Provide actual weather data and forecast for Fish Find Portal


## Tech Stack
- Java

## Keeping docs in sync — IMPORTANT

`docs/specification.txt` is the **single source of truth** used to recreate this service from scratch.
It must always reflect the current state of the code.

`CHANGLOG.md` is the **single source of truth for changelog entries**. Put release notes,
version history, and notable change records there instead of keeping changelog data in
`CLAUDE.md` or `docs/specification.txt`.

**Rules:**

- Whenever **any source file** (`*.java`, `pom.xml`, `application.yml`, `logback-spring.xml`,
  `Dockerfile`, etc.) is created, modified, or deleted — update `docs/specification.txt` to match.
- Whenever a change is release-worthy or operationally notable — update `CHANGLOG.md`.
- Whenever **this `claude.md`** is updated — apply the same change to `docs/specification.txt`
  if it affects behaviour, structure, or configuration.
- `docs/specification.txt` must be sufficient on its own for a developer (or Claude) to
  **fully recreate the service from scratch** with no other context. Keep it complete and accurate.
- Do not leave `docs/specification.txt` describing behaviour that no longer exists, or omitting
  behaviour that was added.
- Treat every code change as a two-step commit: ① change the code, ② update `docs/specification.txt`.

---

##IMPORTANT
Explicitly follows database schema at:
- @srv/../../envfish-db

- **DO NOT COMMIT without explicit user permission.**
- **DO NOT PUSH without explicit user permission.**
- **DO NOT CREATE, MERGE, OR CLOSE PULL REQUESTS without explicit user permission.**
- When code changes are requested, make the file edits and stop with a status summary unless the
  user explicitly asks for Git actions.

- Local project skills live under `.claude/skills` inside this service. When the user asks to run a
  skill by name, check `.claude/skills/<skill-name>/SKILL.md` before searching repo-level `Skills`
  directories or global skill registries.

- **Before making ANY database change** (schema, stored proc, function, view, seed data, or any
bug fix that touches the DB), **read `c:\envoinx\fishfind\envfish-db\CLAUDE.md `
first** — it is the authoritative DB workflow (never edit the generated `ffi2.sql`; edit the
`scriptNN_*.sql` sources; test-first: a FAILING unit test to confirm the bug, then a PASSING one
to verify the fix; run `mssql\UNIT_TESTS\autorun.bat`). That file lives in the separate
`efj-backend` repo and does NOT auto-load in this project, so it must be opened explicitly.


---

## Project identity

| Key | Value |
|-----|-------|
| Service name | `debian-weather` |
| Language | Java 21 |
| Build | Maven |
| Framework | Spring Boot 3.5.16 |
| Main class | `com.fishfind.weather.WeatherStationPusherApplication` |

---

## Goal

- Poll up to 900 US weather stations and up to 1400 CA weather stations from MSSQL (`dbo.vwWeatherForecastToDay`).
- Fetch raw JSON latest-observation data from Weather.gov for US stations.
- Fetch raw JSON forecast data from Open-Meteo for CA stations.
- Store the raw JSON as-is into `dbo.ows_meteo` with source type `2`. **Do not parse JSON in Java.**
- After each full pass, run post-processing stored procedures in order:
  1. `dbo.spPushSpeciesFromLakeToStation`
  2. `dbo.spTotalUpdateProbability`
  3. `dbo.sp_clean_old_weather_data`
- Log failures and skipped unpublished-source events; **do not disable stations automatically**.
- Sleep until next midnight between cycles.

---

## Commands

```bash
# Build (skip tests)
mvn -DskipTests package

# Run tests
mvn test

# Run a single test class
mvn test -Dtest=MyTestClass

# Docker build
docker build -t weather-station-pusher:1.0.0 .
```

**Run modes:**
```bash
# Normal daemon (loops indefinitely, sleeps until next midnight between cycles)
java -jar target/weather-station-pusher-1.0.0.jar

# One-shot pass through all stations, then exit
java -jar target/weather-station-pusher-1.0.0.jar --console

# One-shot for a single station (by MLI identifier)
java -jar target/weather-station-pusher-1.0.0.jar --console --station=<MLI>
```

---

## Package layout

```
com.fishfind.weather
├── domain
│   └── StationRef.java           # record: mli, latitude, longitude, state
├── repo
│   ├── WeatherDataRepository.java
│   └── WeatherStationRepository.java
└── service
    ├── ConsoleDebugRunner.java
    ├── CycleReportEntry.java           # record: one worker's completed-cycle summary
    ├── CycleReportRecorder.java        # in-memory rolling buffer (last 7 days per worker) for the weekly email
    ├── IncidentEntry.java              # record: one detected crash/unclean-restart incident
    ├── OpenMeteoFetcher.java          # resilience4j + 429 Retry-After
    ├── ProcessingOutcome.java         # enum PROCESSED / SKIPPED / FAILED
    ├── RateLimitedException.java      # IOException on exhausted 429 retries
    ├── ServiceLifecycleTracker.java    # crash detection via marker file + log-tail description
    ├── StationPostProcessingService.java
    ├── StationProcessorBase.java      # template method; returns ProcessingOutcome
    ├── StationProcessorOpen.java
    ├── StationWorker.java             # entry point + graceful shutdown + post-proc gate
    └── WeeklyReportMailService.java    # @Scheduled weekly email: cycles + crash incidents
```

---

## Required files

```
pom.xml
src/main/java/com/fishfind/weather/WeatherStationPusherApplication.java
src/main/java/com/fishfind/weather/domain/StationRef.java
src/main/java/com/fishfind/weather/repo/WeatherDataRepository.java
src/main/java/com/fishfind/weather/repo/WeatherStationRepository.java
src/main/java/com/fishfind/weather/service/ConsoleDebugRunner.java
src/main/java/com/fishfind/weather/service/CycleReportEntry.java
src/main/java/com/fishfind/weather/service/CycleReportRecorder.java
src/main/java/com/fishfind/weather/service/IncidentEntry.java
src/main/java/com/fishfind/weather/service/OpenMeteoFetcher.java
src/main/java/com/fishfind/weather/service/ProcessingOutcome.java
src/main/java/com/fishfind/weather/service/RateLimitedException.java
src/main/java/com/fishfind/weather/service/ServiceLifecycleTracker.java
src/main/java/com/fishfind/weather/service/StationPostProcessingService.java
src/main/java/com/fishfind/weather/service/StationProcessorBase.java
src/main/java/com/fishfind/weather/service/StationProcessorOpen.java
src/main/java/com/fishfind/weather/service/StationWorker.java
src/main/java/com/fishfind/weather/service/WeeklyReportMailService.java
src/main/resources/application.yml
src/main/resources/logback-spring.xml
.env.example          (project root, placeholder values only; trustServerCertificate=false)
.owasp-suppressions.xml
Dockerfile
.dockerignore
```

**Never include:** real `.env`, secrets, or `.env` under `src/main/resources`.

---

## Dependencies (pom.xml)

- Maven coordinates: `com.fishfind:weather-station-pusher:1.0.0`
- `spring-boot-starter`
- `spring-boot-starter-web`
- `spring-boot-starter-actuator`
- `spring-boot-starter-jdbc`
- `spring-boot-starter-aop`
- `spring-boot-starter-mail` — SMTP client for the weekly report email (optional; app runs fine with it unconfigured)
- `mssql-jdbc` (`com.microsoft.sqlserver.jdbc.SQLServerDriver`)
- `io.github.resilience4j:resilience4j-spring-boot3`
- `io.github.cdimascio:dotenv-java`
- SLF4J + Logback (via Spring Boot default)
- `spring-boot-starter-test` (test scope)

Build plugins:
- `org.cyclonedx:cyclonedx-maven-plugin:2.9.2` — generates SBOM at `target/bom.json` during `package`
- `org.owasp:dependency-check-maven:12.2.2` — CVE scan; run with `mvn dependency-check:check`; fails on CVSS ≥ 7; suppressions in `.owasp-suppressions.xml`

---

## Startup / credential loading

1. **Before Spring initialises**, read `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` from process environment or JVM system properties.
2. If any are missing, attempt to load from a dotenv file:
   - if `DOTENV_PATH` is set and non-blank, load that path
   - otherwise, if a `.env` file exists in the working directory, load it
   - ignore missing or malformed dotenv files
3. Collect dotenv values into a `Map<String, Object>` and register them via `SpringApplication.setDefaultProperties()`.
   **Never** call `System.setProperty()` for secrets — Spring default properties are the lowest-priority source, so real env/JVM properties still win, and secrets are not exposed in heap dumps or via `System.getProperty()`.
4. Same dotenv fallback also covers `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `REPORT_EMAIL_TO`, `REPORT_EMAIL_FROM` — all optional. Their absence is not a startup failure; see **Weekly report email** below.

---

## Configuration (`application.yml`)

```yaml
spring:
  datasource:
    url: ${DB_URL}
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}
    driver-class-name: com.microsoft.sqlserver.jdbc.SQLServerDriver
  lifecycle:
    timeout-per-shutdown-phase: 30s
  mail:                       # all blank by default: SMTP is optional, app starts fine without it
    host: ${SMTP_HOST:}
    port: ${SMTP_PORT:587}
    username: ${SMTP_USERNAME:}
    password: ${SMTP_PASSWORD:}
    properties: { mail: { smtp: { auth: true, starttls: { enable: true } } } }

server:
  port: 8081        # single listener: serves only the actuator endpoints (no controllers exist)
  shutdown: graceful

resilience4j:
  retry:
    instances:
      sqlRetry: { max-attempts: 3, wait-duration: 2s, retry-exceptions: [DataAccessException, SQLException] }
      openMeteo:                 # HTTP fetch: exponential backoff
        max-attempts: 4
        wait-duration: 1s
        enable-exponential-backoff: true
        exponential-backoff-multiplier: 2
        enable-randomized-wait: true
        retry-exceptions: [java.io.IOException]
        ignore-exceptions:       # not retried: 404, already-waited 429, open breaker
          - java.io.FileNotFoundException
          - com.fishfind.weather.service.RateLimitedException
          - io.github.resilience4j.circuitbreaker.CallNotPermittedException
  circuitbreaker:
    instances:
      sqlBreaker: { sliding-window-size: 10, minimum-number-of-calls: 5, failure-rate-threshold: 50, wait-duration-in-open-state: 30s }
      openMeteo:
        sliding-window-size: 20
        minimum-number-of-calls: 10
        failure-rate-threshold: 50
        wait-duration-in-open-state: 60s
        record-exceptions: [java.io.IOException]
        ignore-exceptions: [java.io.FileNotFoundException]
  ratelimiter:
    instances:
      openMeteo: { limit-for-period: 5, limit-refresh-period: 1s, timeout-duration: 10s }

weather:
  worker:
    connect-timeout-ms: 15000
    read-timeout-ms: 30000
    open-meteo-base-url: https://api.open-meteo.com/v1/forecast
    rate-limit: { max-retries: 2, default-wait-ms: 5000, max-wait-ms: 60000 }   # 429 Retry-After
    max-response-bytes: 5242880                                                 # payload size cap (5 MB)
    post-processing: { max-failure-rate: 0.5 }                                  # cycle gate
  report:
    to: ${REPORT_EMAIL_TO:}          # recipient; blank = weekly email silently disabled
    from: ${REPORT_EMAIL_FROM:}      # optional; falls back to spring.mail.username
    cron: "0 0 8 * * FRI"            # every Friday 08:00, server-local time
  lifecycle:
    state-dir: ${WEATHER_STATE_DIR:/app/logs/.lifecycle}   # crash tracking; persists only if /app/logs is mounted
    log-file: logs/weather.log      # must match logback-spring.xml's <file> path

management:
  endpoints:
    web:
      exposure:
        include: health
  endpoint:
    health:
      probes:
        enabled: true
      show-details: never

logging:
  level:
    root: INFO
    com.fishfind.weather: INFO
```

---

## Worker behaviour

### Thread

- Launched by `StationWorker` (`ApplicationRunner`).
- Thread names: `weather-data-worker-open-us` and `weather-data-worker-open-ca`.
- **Non-daemon** threads.
- If app starts with `--console`: **do not launch background threads**.

### Graceful shutdown

- `volatile running` flag + each loop's interrupt check stop workers cleanly.
- `@PreDestroy shutdown()`: set `running=false`, interrupt each thread, `join` each up to 25 s.
- A stop requested **mid-cycle** breaks the loop and **skips** post-processing.

### Per-cycle loop

1. Load stations for the worker country (`US` or `CA`) from `dbo.vwWeatherForecastToDay` (max 1400 per country).
2. Compute target delay: `max(8_hours_ms / stationCount, 2000)`. If count ≤ 1, use `2000 ms`.
3. For each station (unless stopping): `process()` → tally `PROCESSED/SKIPPED/FAILED` → sleep `(targetDelay - actualProcessingTime)` (skip if negative).
4. **Post-processing gate** (`maybeRunPostProcessing`): with `attempted = processed + failed`, if `attempted > 0 && failed/attempted > weather.worker.post-processing.max-failure-rate` → log **ERROR** and **skip** post-processing (don't recompute probabilities from partial data); otherwise run the procedures. Skipped (no-feed) stations never block post-processing.
5. On cycle completion, record a `CycleReportEntry` (date, worker, country, processed, failed, last processed/failed station) into `CycleReportRecorder` — the same data as the "Worker cycle completed" log line, feeding the weekly report email (see below). Only the background loop records; `--console` runs do not.
6. Sleep until next local midnight (skip if already past boundary).

---

## Console / debug mode (`--console`)

- Activated by `--console` command-line arg (`@Order(0)`, exits process when done).
- Optional: `--station=<MLI>` to filter to one station.
- Runs exactly one processing pass; no background thread started.
- `StationWorker.runOnce` returns a `RunResult(processedStations, failedStations)`. Exit code: `1` when **every** attempted station failed (`processedStations == 0 && failedStations > 0`), so a cron/script wrapper can detect a fully broken pass; otherwise `0` — a partial success (some processed, some failed) still did useful work.

---

## Weekly report email (`WeeklyReportMailService` / `CycleReportRecorder`)

- **Trigger:** `@Scheduled(cron = "${weather.report.cron:0 0 8 * * FRI}")` — every Friday at 08:00 server-local time by default; requires `@EnableScheduling` on `WeatherStationPusherApplication`.
- **Data source:** `CycleReportRecorder` is an in-memory rolling buffer of the last **7 days per worker** (`14` total expected entries) of `CycleReportEntry` records (date, worker, country, `successfulStations`, `failedStations`, last processed/failed station), appended once per completed background-loop cycle in `StationWorker.loop()` — the exact same values as the "Worker cycle completed" log line.
  - **Not persisted.** A JVM restart (e.g. a mid-week deploy) clears the buffer, so a report generated right after a restart only covers cycles completed since then, not the full week. There is no DB table backing this.
  - `--console` runs do **not** feed the recorder — only the production midnight loop does.
- **Skip conditions (no error, just a log line and no email):**
  - `weather.report.to` blank/unset → SMTP not configured for reporting.
  - `CycleReportRecorder` empty → nothing completed yet since the last restart/report.
- **Send failure:** caught (`MailException`) and logged as an **error**; never propagates out of the `@Scheduled` method.
- **From address:** `weather.report.from` if set, else falls back to `spring.mail.username`, else omitted (mail server default).
- **Body:** plain text (`SimpleMailMessage`), one line per recorded worker cycle: `YYYY-MM-DD: worker=<provider> country=<country> processed=N failed=N lastProcessedStation=<mli|none> lastFailedStation=<mli|none>`.
- **SMTP itself is fully optional at the app level:** `spring.mail.host/port/username/password` all default to blank (`${SMTP_HOST:}` etc.), so the weather worker starts and runs normally with no SMTP configured — only the weekly email is skipped.
- **Skip logic accounts for crash-loops:** the email is skipped only when there is genuinely nothing to report (`entries` AND `incidents` both empty). Incidents alone are enough to trigger a send — a service that crash-loops before ever completing a cycle must not go unreported just because `CycleReportRecorder` is empty.

---

## Crash / unclean-restart tracking (`ServiceLifecycleTracker`)

- **Detection mechanism:** a two-line marker file (`RUNNING|<startedAt>` / `CLEAN|<shutdownAt>`) is written on every startup (`@PostConstruct init()`) and rewritten to `CLEAN` on graceful shutdown (`@PreDestroy onShutdown()`, fired when Spring gets SIGTERM and has time to run its shutdown phase). If the **next** startup finds the marker still says `RUNNING`, the previous process never got that chance — it crashed (OOM-killed, uncaught JVM error, `kill -9`, host reboot, or a forceful container removal that skips SIGTERM).
- **Incident description:** the last `ERROR`/`WARN` line found by tailing the previous run's log file (`weather.lifecycle.log-file`, JSON-per-line via the existing Logstash encoder, parsed with the Jackson `ObjectMapper` already on the classpath via `spring-boot-starter-web`). Falls back to `"no errors or warnings recorded before the restart"` if the tail has none, or `"no log data available"` if the log file itself is missing/unreadable.
- **Downtime start:** the timestamp of the last parseable line in that log tail (closer to the true crash moment than "when the crashed process started"); falls back to the marker's own `startedAt`, then to `LocalDateTime.now()`.
- **CRITICAL — depends on the deploy flow sending a graceful stop, not SIGKILL.** `docker rm -f` (the old deploy step) sends SIGKILL immediately, skipping `@PreDestroy` — every deploy would then be misreported as a crash. `docs/do-update.md` and the `update-weather` skill's Step 8 now do `docker stop -t 30` (SIGTERM, wait) **then** `docker rm`, so a normal deploy is correctly not counted.
- **Persistence:** state is a plain file under `weather.lifecycle.state-dir` (default `/app/logs/.lifecycle`, a subdirectory of the logs volume) — not a database table. Nothing here fails startup: an unwritable/missing state dir is logged and skipped, exactly like the SMTP-unconfigured case.
- **Retention:** `recentIncidents()` returns and keeps only incidents detected within the last 7 days, trimming the backing file on read.

---

## Station query (`WeatherStationRepository`)

```sql
SELECT TOP 1400 mli, lat, lon, state
FROM dbo.vwWeatherForecastToDay
WHERE country = ?
```

`StationWorker` starts one pass loop for `US` and one for `CA`; the repository binds the
country parameter for each loop.

Model: `StationRef(String mli, double latitude, double longitude, String state)`

---

## HTTP fetch (`OpenMeteoFetcher`)

- Transport: `HttpURLConnection`, method `GET`.
- Base URL: `weather.worker.open-meteo-base-url` (default `https://api.open-meteo.com/v1/forecast`) — overridable for tests.
- Connect timeout: `weather.worker.connect-timeout-ms` (default 15 000 ms).
- Read timeout: `weather.worker.read-timeout-ms` (default 30 000 ms).
- `User-Agent`: Chrome-like `Mozilla/5.0 (...) AppleWebKit/537.NN (...) Chrome/124.0 Safari/537.NN`. The two `537.NN` WebKit/Safari build numbers are randomised in `[11, 97]`, seeded by the calendar day so they're stable per day and change daily (`OpenMeteoFetcher.currentUserAgent`).
- Resilience: `fetch` is annotated `@Retry` + `@CircuitBreaker` + `@RateLimiter` (instance `openMeteo`). AOP-active only on the Spring bean at runtime (inert in direct unit tests).
- HTTP 200 → read response body as UTF-8 **verbatim** (no post-processing of the body), but reject before persisting: body over `weather.worker.max-response-bytes` or whose first non-whitespace char is not `{` → `IOException` (retried). A cheap shape guard, **not** JSON parsing — keeps HTML error pages out of `ows_meteo`.
- HTTP 404 → throw `FileNotFoundException` (not retried; → `SKIPPED` upstream).
- HTTP 429 → honour `Retry-After` **inline** (delta-seconds or HTTP-date, clamped to `[0, max-wait-ms]`), retry up to `rate-limit.max-retries`; if still 429 → `RateLimitedException` (recorded by the breaker). Interrupt during the wait → re-set flag and throw `RateLimitedException` (excluded from retry, so shutdown isn't delayed by backoff attempts).
- Other non-200 / timeout → throw `IOException` (retried with exponential backoff).

**URL shape:**
```
https://api.open-meteo.com/v1/forecast
  ?latitude={lat}&longitude={lon}
  &hourly=temperature_2m,relative_humidity_2m,precipitation_probability,
          pressure_msl,wind_speed_10m,wind_direction_10m,weather_code,rain
  &daily=temperature_2m_max,temperature_2m_min
  &timezone=auto
```

---

## Persistence (`WeatherDataRepository`)

### Save raw JSON

```java
void saveStationData(String mli, String jsonData)
```

- Reject blank `mli` → throw `IllegalArgumentException`.
- Blank / null `jsonData` → no-op.
- Runs in a transaction; protected by Resilience4j `@Retry(sqlRetry)` + `@CircuitBreaker(sqlBreaker)`.
- `UPDATE` matching 0 rows → log **WARNING** with `mli` and payload size (payload is dropped; must not vanish silently).
- The raw `UPDATE` (rather than a view/procedure) is an intentional, grandfathered exception to the house DB-access rule — it mirrors the legacy `WeatherDataWorkerOpen` .NET service exactly. If a save procedure for this table is ever introduced, switch to it instead of adding a new raw-table statement elsewhere.

```sql
UPDATE dbo.ows_meteo
SET type = 2, ows = ?, stamp = GETDATE()
WHERE mli = ?
```

### Post-processing procedures

```java
pushSpeciesFromLakeToStation()  // → EXEC dbo.spPushSpeciesFromLakeToStation
totalUpdateProbability()        // → EXEC dbo.spTotalUpdateProbability
cleanOldWeatherData()           // → EXEC dbo.sp_clean_old_weather_data
```

- Each runs in a transaction; each is protected by Resilience4j retry + circuit breaker.
- Procedures may emit incidental result sets or update counts — drain with `PreparedStatementCallback` + `getMoreResults`.

---

## Processing pipeline (`StationProcessorBase` / `StationProcessorOpen`)

`StationProcessorBase` enforces consistent exception handling (template method):
- `process(StationRef)` is `final`; calls `processStation()` inside try/catch.
- `FileNotFoundException` → log info skip: `Skipping US station with no published Open-Meteo source. station={mli} state={state}`
- Any other exception → log warning: `US station processing failed. station={mli} state={state}`; continue.

`StationProcessorOpen` implements:
1. Fetch JSON from Open-Meteo using station lat/lon.
2. Log save start with payload byte count at `DEBUG`.
3. Update `dbo.ows_meteo` via `WeatherDataRepository`.
4. Log station processed at `DEBUG`.

`StationPostProcessingService` calls procedures in this exact order (matches legacy base):
1. `dbo.spPushSpeciesFromLakeToStation`
2. `dbo.spTotalUpdateProbability`
3. `dbo.sp_clean_old_weather_data`

---

## Timing model

| Scenario | Behaviour |
|---|---|
| 1400 stations, 8h budget | delay ≈ `28 800 000 / 1400 = 20 571 ms` per station |
| Actual delay | `targetDelay − actualProcessingTime`; never negative |
| Between cycles | sleep until next local midnight; skip sleep if already past boundary |

---

## Error handling

| Scenario | Behaviour |
|---|---|
| Missing `DB_URL` / `DB_USERNAME` / `DB_PASSWORD` | Spring datasource fails at startup |
| Blank `mli` during save | throw `IllegalArgumentException` |
| Blank / null JSON payload | skip save |
| HTTP 404 from Open-Meteo | `FileNotFoundException`; log skip; outcome `SKIPPED` |
| HTTP 429 from Open-Meteo | honour `Retry-After` inline; if exhausted → `RateLimitedException` → `FAILED` |
| Interrupted during `Retry-After` wait | `RateLimitedException` (no further retry); interrupt flag re-set |
| 200 body oversized or not a JSON object | `IOException`; retried (backoff); if exhausted → `FAILED` |
| `UPDATE` matches 0 `ows_meteo` rows | log **WARNING** (payload dropped); still counts as `PROCESSED` |
| HTTP non-200 other than 404 / timeout | `IOException`; retried (backoff); if exhausted → `FAILED` |
| Open Open-Meteo circuit | `CallNotPermittedException` fast-fail → `FAILED` |
| Per-station processing exception | log warning with station and state; outcome `FAILED`; continue |
| SQL write failure | Resilience4j retry/circuit breaker; then runtime exception propagates → `FAILED` |
| High cycle failure rate (> `max-failure-rate`) | log **ERROR**; **skip** post-processing for the cycle |
| Post-processing emits result sets | drain with `getMoreResults`; continue normally |
| Stop requested mid-cycle (`@PreDestroy`) | break loop; skip post-processing; thread joins (≤ 25 s) |
| Worker thread interrupted | re-set interrupt flag; stop worker thread |
| Unexpected worker loop exception | log error; continue loop |

**Never:** disable stations automatically; stop the worker for a single station failure; parse JSON in Java.

---

## Logging

Root level: `INFO` / `com.fishfind.weather`: `INFO`

### Format

Structured JSON via `logstash-logback-encoder`. Every log line is a JSON object with at minimum: `timestamp`, `level`, `service` (`debian-weather`), `logger_name`, `thread_name`, `message`. MDC field `correlationId` appears automatically when set.

### Appenders (`logback-spring.xml`)

- **CONSOLE** — `LogstashEncoder`, writes to stdout.
- **FILE** — `LogstashEncoder`, active file `logs/weather.log`, rolls daily to `logs/weather-%d{yyyy-MM-dd}.log.gz`, `maxHistory=7`, `totalSizeCap=500MB`.

### Required log events

- Background worker thread start
- Supported station count
- Calculated time-budget delay
- Fetch success per station (`DEBUG`)
- Save start with payload byte count (`DEBUG`)
- Station processed (`DEBUG`)
- Startup verification started/succeeded/failed (`INFO` for started and succeeded, `ERROR` for failed)
- Post-processing procedure execution
- Skip due to unpublished source (info)
- Station processing failure (warning)
- Cycle completion with next run time

---

## Docker

Build stage: `maven:3.9.9-eclipse-temurin-21` — runs `mvn -B -DskipTests package`.  
Runtime stage: `eclipse-temurin:21-jre` — copies jar to `/app/weather-station-pusher.jar`.

Security:
- Non-root user: `appgroup` (gid 1001) + `appuser` (uid 1001, no home directory).
- `mkdir -p /app/logs` and `chown appuser:appgroup /app/weather-station-pusher.jar /app/logs` before `USER appuser`.
- `exec java` in the entrypoint replaces the shell so Java is PID 1 and receives `SIGTERM` directly.
- `curl` is installed in the runtime stage — the `eclipse-temurin:21-jre` base ships neither `curl` nor `wget`, so a `wget`-based HEALTHCHECK would always fail.

```sh
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*
EXPOSE 8081
# Liveness only: a DB outage must not mark the container unhealthy — the worker
# sleeps and recovers on its own. Overall /actuator/health includes the DB check.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -sf http://localhost:8081/actuator/health/liveness || exit 1
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/weather-station-pusher.jar"]
```

`.dockerignore` must exclude: `.git`, `.idea`, `target`, `docs`, `.env`.  
Do **not** bake a real `.env` into the image.

### Health endpoint

Spring Boot Actuator serves on **port 8081** — the application's only HTTP listener (`server.port: 8081`, no separate management port, nothing listens on 8080). The app has no controllers, so the listener serves only the actuator endpoints; every other path returns 404.

| Path | Purpose |
|---|---|
| `GET /actuator/health` | Overall status incl. DB indicator (`{"status":"UP"}`) |
| `GET /actuator/health/liveness` | Liveness probe (Docker `HEALTHCHECK` + k8s `livenessProbe`) |
| `GET /actuator/health/readiness` | Kubernetes readiness probe |

`start-period=60s` accounts for database connection time at startup.

**Kubernetes probe example:**
```yaml
livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: 8081
  initialDelaySeconds: 60
  periodSeconds: 30
readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 8081
  initialDelaySeconds: 60
  periodSeconds: 10
```

---

## Testing

Unit tests (JUnit 5 + Mockito + AssertJ, all via `spring-boot-starter-test`) cover every functional class — no Spring context is started; collaborators are mocked. One test class per production class, under `src/test/java/com/fishfind/weather/...`.

Testability seams (production behaviour unchanged):
- `OpenMeteoFetcher` — `weather.worker.open-meteo-base-url` lets tests target a local `HttpServer`.
- `StationWorker` — `protected void sleep(long)` so tests run without real waits.
- `ConsoleDebugRunner` — `protected void exit(int)` so the console path doesn't terminate the JVM.

`OpenMeteoFetcherTest` spins up a real loopback `com.sun.net.httpserver.HttpServer` to exercise the 200 / 404 / non-200 branches, the verbatim body, the daily `User-Agent` (build numbers in `[11, 97]`, stable per day, varying across days), and the **429 `Retry-After`** path (retry-then-succeed and exhausted → `RateLimitedException`). `StationWorkerTest` covers the **post-processing gate** (skipped-don't-block, degraded-cycle skip), the **stop-requested** short-circuit, and the **shutdown** flag.

`CycleReportRecorderTest` covers insertion order and the 7-entry eviction cap. `WeeklyReportMailServiceTest` mocks `JavaMailSender` and `ServiceLifecycleTracker` to cover: skip-when-`to`-blank, skip only when both cycles AND incidents are empty (crash-loop case still sends), one email covering every recorded day, incident details in the body, `from` → `spring.mail.username` fallback, and a `MailException` being caught rather than propagated. `ServiceLifecycleTrackerTest` uses `@TempDir` to cover: first-ever startup (no incident), clean-shutdown-then-restart (no incident), an unclean shutdown with a real JSON log file (incident recorded with the last ERROR line as description), a crash with no log file (fallback description), 7-day retention trimming, and an unwritable state dir not throwing.

---

## Explicitly not implemented

Do not add these unless explicitly requested:

- Weather Underground worker
- Canadian station processing
- Windows Service hosting
- Java-side parsing of weather JSON into hourly/daily rows
- Automatic station disabling
- API key handling for Open-Meteo

---

## Recreation checklist

1. Maven Java 21 Spring Boot project; coordinates `com.fishfind:weather-station-pusher:1.0.0`.
2. Add dependencies (web, actuator, JDBC, AOP, MSSQL, Resilience4j, dotenv, logback).
3. Add build plugins: `cyclonedx-maven-plugin:2.9.2` + `dependency-check-maven:12.2.2`.
4. Implement dotenv bootstrap in `WeatherStationPusherApplication` using `setDefaultProperties()` — **no** `System.setProperty()` for secrets.
5. `StationRef` record: `mli`, `latitude`, `longitude`, `state`.
6. `WeatherStationRepository` — `vwWeatherForecastToDay` US query.
7. `OpenMeteoFetcher` — `HttpURLConnection`; daily `User-Agent`; verbatim UTF-8 body; `@Retry`/`@CircuitBreaker`/`@RateLimiter` (`openMeteo`) + inline 429 `Retry-After`; `RateLimitedException`.
8. `WeatherDataRepository` — `UPDATE dbo.ows_meteo`, two stored procedure methods, Resilience4j.
9. `ProcessingOutcome` enum; `StationProcessorBase` — template method returning the outcome.
10. `StationProcessorOpen` — fetch + save flow.
11. `StationPostProcessingService` — exact procedure order.
12. `StationWorker` — background thread, 8-hour dynamic delay, midnight sleep, `@PreDestroy` graceful shutdown, post-processing success gate, records a `CycleReportEntry` per completed cycle.
13. `ConsoleDebugRunner` — `--console` + `--station` one-shot mode.
14. `CycleReportEntry` record + `CycleReportRecorder` — in-memory last-7-days-per-worker buffer (not persisted).
15. `IncidentEntry` record + `ServiceLifecycleTracker` — marker-file crash detection + log-tail description; degrades gracefully if its state dir is unwritable.
16. `WeeklyReportMailService` — `@Scheduled` Friday email built from the recorder and the lifecycle tracker; skips (not fails) only when both are empty; catches `MailException`.
17. `application.yml` and `logback-spring.xml` (incl. `spring.mail.*`, `weather.report.*`, `weather.lifecycle.*`, all-blank-safe defaults).
18. `.env.example` (`trustServerCertificate=false`; optional `SMTP_*` / `REPORT_EMAIL_*`), `.owasp-suppressions.xml`, `.dockerignore`.
19. `Dockerfile`: non-root `appuser` (uid 1001), `exec java` entrypoint, `EXPOSE 8081` + `HEALTHCHECK`.
20. Deploy tooling (`docs/do-update.md`, `update-weather` skill): graceful `docker stop` before `docker rm` (never `-f`), plus a persistent `/app/logs` volume mount — both required for crash tracking to work across redeploys.
21. Unit tests for all functional classes (see **Testing**) via the sleep/exit/base-url seams.
22. Verify: `mvn test`

---

## Fidelity notes

This service mirrors only the `WeatherDataWorkerOpen` path of the legacy .NET `OWMService`:
- Only the Open-Meteo worker is present.
- US and CA station loops are processed.
- Persistence is an `UPDATE` into existing `ows_meteo` rows (not an insert).
- Post-processing order follows the legacy weather worker base implementation.
- Daily cadence aligns to midnight, not top-of-hour.

If future work restores Weather Underground or Windows Service hosting, update this document rather than treating it as a superset of missing functionality.
