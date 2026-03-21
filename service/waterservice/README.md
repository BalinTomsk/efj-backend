# water-station-pusher

`water-station-pusher` is a Spring Boot 3 background service that:

- reads supported Canadian water stations from SQL Server
- downloads hourly hydrometric CSV files from Environment Canada
- parses the readings
- upserts them into `dbo.WaterData`
- disables a station after repeated fetch failures

This service has no HTTP API. It runs as a worker process.

Deployment runbooks:

- `docs/digitalocean.md` for initial DigitalOcean setup
- `docs/update.md` for publishing a new image version and replacing the running Droplet container

## Requirements

- Java 21
- Maven 3.9+
- Docker Desktop if you want to run it in a container
- Access to a Microsoft SQL Server instance

## Project layout

- `src/main/java/com/fishfind/water/WaterStationPusherApplication.java`
  Entry point. Loads credentials from environment variables or `.env` before Spring starts.
- `src/main/java/com/fishfind/water/service/StationWorker.java`
  Starts the background worker thread in normal mode.
- `src/main/java/com/fishfind/water/service/ConsoleDebugRunner.java`
  Runs exactly one processing pass when `--console` is used.
- `src/main/java/com/fishfind/water/service/StationProcessor.java`
  Fetches, parses, saves, and handles station failure tracking.
- `src/main/java/com/fishfind/water/service/CsvFetcher.java`
  Downloads CSV files from Environment Canada.
- `src/main/java/com/fishfind/water/repo/WaterStationRepository.java`
  Loads supported stations and disables failing stations.
- `src/main/java/com/fishfind/water/repo/WaterDataRepository.java`
  Upserts readings into `dbo.WaterData`.
- `src/main/resources/application.yml`
  Spring datasource, worker timing, and Resilience4j settings.

## Configuration

The application requires these values:

- `DB_URL`
- `DB_USERNAME`
- `DB_PASSWORD`

Example `.env`:

```env
DB_URL=jdbc:sqlserver://host.docker.internal:1433;databaseName=your_database;encrypt=true;trustServerCertificate=true
DB_USERNAME=your_username
DB_PASSWORD=your_password
```

Notes:

- A real `.env` file should live in the project root.
- Do not commit the real `.env`.
- `.env.example` contains placeholders only.
- If the process environment already defines `DB_URL`, `DB_USERNAME`, or `DB_PASSWORD`, those values win.
- If environment variables are missing, the app tries to load `.env` from the current working directory.
- You can override the dotenv file location with `DOTENV_PATH`.

Example:

```powershell
$env:DOTENV_PATH = "C:\secrets\waterservice.env"
```

## Runtime modes

The service supports two modes.

### Normal worker mode

This is the default. The application starts Spring and then launches a non-daemon worker thread named `water-station-worker`.

Worker behavior:

- loads all supported Canadian stations from `WaterStation`
- processes them one by one
- sleeps between stations
- after a full cycle, waits until the next top-of-hour before starting again
- keeps running until the process is stopped

### Console mode

Use `--console` to run exactly one pass and then exit.

Optional:

- `--station=<MLI>` to process only one station

Examples:

```powershell
mvn spring-boot:run "-Dspring-boot.run.arguments=--console"
```

```powershell
mvn spring-boot:run "-Dspring-boot.run.arguments=--console --station=02JE025"
```

Console mode is the easiest way to debug one station without waiting for the full worker loop.

## Worker settings

Defined in `src/main/resources/application.yml`:

- `water.worker.pause-between-stations-ms=1500`
- `water.worker.connect-timeout-ms=15000`
- `water.worker.read-timeout-ms=30000`

You can override them at runtime with JVM system properties or environment variables recognized by Spring Boot.

PowerShell example:

```powershell
mvn spring-boot:run "-Dspring-boot.run.jvmArguments=-Dwater.worker.pause-between-stations-ms=100"
```

## Build without Docker

Build the jar:

```powershell
mvn clean package
```

Expected output:

- `target/water-station-pusher-1.0.0.jar`

Run the packaged jar:

```powershell
java -jar target\water-station-pusher-1.0.0.jar
```

