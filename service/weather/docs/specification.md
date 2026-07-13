# Weather Service Specification

> Purpose: this document describes the Java service in `service/weather` completely enough to recreate it from zero.

---

## 1. Overview

`weather-station-pusher` is a Java 21 Spring Boot background service that reproduces the current Open-Meteo portion of the legacy `OWMService`.

The current project state intentionally implements only the behavior of `WeatherDataWorkerOpen`.

The service:

- loads database credentials from environment variables or a root `.env` file
- starts a single Open-Meteo worker unless the app is launched in console mode
- reads supported US weather stations from SQL Server
- fetches raw JSON forecast data from Open-Meteo for each station
- updates the existing `dbo.ows_meteo` row for that station with the fetched JSON and source type `2`
- runs the legacy post-processing stored procedures after each full pass
- waits until the next midnight before starting the next cycle

This is a raw weather-payload pusher. It does not parse weather JSON in Java. Parsing remains on the database side through the existing SQL-side logic already tied to `ows_meteo`.

---

## 2. Technology Stack

| Component | Technology |
|---|---|
| Runtime | Java 21 |
| Build | Maven |
| Framework | Spring Boot 3.2.5 |
| JDBC | `spring-boot-starter-jdbc` |
| AOP | `spring-boot-starter-aop` |
| SQL retry/circuit breaker | Resilience4j Spring Boot 3 |
| Database | Microsoft SQL Server |
| HTTP client | `HttpURLConnection` |
| Logging | SLF4J + Logback |
| Local env loading | `dotenv-java` |
| Packaging | Spring Boot executable jar |
| Container | Docker multi-stage build |

---

## 3. Project Structure

```text
weather/
├── .dockerignore
├── .env.example
├── Dockerfile
├── pom.xml
├── doc/
│   └── specification.md
└── src/
    └── main/
        ├── java/
        │   └── com/fishfind/weather/
        │       ├── WeatherStationPusherApplication.java
        │       ├── domain/
        │       │   └── StationRef.java
        │       ├── repo/
        │       │   ├── WeatherDataRepository.java
        │       │   └── WeatherStationRepository.java
        │       └── service/
        │           ├── ConsoleDebugRunner.java
        │           ├── OpenMeteoFetcher.java
        │           ├── StationPostProcessingService.java
        │           ├── StationProcessorBase.java
        │           ├── StationProcessorOpen.java
        │           └── StationWorker.java
        └── resources/
            ├── application.yml
            └── logback-spring.xml
```

---

## 4. Functional Scope

### 4.1 Implemented behavior

The recreated service implements these legacy behaviors:

- worker source: Open-Meteo only
- station country: US only
- station limit: `TOP 1400`
- source type written to `ows_meteo`: `2`
- URL shape:
  - `https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&hourly=temperature_2m,relative_humidity_2m,precipitation_probability,pressure_msl,wind_speed_10m,wind_direction_10m,weather_code,rain&daily=temperature_2m_max,temperature_2m_min&timezone=auto`
- post-processing procedures:
  - `dbo.spPushSpeciesFromLakeToStation`
  - `dbo.spTotalUpdateProbability`
- processing window:
  - 8-hour time budget distributed across all selected stations
- cycle timing:
  - after a full pass, sleep until next midnight

### 4.2 Explicitly not implemented

Do not add these unless explicitly requested:

- Weather Underground worker behavior
- Canadian station processing
- Windows Service hosting
- Java-side parsing of weather JSON into hourly/daily rows
- automatic station disabling
- API key handling for Open-Meteo

---

## 5. Configuration

### 5.1 Required environment variables

The service expects:

- `DB_URL`
- `DB_USERNAME`
- `DB_PASSWORD`

These values back Spring datasource placeholders directly.

### 5.2 Dotenv fallback

Before Spring starts:

1. check process environment
2. check JVM system properties
3. if values are still missing, load a dotenv file

Dotenv rules:

