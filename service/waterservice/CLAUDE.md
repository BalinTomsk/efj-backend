# water-station-pusher — Claude Context

> This file captures the full specification and architectural rules needed to recreate,
> extend, or debug the `water-station-pusher` Spring Boot service.
> Source: `efj-backend/service/waterservice/docs/specification.txt`

---

## Keeping docs in sync — IMPORTANT

`docs/specification.txt` is the **single source of truth** used to recreate this service from scratch.
It must always reflect the current state of the code.

**Rules:**

- Whenever **any source file** (`*.java`, `pom.xml`, `application.yml`, `logback-spring.xml`,
  `Dockerfile`, etc.) is created, modified, or deleted — update `docs/specification.txt` to match.
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
- @srv/../../database/database/mssql

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

- Poll supported Canadian and US water stations from MSSQL (`vwWaterStation`).
- Download each **CA** station's hourly hydrometric CSV from Environment Canada.
- Download each **US** station's WaterML payload from USGS.
- Parse readings and upsert them into `dbo.WaterData`.
- After each worker cycle, synchronously run stale-data cleanup:
  1. `dbo.sp_clean_old_water_data`
- When at least one station succeeds in a cycle, also run:
  1. `dbo.spPushSpeciesFromLakeToStation`
- Log failures and skipped unpublished-source events; **do not disable stations automatically**.

---

## Package layout

```
com.fishfind.water
├── domain
│   ├── Reading.java            # stationId, stamp (OffsetDateTime), waterLevel, discharge
│   ├── StationRef.java         # mli, state, tz  (record)
│   └── UsSeriesReading.java    # variable metadata + XML payload
├── repo
│   ├── WaterDataRepository.java
│   └── WaterStationRepository.java
├── config
│   ├── DotenvEnvironmentPostProcessor.java  # local .env → low-precedence property source
│   ├── WorkerConfig.java                     # cycleScheduler + countryPassExecutor beans
│   └── HttpClientConfig.java                 # pooled RestClient (JDK HttpClient) for source feeds
├── service
│   ├── CsvFetcherCA.java
│   ├── XmlFetcherUS.java
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
src/main/java/com/fishfind/water/service/XmlFetcherUS.java
src/main/java/com/fishfind/water/service/StationProcessorCA.java
src/main/java/com/fishfind/water/service/StationProcessorUS.java
src/main/java/com/fishfind/water/service/StationWorker.java
src/main/java/com/fishfind/water/service/ConsoleDebugRunner.java
src/main/java/com/fishfind/water/service/StationPostProcessingService.java
src/main/java/com/fishfind/water/web/HealthController.java
src/main/java/com/fishfind/water/config/DotenvEnvironmentPostProcessor.java
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
- MSSQL JDBC driver (`com.microsoft.sqlserver.jdbc.SQLServerDriver`; version overridden via
  `<mssql-jdbc.version>` to the current 12.8.x line)
- `io.github.resilience4j:resilience4j-spring-boot3`
- `commons-csv` (used for CA CSV parsing)
- `io.github.cdimascio:dotenv-java`
- SLF4J + Logback (via Spring Boot default)

---

## Startup / credential loading

1. `main()` only calls `SpringApplication.run`. Credential loading is handled by a Spring
   `EnvironmentPostProcessor` (`com.fishfind.water.config.DotenvEnvironmentPostProcessor`), registered in
   `src/main/resources/META-INF/spring/org.springframework.boot.env.EnvironmentPostProcessor.imports`.
2. Spring resolves `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` from the process environment / JVM system properties.
3. For local dev, the post-processor loads a `.env` file and registers it as the **lowest-precedence** property
   source (`addLast`):
   - Default location: project root; override with `DOTENV_PATH` env var.
   - Only keys declared in the file are imported (`Dotenv.Filter.DECLARED_IN_ENV_FILE`).
   - Real env vars / system properties always win over `.env`.
4. **SECURITY:** credentials are **never** copied into JVM-global system properties (no `System.setProperty`),
   so they cannot leak via `System.getProperties()`, heap dumps, or diagnostic tooling.

---

## Datasource config (`application.yml`)

```yaml
spring:
  datasource:
    url: ${DB_URL}
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}
    driver-class-name: com.microsoft.sqlserver.jdbc.SQLServerDriver
    hikari:                  # tuned for MSSQL + two parallel passes
      pool-name: water-hikari
      maximum-pool-size: 4
      minimum-idle: 1
      connection-timeout: 30000
      max-lifetime: 1740000  # 29 min — retire before server idle timeout
      keepalive-time: 300000
      validation-timeout: 5000