Run the packaged jar in console mode:

```powershell
java -jar target\water-station-pusher-1.0.0.jar --console
```

Run one station only:

```powershell
java -jar target\water-station-pusher-1.0.0.jar --console --station=02JE025
```

## Run without Docker

### Option 1: use a root `.env` file

1. Create `.env` in the project root.
2. Put `DB_URL`, `DB_USERNAME`, and `DB_PASSWORD` into it.
3. Start the app.

Examples:

```powershell
mvn spring-boot:run
```

```powershell
java -jar target\water-station-pusher-1.0.0.jar
```

### Option 2: use process environment variables

PowerShell:

```powershell
$env:DB_URL = "jdbc:sqlserver://localhost:1433;databaseName=your_database;encrypt=true;trustServerCertificate=true"
$env:DB_USERNAME = "your_username"
$env:DB_PASSWORD = "your_password"
mvn spring-boot:run
```

### Option 3: use a custom dotenv file

PowerShell:

```powershell
$env:DOTENV_PATH = "C:\secrets\waterservice.env"
mvn spring-boot:run
```

## Debug without Docker

There are two practical ways to debug locally: IDE debugging and JVM remote debugging.

### IntelliJ IDEA local debug

1. Open the `waterservice` project.
2. Ensure Java 21 SDK is selected.
3. Set environment variables in the run configuration, or keep a valid `.env` in the project root.
4. Create an Application run/debug configuration:
   - Main class: `com.fishfind.water.WaterStationPusherApplication`
   - Working directory: project root
   - JRE: Java 21
5. For one-shot debugging, add program arguments:
   - `--console`
   - optionally `--station=02JE025`
6. Place breakpoints where needed.
7. Start Debug.

Recommended first breakpoint locations:

- `WaterStationPusherApplication.main`
- `ConsoleDebugRunner.run`
- `StationWorker.runOnce`
- `StationProcessor.process`
- `CsvFetcher.fetch`
- `WaterDataRepository.saveStationData`

Why `--console` is useful:

- it avoids the infinite worker loop
- it runs a single pass
- it exits cleanly after the station run
- it makes repeatable debugging much easier

### Maven debug from the command line

Start the app with JDWP enabled:

```powershell
mvn spring-boot:run "-Dspring-boot.run.jvmArguments=-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=*:5005" "-Dspring-boot.run.arguments=--console --station=02JE025"
```

What this does:

- opens a debug socket on port `5005`
- suspends before application code runs
- waits for your debugger to attach

Then attach IntelliJ using a Remote JVM Debug configuration:

- Host: `localhost`
- Port: `5005`

### Debug the packaged jar locally

Build first:

```powershell
mvn clean package
```

Run with remote debug enabled:

```powershell
java "-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=*:5005" -jar target\water-station-pusher-1.0.0.jar --console --station=02JE025
```

Then attach your IDE to `localhost:5005`.

## Expected logging

The service logs to standard output.

Typical events:

- worker thread start
- supported station count
- station processing progress
- CSV fetch success
- save start and save finish
- failure counts
- station disable after 3 failures in one day

If you want more detail during debugging, you can temporarily override logging:

```powershell
mvn spring-boot:run "-Dspring-boot.run.jvmArguments=-Dlogging.level.com.fishfind.water=DEBUG"
```

## Build Docker image

From the project root:

```powershell
docker build -t water-station-pusher:1.0.1 .
```

This uses the multi-stage `Dockerfile`:

- stage 1 builds the jar with Maven
- stage 2 runs the jar on Eclipse Temurin JRE 21

## Save Docker image

Save the built image to a tar archive:

```powershell
docker save -o water-station-pusher-1.0.1.tar water-station-pusher:1.0.1
```

Load it later on the same or another machine:

```powershell
docker load -i water-station-pusher-1.0.1.tar
```

## Run in Docker

This service does not expose an application port. The important runtime dependency is database connectivity.

### Option 1: run with `--env-file`

Create `.env` in the project root, then run:

```powershell
docker run --name water-station-pusher --env-file .env water-station-pusher:1.0.1
```

### Option 2: pass environment variables directly