- if `DOTENV_PATH` is set and non-blank, load that file
- otherwise, if a root `.env` file exists in the working directory, load it
- ignore missing dotenv files
- ignore malformed dotenv content
- copy loaded values into JVM system properties only when the corresponding env var and system property are both missing

### 5.3 Application configuration

`src/main/resources/application.yml` must define:

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

### 5.4 Root `.env.example`

Keep a root `.env.example` with placeholder values only. Do not commit a real `.env`.

Example:

```dotenv
DB_URL=jdbc:sqlserver://host.docker.internal:1433;databaseName=fishfind;encrypt=true;trustServerCertificate=false
DB_USERNAME=your_username
DB_PASSWORD=your_password
# DOTENV_PATH=/app/.env
# JAVA_OPTS=-Xms256m -Xmx512m
```

---

## 6. Main Classes

### 6.1 `WeatherStationPusherApplication`

Responsibilities:

- load dotenv-backed DB credentials before Spring starts
- start Spring Boot application

Rules:

- package name: `com.fishfind.weather`
- class name: `WeatherStationPusherApplication`
- annotate with `@SpringBootApplication`

### 6.2 `StationRef`

Simple record representing a station to process:

```java
public record StationRef(String mli, double latitude, double longitude, String state) {}
```

### 6.3 `WeatherStationRepository`

Loads supported stations for the Open worker using:

```sql
SELECT TOP 1400 mli, lat, lon, state
FROM dbo.vwWeatherForecastToDay
WHERE country = 'US'
```

Mapping:

- `mli` -> station id
- `lat` -> latitude
- `lon` -> longitude
- `state` -> state code

### 6.4 `OpenMeteoFetcher`

Uses `HttpURLConnection` and:

- method: `GET`
- connect timeout from `weather.worker.connect-timeout-ms`
- read timeout from `weather.worker.read-timeout-ms`
- browser-like `User-Agent`

Response rules:

- HTTP 200: read response body as UTF-8 string and return it
- HTTP 404: throw `FileNotFoundException`
- any non-200 other than 404: throw `IOException`

Current payload cleanup:

- replace `\\\"` with `\"`

### 6.5 `WeatherDataRepository`

Implements SQL-side persistence and procedures.

#### Save raw JSON

Method:

```java
void saveStationData(String mli, String jsonData)
```

Rules:

- reject blank `mli`
- if `jsonData` is null or blank, do nothing
- run in a transaction
- protect with Resilience4j retry and circuit breaker
- execute:

```sql
UPDATE dbo.ows_meteo
SET type = 2, ows = ?, stamp = GETDATE()
WHERE mli = ?
```

#### Post-processing procedures

Methods:

- `pushSpeciesFromLakeToStation()`
- `totalUpdateProbability()`

Rules:

- each runs in a transaction
- each is protected by Resilience4j retry and circuit breaker
- procedures may emit incidental result sets or update counts
- implementation must drain results using `PreparedStatementCallback` and `getMoreResults`

SQL:

```sql
EXEC dbo.spPushSpeciesFromLakeToStation
EXEC dbo.spTotalUpdateProbability
```

### 6.6 `StationProcessorBase`

Shared exception handling wrapper using the template method pattern.

Rules:

- expose `process(StationRef station)` as `final`
- call `processStation(station)` inside a try/catch
- if exception is `FileNotFoundException`, log an info skip message
- otherwise log a warning and continue

Abstract methods subclasses must implement:

- `processStation(StationRef station)` — station-specific processing logic
- `logger()` — returns the subclass logger
- `country()` — returns the country label (e.g. `"US"`)
- `missingSourceDescription()` — describes the missing data source (e.g. `"Open-Meteo source"`)

Private helper:

- `stationLabel()` — returns `country() + " station"`

Current message style (rendered from template methods):

- skip: `Skipping US station with no published Open-Meteo source. station={mli} state={state}`
- failure: `US station processing failed. station={mli} state={state}`

