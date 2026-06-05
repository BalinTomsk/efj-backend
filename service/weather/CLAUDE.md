# CLAUDE.md
# weather-station-pusher — Claude Context

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

## Project identity

| Key | Value |
|-----|-------|
| Service name | `debian-weather` |
| Language | Java 21 |
| Build | Maven |
| Framework | Spring Boot 3.2.x |
| Main class | `com.fishfind.weather.WeatherStationPusherApplication` |

---

## Goal

- Poll up to 1400 US weather stations from MSSQL (`dbo.vwWeatherForecastToDay`).
- Fetch raw JSON forecast data from Open-Meteo for each station.
- Store the raw JSON as-is into `dbo.ows_meteo` with source type `2`. **Do not parse JSON in Java.**
- After each full pass, run post-processing stored procedures in order:
  1. `dbo.spPushSpeciesFromLakeToStation`
  2. `dbo.spTotalUpdateProbability`
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
    ├── OpenMeteoFetcher.java
    ├── StationPostProcessingService.java
    ├── StationProcessorBase.java  # shared exception handling (template method)
    ├── StationProcessorOpen.java
    └── StationWorker.java         # ApplicationRunner entry point
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
src/main/java/com/fishfind/weather/service/OpenMeteoFetcher.java
src/main/java/com/fishfind/weather/service/StationPostProcessingService.java
src/main/java/com/fishfind/weather/service/StationProcessorBase.java
src/main/java/com/fishfind/weather/service/StationProcessorOpen.java
src/main/java/com/fishfind/weather/service/StationWorker.java
src/main/resources/application.yml
src/main/resources/logback-spring.xml
.env.example          (project root, placeholder values only)
Dockerfile
.dockerignore
```

**Never include:** real `.env`, secrets, or `.env` under `src/main/resources`.

---

## Dependencies (pom.xml)

- Maven coordinates: `com.fishfind:weather-station-pusher:1.0.0`
- `spring-boot-starter`
- `spring-boot-starter-jdbc`
- `spring-boot-starter-aop`
- `mssql-jdbc` (`com.microsoft.sqlserver.jdbc.SQLServerDriver`)
- `io.github.resilience4j:resilience4j-spring-boot3`
- `io.github.cdimascio:dotenv-java`
- SLF4J + Logback (via Spring Boot default)
- `spring-boot-starter-test` (test scope)

---

## Startup / credential loading

1. **Before Spring initialises**, read `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` from process environment or JVM system properties.
2. If any are missing, attempt to load from a dotenv file:
   - if `DOTENV_PATH` is set and non-blank, load that path
   - otherwise, if a `.env` file exists in the working directory, load it
   - ignore missing or malformed dotenv files
3. Copy loaded values into JVM system properties only when the corresponding env var and system property are both missing.

---

## Configuration (`application.yml`)

```yaml
spring:
  datasource:
    url: ${DB_URL}
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}
    driver-class-name: com.microsoft.sqlserver.jdbc.SQLServerDriver

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

weather:
  worker:
    connect-timeout-ms: 15000
    read-timeout-ms: 30000

logging:
  level:
    root: INFO
    com.fishfind.weather: INFO
```

---

## Worker behaviour

### Thread

- Launched by `StationWorker` (`ApplicationRunner`).
- Thread name: `weather-data-worker-open`.
- **Non-daemon** thread.
- If app starts with `--console`: **do not launch the background thread**.

### Per-cycle loop

1. Load US stations from `dbo.vwWeatherForecastToDay` (max 1400).
2. Compute target delay: `max(8_hours_ms / stationCount, 2000)`. If count ≤ 1, use `2000 ms`.
3. For each station: fetch JSON → save to `dbo.ows_meteo` → sleep `(targetDelay - actualProcessingTime)` (skip sleep if negative).
4. Run post-processing procedures.
5. Sleep until next local midnight (skip if already past boundary).

---

## Console / debug mode (`--console`)

- Activated by `--console` command-line arg (`@Order(0)`, exits process when done).
- Optional: `--station=<MLI>` to filter to one station.
- Runs exactly one processing pass; no background thread started.

---

## Station query (`WeatherStationRepository`)

```sql
SELECT TOP 1400 mli, lat, lon, state
FROM dbo.vwWeatherForecastToDay
WHERE country = 'US'
```

Model: `StationRef(String mli, double latitude, double longitude, String state)`

---

## HTTP fetch (`OpenMeteoFetcher`)

- Transport: `HttpURLConnection`, method `GET`.
- Connect timeout: `weather.worker.connect-timeout-ms` (default 15 000 ms).
- Read timeout: `weather.worker.read-timeout-ms` (default 30 000 ms).
- Browser-like `User-Agent` header.
- HTTP 200 → read response body as UTF-8; replace `\\\"` → `\"`.
- HTTP 404 → throw `FileNotFoundException`.
- Any other non-200 → throw `IOException`.

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

