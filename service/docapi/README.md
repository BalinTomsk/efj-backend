# docapi

`docapi` is a Spring Boot 3 REST service that manages **JSON documents** for four entities:

- **news** — news articles
- **waterbody** — water bodies (the legacy `dbo.lake` entity)
- **fish** — fish species
- **station** — water stations

Each entity has its own controller exposing three operations:

| Verb | Path | Purpose |
|------|------|---------|
| `GET`  | `/api/v1/<entity>/{id}` | return the stored JSON document |
| `POST` | `/api/v1/<entity>`      | add a new document (JSON body) |
| `PUT`  | `/api/v1/<entity>/{id}` | update an existing document (JSON body) |

`<entity>` is one of `news`, `waterbody`, `fish`, `station`.

Every response uses the platform envelope `{ data, error, meta }`.

**Runs with no database by default.** Out of the box DocApi uses an in-memory document store, so it
starts and serves all endpoints without any DB connection or configuration — ideal for the initial
working service and for local development. The SQL Server backing (each entity's own JSON **function**
for reads and stored **procedures** for writes) is wired only under the `jdbc` Spring profile once the
DB objects exist (see [Storage backends](#storage-backends) and [Database contract](#database-contract)).

This service follows the same conventions as the sibling `waterservice` (dotenv-backed local
credentials, JDBC to legacy DB objects, Resilience4j around SQL, private Actuator management port,
JSON logging, digest-pinned multi-stage Docker image).

## Requirements

- Java 21
- Maven 3.9+
- Docker Desktop (optional, to run in a container)
- Access to a Microsoft SQL Server instance

## Project layout

```
src/main/java/com/fishfind/docapi/
├── DocApiApplication.java              # entry point
├── config/DotenvEnvironmentPostProcessor.java
├── config/InMemoryStoreConfig.java     # default: in-memory stores (no DB)
├── config/JdbcStoreConfig.java         # `jdbc` profile: SQL-backed stores
├── domain/DocumentType.java            # NEWS / WATERBODY / FISH / STATION
├── repo/
│   ├── DocumentStore.java              # storage interface (get / add / update)
│   ├── InMemoryDocumentStore.java      # default backing, process-local, no DB
│   ├── JdbcDocumentRepository.java     # abstract SQL backing (jdbc profile)
│   ├── NewsDocumentRepository.java
│   ├── WaterbodyDocumentRepository.java
│   ├── FishDocumentRepository.java
│   └── StationDocumentRepository.java
├── service/
│   ├── DocumentService.java            # abstract: validation + not-found handling
│   ├── NewsDocumentService.java …      # one per entity
│   ├── DocumentNotFoundException.java  # → 404
│   └── InvalidDocumentException.java   # → 400
└── web/
    ├── AbstractDocumentController.java # GET/POST/PUT shared surface
    ├── NewsController.java …           # one per entity, sets base path
    ├── HealthController.java           # GET /health → { status, version, uptime }
    ├── ApiResponse.java                # { data, error, meta } envelope
    └── ApiExceptionHandler.java        # maps exceptions to the envelope
```

## Storage backends

| Profile | Backing | DB needed? |
|---------|---------|------------|
| _default_ (no profile) | `InMemoryDocumentStore` — process-local, lost on restart | **No** |
| `jdbc` | `JdbcDocumentRepository` per entity → stored procs / JSON function | Yes |

Both backends implement `DocumentStore` and are registered under the same bean names
(`newsStore`, `waterbodyStore`, `fishStore`, `stationStore`), so the service layer is identical
regardless of which is active. Under the default profile, JDBC/datasource auto-configuration is
excluded so the app never tries to reach a database. Switch to SQL Server with:

```bash
java -jar target/docapi-1.0.0.jar --spring.profiles.active=jdbc   # requires DB_URL/USERNAME/PASSWORD + DB objects
```

## Configuration

With the default in-memory backing **no configuration is required** — just build and run.

The `jdbc` profile requires:

- `DB_URL`
- `DB_USERNAME`
- `DB_PASSWORD`

Example `.env` (project root, do **not** commit — `.env.example` holds placeholders only):

```env
DB_URL=jdbc:sqlserver://host.docker.internal:1433;databaseName=your_database;encrypt=true;trustServerCertificate=true
DB_USERNAME=your_username
DB_PASSWORD=your_password
```

- Real process environment variables / JVM system properties always win over `.env`.
- Override the dotenv file location with `DOTENV_PATH`.

## Build & run

```powershell
mvn clean package
java -jar target\docapi-1.0.0.jar
```

The service listens on **8080** (application + `/health`); Actuator lives on the private management
port **8081** and must never be exposed publicly.

Quick smoke test once running (default in-memory backing — no DB needed):

```bash
curl http://localhost:8080/health
# -> {"status":"UP","version":"1.0.0","uptime":...}

ID=$(curl -s -X POST http://localhost:8080/api/v1/news \
       -H 'Content-Type: application/json' -d '{"title":"Spring opener"}' \
     | sed -E 's/.*"id":"([^"]+)".*/\1/')          # e.g. news-1
curl http://localhost:8080/api/v1/news/$ID
curl -X PUT http://localhost:8080/api/v1/news/$ID -H 'Content-Type: application/json' -d '{"title":"Edited"}'
```

### Response shape

Success:

```json
{ "data": { "title": "Spring opener" }, "error": null, "meta": { "timestamp": "2026-07-27T…" } }
```

Error (e.g. unknown id):

```json
{ "data": null, "error": { "code": "not_found", "message": "No news document found for id '999'" }, "meta": { "timestamp": "…" } }
```

## Database contract

> Only used under the **`jdbc` profile**. The default in-memory backing needs none of this.
> **These SQL objects are not created yet.** Each entity is wired to its own objects; create them in
> `envfish-db` (test-first, per that repo's workflow) before running with `--spring.profiles.active=jdbc`.

For each `<entity>` in `news`, `waterbody`, `fish`, `station`:

| Operation | SQL invoked | Expected behaviour |
|-----------|-------------|--------------------|
| return | `SELECT dbo.fn_<entity>_doc(@id)` | returns the document as a JSON string; `NULL` ⇒ HTTP 404 |
| add    | `EXEC dbo.sp_<entity>_doc_add @json` | inserts, returns the new id as a single scalar |
| update | `EXEC dbo.sp_<entity>_doc_update @id, @json` | updates, returns the affected id as a single scalar |

Notes:

- The id is passed as a string and converted by SQL Server to the column's real key type (`int` or
  `uniqueidentifier`), so DocApi stays agnostic to per-entity key types.
- `waterbody` maps to the `dbo.lake` table.
- The `fish` objects (`fn_fish_doc` / `sp_fish_doc_*`) are distinct from the existing
  `dbo.fn_fish_document` / `dbo.sp_add_fish_document`, which manage a PDF blob, not the species JSON.

## Docker

```powershell
docker build -t docapi:1.0.0 .
docker run --name docapi --env-file .env -p 8080:8080 docapi:1.0.0
```

The image is a multi-stage build (Maven → Temurin JRE 21), runs as a non-root user, and its
HEALTHCHECK hits `/health`.

## Tests

```powershell
mvn test
```

No DB is required: repository tests mock `JdbcTemplate`, the web slice mocks the service layer, and
the context test boots against an in-memory H2 datasource.