### 6.7 `StationProcessorOpen`

Open-Meteo worker implementation. Extends `StationProcessorBase`.

Template method implementations:

- `country()` → `"US"`
- `missingSourceDescription()` → `"Open-Meteo source"`

Processing flow per station:

1. fetch JSON from Open-Meteo using station latitude and longitude
2. log save start with payload byte count
3. update `dbo.ows_meteo` via repository
4. log station processed

### 6.8 `StationPostProcessingService`

Runs the stored procedures in this exact order:

1. `dbo.spPushSpeciesFromLakeToStation`
2. `dbo.spTotalUpdateProbability`

This ordering matches the legacy weather worker base implementation.

### 6.9 `StationWorker`

This is the main background worker.

Startup rules:

- implement `ApplicationRunner`
- if app starts with `--console`, do not start the background thread
- otherwise start one non-daemon thread named `weather-data-worker-open`

Per-cycle rules:

1. load supported US stations
2. compute target delay using an 8-hour time budget
3. process stations one by one
4. apply the remaining delay after each station so the full pass spreads across the time budget
5. run post-processing procedures
6. sleep until next midnight

Delay calculation:

- if station count <= 1, use `2000 ms`
- otherwise:
  - `delayMs = max(8 hours in ms / stationCount, 2000)`

Sleep rule after full cycle:

- compute time until local next midnight
- if already at or past the boundary, continue immediately

### 6.10 `ConsoleDebugRunner`

Console mode rules:

- activate when `--console` is present
- optional filter: `--station=<MLI>`
- run exactly one worker pass
- process only matching station when `--station` is provided
- log start and finish
- exit process after the one-shot run completes

---

## 7. Data Flow

### 7.1 Station selection

Source:

- view `dbo.vwWeatherForecastToDay`

Selection:

- US only
- maximum 1400 rows

### 7.2 HTTP request

For each station:

1. take `lat` and `lon`
2. build Open-Meteo forecast URL
3. perform HTTP GET
4. read raw JSON response

### 7.3 Database update

For each successful fetch:

1. locate row in `dbo.ows_meteo` by `mli`
2. set:
   - `type = 2`
   - `ows = fetched JSON`
   - `stamp = GETDATE()`

### 7.4 Post-processing

After the full station pass:

1. `dbo.spPushSpeciesFromLakeToStation`
2. `dbo.spTotalUpdateProbability`

---

## 8. Timing Model

The service reproduces the legacy weather pacing logic.

### 8.1 Time budget

- each full worker pass is budgeted for 8 hours

### 8.2 Delay between stations

Example:

- 1400 stations
- 8 hours = 28,800,000 ms
- target delay = `28,800,000 / 1400 = 20,571 ms`

Actual sleep after a station is:

- `targetDelay - actualProcessingTime`
- if negative or zero, do not sleep

### 8.3 Between cycles

After post-processing:

- compute duration until next local midnight
- sleep for that duration
- when the service reaches the next day, start a new full pass

---

## 9. Error Handling

Behavior should match the current project state:

| Scenario | Behavior |
|---|---|
| Missing `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` | Spring datasource initialization fails at startup |
| Blank `mli` during save | throw `IllegalArgumentException` |
| Blank or empty JSON payload | skip save |
| HTTP 404 from Open-Meteo | throw `FileNotFoundException`, log unpublished-source skip, continue |
| HTTP non-200 other than 404 | throw `IOException`, log warning, continue |
| Per-station processing exception | log warning with station and state, continue |
| SQL write failure | Resilience4j retry/circuit breaker applies, then fallback throws runtime exception |
| Post-processing procedure emits result sets | drain result sets and continue normally |
| Worker thread interrupted | re-set interrupt flag and stop worker thread |
| Unexpected worker loop exception | log error and continue loop |

Important:

- do not disable stations automatically
- do not stop the worker for a single station failure
- do not parse JSON in Java