```

---

## Worker behaviour

### Lifecycle (Spring-managed — no hand-managed threads)

- `WorkerConfig` provides two Spring beans (graceful shutdown on context close):
  - `cycleScheduler` — single-thread `ThreadPoolTaskScheduler` (`water-cycle-`). Pool size 1 ⇒ an overrunning
    cycle delays the next trigger instead of overlapping (no tight-loop).
  - `countryPassExecutor` — 2-thread `ThreadPoolTaskExecutor` (`water-pass-`) for parallel CA/US passes.
- `StationWorker` (`ApplicationRunner`): if `--console`, schedule nothing; otherwise register one recurring
  cycle on `cycleScheduler` via a `CronTrigger` from `water.worker.cron` (default `0 0 * * * *`).

### Cycle (`runCycle`, used by scheduler AND console)

1. Run CA and US passes **in parallel** on `countryPassExecutor`; a failure of one country is isolated/logged.
2. Each pass (`runOnce`) loads its stations, processes them one by one sleeping `pause-between-stations-ms`
   **between** stations only — never after the last (interrupt-aware), and returns the count processed **successfully**.
3. Run species post-processing **exactly once per cycle**, and **only if ≥1 station succeeded**.
4. Run stale-data cleanup **exactly once after every cycle** through `dbo.sp_clean_old_water_data`.
   - `dbo.spPushSpeciesFromLakeToStation`
   - (Previously each worker thread ran this independently ⇒ the SP executed twice, concurrently. Fixed.)
5. Failure semantics: a species post-processing failure never blocks cleanup; if cleanup **also** fails, the
   species exception propagates with the cleanup exception as **suppressed** (no finally-masking). The
   cycle-completed summary log is always emitted.
6. Shutdown-safe pass startup: executor rejection ⇒ failed future (empty pass), and `awaitPass` handles
   `CompletionException` **and** `CancellationException`.
- `StationProcessorBase.process(...)` returns `boolean` so the cycle knows whether anything succeeded.

### Configurable properties

```yaml
water:
  worker:
    cron: "0 0 * * * *"               # default — top of every hour (Spring 6-field cron)
    pause-between-stations-ms: 1000   # default
    connect-timeout-ms: 15000         # default
    read-timeout-ms: 30000            # default
```

---

## Console / debug mode (`--console`)

- Activated by `--console` command-line arg.
- Optional: `--station=<MLI>` to filter to one station.
- Delegates to `StationWorker.runCycle(station)` — one cycle: both countries in parallel + a single
  post-processing run. Identical to scheduled behavior.

---

## Station query (`WaterStationRepository`)

- View: `vwWaterStation`
- Columns selected: `mli`, `state`, `tz`
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

## US fetch (`XmlFetcherUS`)

- URL: `https://waterservices.usgs.gov/nwis/iv/?sites={MLI}&period=P3D&format=waterml`
- SECURITY: built as a RestClient **URI template** — `mli` is strictly URL-encoded, so a DB value cannot
  append or override query parameters.
- `fetch` returns the raw XML body `String`. `@Retry("httpRetry")` + `@CircuitBreaker("usFeed")`.
- HTTP 404 → `FileNotFoundException` → station skipped. The exception message names the feed, station, and state (self-sufficient without caller context).
- Transient failures (premature EOF, socket timeouts, 5xx) retried by `httpRetry` — the old hand-rolled retry
  loop was removed.

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

- Parse USGS WaterML into one stored-procedure payload per variable (`UsSeriesReading`).
- Preserve variable metadata and XML payload content.
- Reduce values to **daily entries** before building the stored-procedure payload: for each day, keep the
  **latest sample by timestamp** (document order is not trusted — USGS does not guarantee it).
- **SECURITY (XXE):** WaterML is untrusted input. Harden `DocumentBuilderFactory` + `XPathFactory` before
  parsing — enable `FEATURE_SECURE_PROCESSING`, set `disallow-doctype-decl=true`, disable external
  general/parameter entities and external DTD loading, `setXIncludeAware(false)`,
  `setExpandEntityReferences(false)`. A DOCTYPE/entity payload must be rejected, never expanded.

---

## Failure handling (shared — `StationProcessorBase`)

- On any station processing exception: log warning with country, station, state; continue.
- HTTP 404: log "source feed not published"; do not disable station.
- **Do not call** `dbo.sp_DisableWaterStation`.
- Log message format: `{country} station` (e.g., `"CA station"`, `"US station"`).

---

## Persistence (`WaterDataRepository`)

### `saveStationData(String mli, List<Reading> readings)`

- Reject blank `mli`.
- No-op if readings is null or empty.
- Wrap in a single transaction.
- Deduplicate readings by timestamp within the batch; **keep the last duplicate**.
- Upsert via legacy SP: `dbo.sp_UpdateWaterData`, executed as **one JDBC batch** (`jdbc.batchUpdate`)
  instead of one round-trip per reading — the DB is remote and a cycle can push tens of thousands of rows.
  - `waterLevel` → `dbo.WaterData.elevation`
  - `discharge` → `dbo.WaterData.discharge`
  - Timestamp stored as SQL `datetime2`.
- Apply Resilience4j retry + circuit breaker around SQL operations.

### `saveUsStationData(String mli, String state, List<UsSeriesReading> seriesList)`

- Use legacy SP: `dbo.sp_push_us_water_data`
- **Ignore** empty variable payloads instead of failing the full station save.

### Post-processing methods

```java
cleanOldWaterData()            // → dbo.sp_clean_old_water_data
pushSpeciesFromLakeToStation() // → dbo.spPushSpeciesFromLakeToStation
```

- Both must **tolerate** procedures that emit incidental result sets or update counts.

### Delete logic

- There was earlier intent to delete `WaterData` rows older than 15 days per station.
- **That delete is not active in the current state.** Do not restore it unless explicitly asked.
- Cleanup happens only through `dbo.sp_clean_old_water_data`.

---

## Resilience4j configuration

- **Aspect order:** `circuit-breaker-aspect-order: 2` > `retry-aspect-order: 1` ⇒ the **breaker is outermost**
  (an open breaker fails fast without burning retries; all retries of one call = one breaker outcome).
- **SQL** (`WaterDataRepository`): retry `sqlRetry` (3×/2s on `DataAccessException`/`SQLException`), breaker
  `sqlBreaker` (window 10, min 5, 50%, open 30s).
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
DB_URL=jdbc:sqlserver://localhost:1433;databaseName=fishfind
DB_USERNAME=your_username
DB_PASSWORD=your_password
# Optional: path to a custom .env file
DOTENV_PATH=
```