```powershell
docker run --name water-station-pusher `
  -e DB_URL="jdbc:sqlserver://host.docker.internal:1433;databaseName=your_database;encrypt=true;trustServerCertificate=true" `
  -e DB_USERNAME="your_username" `
  -e DB_PASSWORD="your_password" `
  water-station-pusher:1.0.0
```

### Option 3: mount a custom dotenv file and point `DOTENV_PATH` at it

```powershell
docker run --name water-station-pusher `
  -v "C:\secrets\waterservice.env:/run/secrets/waterservice.env:ro" `
  -e DOTENV_PATH="/run/secrets/waterservice.env" `
  water-station-pusher:1.0.0
```

Use this only if you intentionally want the application to read dotenv inside the container. In most deployments, plain environment variables are simpler.

## Debug in Docker

The cleanest approach is to enable JDWP through `JAVA_OPTS` and publish the debug port to the host.

### Debug the normal worker in Docker

```powershell
docker run --name water-station-pusher-debug `
  -e DB_URL="jdbc:sqlserver://host.docker.internal:1433;databaseName=your_database;encrypt=true;trustServerCertificate=true" `
  -e DB_USERNAME="your_username" `
  -e DB_PASSWORD="your_password" `
  -e JAVA_OPTS="-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=*:5005" `
  -p 5005:5005 `
  water-station-pusher:1.0.0
```

Attach your IDE to:

- Host: `localhost`
- Port: `5005`

### Debug one station in Docker

Override the container command and add console arguments:

```powershell
docker run --name water-station-pusher-console-debug `
  -e DB_URL="jdbc:sqlserver://host.docker.internal:1433;databaseName=your_database;encrypt=true;trustServerCertificate=true" `
  -e DB_USERNAME="your_username" `
  -e DB_PASSWORD="your_password" `
  -p 5005:5005 `
  water-station-pusher:1.0.1 `
  sh -c "java -agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=*:5005 -jar /app/water-station-pusher.jar --console --station=02JE025"
```

Use this mode when you want:

- deterministic one-pass execution
- a faster debugging loop
- easier breakpoint management

### Notes about container debugging

- `suspend=y` makes the JVM wait for your debugger before running application code.
- `-p 5005:5005` is required so your IDE can reach the JVM inside the container.
- `host.docker.internal` usually works on Docker Desktop for Windows and macOS to reach a database running on the host machine.
- If SQL Server runs elsewhere, replace the hostname in `DB_URL`.

## Docker lifecycle commands

View logs:

```powershell
docker logs -f water-station-pusher
```

View logs for the debug container:

```powershell
docker logs -f water-station-pusher-debug
```

Stop a container:

```powershell
docker stop water-station-pusher
```

Remove a container:

```powershell
docker rm water-station-pusher
```

List local images:

```powershell
docker images
```

## Troubleshooting

### The app fails on startup with datasource placeholder errors

Cause:

- `DB_URL`, `DB_USERNAME`, or `DB_PASSWORD` was not available to Spring

Check:

- your `.env` exists in the project root, or
- your environment variables are set in the same shell session, or
- `DOTENV_PATH` points to a real file

### The container starts but cannot connect to SQL Server

Check:

- the hostname in `DB_URL`
- firewall rules
- SQL Server port availability
- whether `host.docker.internal` is valid for your Docker environment

### Breakpoints are not hit in container debug

Check:

- the container was started with `-p 5005:5005`
- `JAVA_OPTS` or the overridden `java` command includes the JDWP agent
- your IDE remote debug config is attached to `localhost:5005`
- `suspend=y` is present if you need to catch startup logic

### The worker never exits

This is expected in normal mode. Use `--console` for a one-shot run during debugging.

## Recommended debug workflow

For most development tasks:

1. Put valid credentials in root `.env`.
2. Run with `--console --station=<MLI>`.
3. Place breakpoints in `StationProcessor.process`, `CsvFetcher.fetch`, and `WaterDataRepository.saveStationData`.
4. Once the station flow works, run normal worker mode.

This is the fastest loop for verifying fetch, parse, and save behavior.