---

## 10. Logging

Logging uses Logback console output.

### 10.1 Log levels

- root: `INFO`
- `com.fishfind.weather`: `INFO`

### 10.2 Important log events

Log at least:

- background worker thread start
- supported station count
- calculated time-budget delay
- fetch success
- save start
- station processed
- post-processing procedure execution
- skip due to unpublished source
- station processing failure
- cycle completion with next run time

### 10.3 Logback file

`logback-spring.xml` should define:

- Spring property-backed log levels
- a single console appender
- a timestamped line format with thread name and logger name

---

## 11. Build and Packaging

### 11.1 Maven coordinates

- `groupId`: `com.fishfind`
- `artifactId`: `weather-station-pusher`
- `version`: `1.0.0`

### 11.2 Required dependencies

- `spring-boot-starter`
- `spring-boot-starter-jdbc`
- `spring-boot-starter-aop`
- `resilience4j-spring-boot3`
- `mssql-jdbc`
- `dotenv-java`
- `slf4j-api`
- `logback-classic`
- `spring-boot-starter-test` for tests when added

### 11.3 Build command

```powershell
mvn -DskipTests package
```

Expected runtime jar:

```text
target/weather-station-pusher-1.0.0.jar
```

---

## 12. Docker

The service may be containerized with a multi-stage build.

### 12.1 Dockerfile behavior

Build stage:

- base image: `maven:3.9.9-eclipse-temurin-21`
- copy `pom.xml` and `src`
- run `mvn -B -DskipTests package`

Runtime stage:

- base image: `eclipse-temurin:21-jre`
- copy built jar to `/app/weather-station-pusher.jar`
- run:

```sh
java $JAVA_OPTS -jar /app/weather-station-pusher.jar
```

### 12.2 `.dockerignore`

Exclude:

- `.git`
- `.idea`
- `target`
- `docs` or `doc` folders if desired
- `.env`

Do not bake a real `.env` into the image.

---

## 13. Recreation Checklist

To recreate the service from zero:

1. Create a Maven Java 21 Spring Boot project.
2. Set coordinates to `com.fishfind:weather-station-pusher:1.0.0`.
3. Add JDBC, AOP, MSSQL, Resilience4j, dotenv, and logging dependencies.
4. Create package `com.fishfind.weather`.
5. Implement dotenv bootstrap in `WeatherStationPusherApplication`.
6. Create `StationRef` record with `mli`, `latitude`, `longitude`, `state`.
7. Implement `WeatherStationRepository` with the `vwWeatherForecastToDay` US query.
8. Implement `OpenMeteoFetcher` using `HttpURLConnection`.
9. Implement `WeatherDataRepository` to update `dbo.ows_meteo` and execute the two procedures.
10. Implement `StationProcessorBase` shared exception handling.
11. Implement `StationProcessorOpen` to fetch and save raw JSON.
12. Implement `StationPostProcessingService` with the exact procedure order.
13. Implement `StationWorker`:
    - background thread named `weather-data-worker-open`
    - 8-hour dynamic delay
    - sleep until next midnight
14. Implement `ConsoleDebugRunner` for `--console` and optional `--station`.
15. Add `application.yml` and `logback-spring.xml`.
16. Add `.env.example`, `.dockerignore`, and `Dockerfile`.
17. Verify with:

```powershell
mvn -DskipTests compile
```

---

## 14. Fidelity Notes

This specification reflects the current recreated Java service, which mirrors the legacy `WeatherDataWorkerOpen` path rather than the broader original .NET service.

That means:

- only the Open-Meteo worker is present
- only US stations are processed
- persistence is an `UPDATE` into existing `ows_meteo` rows
- post-processing order follows the legacy weather worker base implementation
- daily cadence is aligned to midnight, not top-of-hour

If future work restores Weather Underground or Windows Service hosting, this document should be updated rather than treated as a superset of that missing functionality.
