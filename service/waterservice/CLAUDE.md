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
- @srv/../database/database/mssql/ffi2.sql  

---

## Project identity

| Key | Value |
|-----|-------|
| Service name | `water-station-pusher` |
| Language | Java 21 |
| Build | Maven |
| Framework | Spring Boot 3.2.x |
| Main class | `com.fishfind.water.WaterStationPusherApplication` |

---

## Goal

- Poll supported Canadian and US water stations from MSSQL (`vwWaterStation`).
- Download each **CA** station's hourly hydrometric CSV from Environment Canada.
- Download each **US** station's WaterML payload from USGS.
- Parse readings and upsert them into `dbo.WaterData`.
- After each worker pass, synchronously run stored procedures in order:
  1. `dbo.spCleanWeatherWaterData`
  2. `dbo.spPushSpeciesFromLakeToStation`
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
├── service
│   ├── CsvFetcherCA.java
│   ├── XmlFetcherUS.java
│   ├── StationProcessorCA.java
│   ├── StationProcessorUS.java
│   ├── StationProcessorBase.java   # shared exception handling; formats "{country} station"
│   ├── StationWorker.java          # ApplicationRunner entry point
│   ├── ConsoleDebugRunner.java
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
- MSSQL JDBC driver (`com.microsoft.sqlserver.jdbc.SQLServerDriver`)
- `io.github.resilience4j:resilience4j-spring-boot3`
- `commons-csv` (optional; simple CSV parsing is acceptable)
- `io.github.cdimascio:dotenv-java`
- SLF4J + Logback (via Spring Boot default)

---

## Startup / credential loading

1. On startup, **before Spring initialises**, read `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` from environment variables or JVM system properties.
2. If any are missing, attempt to load from a `.env` file:
   - Default location: project root.
   - Override with `DOTENV_PATH` env var.
3. Copy any values loaded from dotenv into JVM system properties so Spring's `${...}` placeholders resolve.

---

## Datasource config (`application.yml`)

```yaml
spring:
  datasource:
    url: ${DB_URL}
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}
    driver-class-name: com.microsoft.sqlserver.jdbc.SQLServerDriver
```

---

## Worker behaviour

### Threads

- Launched by `StationWorker` via `ApplicationRunner`.
- Thread names: `water-station-worker-ca`, `water-station-worker-us`.
- **Non-daemon** threads.
- If app is started with `--console`: **do not launch either thread**.

### Loop (each worker independently)

1. Load supported stations for its country from `vwWaterStation`.
2. Process stations one by one, sleeping `pause-between-stations-ms` between each.
3. After completing the full pass, run post-processing procedures **synchronously in order**:
   - `dbo.spCleanWeatherWaterData`
   - `dbo.spPushSpeciesFromLakeToStation`
4. Sleep until the next top-of-hour if the cycle finished early; start immediately if already past the boundary.

### Configurable properties

```yaml
water:
  worker:
    pause-between-stations-ms: 1000   # default
    connect-timeout-ms: 15000         # default
    read-timeout-ms: 30000            # default
```

---

## Console / debug mode (`--console`)

- Activated by `--console` command-line arg.
- Optional: `--station=<MLI>` to filter to one station.
- Runs exactly one processing pass for **both** country workers **in parallel**.
- Each worker still runs its own post-processing sequence after its pass.

---

## Station query (`WaterStationRepository`)

- View: `vwWaterStation`
- Columns selected: `mli`, `state`, `tz`
- CA worker filter: `country = 'CA'`
- US worker filter: `country = 'US'`
- Model: `StationRef(String mli, String state, int tz)` — simple record.

---

## CA fetch (`CsvFetcherCA`)

- URL: `https://dd.weather.gc.ca/today/hydrometric/csv/{STATE}/hourly/{STATE}_{MLI}_hourly_hydrometric.csv`
- Example: `.../QC/hourly/QC_02JE025_hourly_hydrometric.csv`
- Transport: `HttpURLConnection`
- Set connect/read timeouts from config.
- Set a browser-like `User-Agent`.
- Non-200 → failure.
- HTTP 404 → `FileNotFoundException` semantics → station skipped, log "source feed not published".

---

## US fetch (`XmlFetcherUS`)

- URL: `https://waterservices.usgs.gov/nwis/iv/?sites={MLI}&period=P3D&format=waterml`
- Transport: `HttpURLConnection`
- Set connect/read timeouts from config.
- Set a browser-like `User-Agent`.
- Non-200 → failure.
- HTTP 404 → `FileNotFoundException` semantics → station skipped.
- **Retry** transient `IOException`s up to **3 attempts** for:
  - `EOFException`
  - `SocketTimeoutException`
  - `SocketException`
  - messages containing `"Premature EOF"`

---

## CSV parse rules (`StationProcessorCA`)

- Skip row 0 (header).
- Skip rows with fewer than 7 columns.
- Column mapping:
  - `[0]` → station id (String, trimmed)
  - `[1]` → timestamp (`OffsetDateTime`)
  - `[2]` → water level (Double, null if empty)
  - `[6]` → discharge (Double, null if empty)
- Model: `Reading(String stationId, OffsetDateTime stamp, Double waterLevel, Double discharge)`

---

## US parse rules (`StationProcessorUS`)

- Parse USGS WaterML into one stored-procedure payload per variable (`UsSeriesReading`).
- Preserve variable metadata and XML payload content.
- Reduce values to **daily entries** before building the stored-procedure payload.

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
- Upsert via legacy SP: `dbo.sp_UpdateWaterData`
  - `waterLevel` → `dbo.WaterData.elevation`
  - `discharge` → `dbo.WaterData.discharge`
  - Timestamp stored as SQL `datetime2`.
- Apply Resilience4j retry + circuit breaker around SQL operations.

### `saveUsStationData(String mli, String state, List<UsSeriesReading> seriesList)`

- Use legacy SP: `dbo.sp_push_us_water_data`
- **Ignore** empty variable payloads instead of failing the full station save.

### Post-processing methods

```java
cleanWeatherWaterData()        // → dbo.spCleanWeatherWaterData
pushSpeciesFromLakeToStation() // → dbo.spPushSpeciesFromLakeToStation
```

- Both must **tolerate** procedures that emit incidental result sets or update counts.

### Delete logic

- There was earlier intent to delete `WaterData` rows older than 15 days per station.
- **That delete is not active in the current state.** Do not restore it unless explicitly asked.
- Cleanup happens only through `dbo.spCleanWeatherWaterData`.

---

## Resilience4j configuration

```yaml
resilience4j:
  retry:
    instances:
      sqlRetry:
        max-attempts: 3
        wait-duration: 2s
        retry-exceptions:
          - org.springframework.dao.DataAccessException
          - java.sql.SQLException
  circuitbreaker:
    instances:
      sqlBreaker:
        sliding-window-size: 10
        minimum-number-of-calls: 5
        failure-rate-threshold: 50
        wait-duration-in-open-state: 30s
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

---

## Docker

```dockerfile
# Multi-stage: build with Maven, runtime launches:
CMD java $JAVA_OPTS -jar /app/water-station-pusher.jar
```

- Do **not** bake the real `.env` into the image or jar resources.
- `.dockerignore` must exclude `.env`, secrets, and local build artifacts.

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