```sql
UPDATE dbo.ows_meteo
SET type = 2, ows = ?, stamp = GETDATE()
WHERE mli = ?
```

### Post-processing procedures

```java
pushSpeciesFromLakeToStation()  // → EXEC dbo.spPushSpeciesFromLakeToStation
totalUpdateProbability()        // → EXEC dbo.spTotalUpdateProbability
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
2. Log save start with payload byte count.
3. Update `dbo.ows_meteo` via `WeatherDataRepository`.
4. Log station processed.

`StationPostProcessingService` calls procedures in this exact order (matches legacy base):
1. `dbo.spPushSpeciesFromLakeToStation`
2. `dbo.spTotalUpdateProbability`

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
| HTTP 404 from Open-Meteo | throw `FileNotFoundException`; log skip; continue |
| HTTP non-200 other than 404 | throw `IOException`; log warning; continue |
| Per-station processing exception | log warning with station and state; continue |
| SQL write failure | Resilience4j retry/circuit breaker; then runtime exception propagates |
| Post-processing emits result sets | drain with `getMoreResults`; continue normally |
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
- Fetch success per station
- Save start (with payload byte count)
- Station processed
- Post-processing procedure execution
- Skip due to unpublished source (info)
- Station processing failure (warning)
- Cycle completion with next run time

---

## Docker

Build stage: `maven:3.9.9-eclipse-temurin-21` — runs `mvn -B -DskipTests package`.  
Runtime stage: `eclipse-temurin:21-jre` — copies jar to `/app/weather-station-pusher.jar`.

```sh
CMD java $JAVA_OPTS -jar /app/weather-station-pusher.jar
```

`.dockerignore` must exclude: `.git`, `.idea`, `target`, `docs`, `.env`.  
Do **not** bake a real `.env` into the image.

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
2. Add dependencies (JDBC, AOP, MSSQL, Resilience4j, dotenv, logback).
3. Implement dotenv bootstrap in `WeatherStationPusherApplication` (before Spring starts).
4. `StationRef` record: `mli`, `latitude`, `longitude`, `state`.
5. `WeatherStationRepository` — `vwWeatherForecastToDay` US query.
6. `OpenMeteoFetcher` — `HttpURLConnection` with response rules above.
7. `WeatherDataRepository` — `UPDATE dbo.ows_meteo`, two stored procedure methods, Resilience4j.
8. `StationProcessorBase` — template method exception handling.
9. `StationProcessorOpen` — fetch + save flow.
10. `StationPostProcessingService` — exact procedure order.
11. `StationWorker` — background thread, 8-hour dynamic delay, midnight sleep.
12. `ConsoleDebugRunner` — `--console` + `--station` one-shot mode.
13. `application.yml` and `logback-spring.xml`.
14. `.env.example`, `.dockerignore`, `Dockerfile`.
15. Verify: `mvn -DskipTests compile`

---

## Fidelity notes

This service mirrors only the `WeatherDataWorkerOpen` path of the legacy .NET `OWMService`:
- Only the Open-Meteo worker is present.
- Only US stations are processed.
- Persistence is an `UPDATE` into existing `ows_meteo` rows (not an insert).
- Post-processing order follows the legacy weather worker base implementation.
- Daily cadence aligns to midnight, not top-of-hour.

If future work restores Weather Underground or Windows Service hosting, update this document rather than treating it as a superset of missing functionality.
