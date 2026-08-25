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
│   ├── StationDocumentRepository.java
│   ├── NewsQueryRepository.java        # interface for news-page queries (list + default)
│   ├── InMemoryNewsQueryRepository.java
│   └── JdbcNewsQueryRepository.java
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
port **8082** and must never be exposed publicly.

Quick smoke test once running (default in-memory backing — no DB needed):

```bash
curl http://localhost:8080/health
# -> {"status":"UP","version":"1.0.0","uptime":...}

ID=$(curl -s -X POST http://localhost:8080/api/v1/news \
       -H 'Content-Type: application/json' -d '{"title":"Spring opener"}' \
     | sed -E 's/.*"id":"([^"]+)".*/\1/')          # e.g. news-1
curl http://localhost:8080/api/v1/news/$ID
curl -X PUT http://localhost:8080/api/v1/news/$ID -H 'Content-Type: application/json' -d '{"title":"Edited"}'

# Interchange export/import (fn_news_json format — the full self-contained document with base64 photos)
curl http://localhost:8080/api/v1/news/export/$ID
curl -X POST http://localhost:8080/api/v1/news/import \
     -H 'Content-Type: application/json' -d '{"title":"Imported","author":"Jane Roe"}'
```

The News page adds extra endpoints on top of the generic CRUD: `GET /api/v1/news/list` and
`GET /api/v1/news/default` (latest-news list + assembled home page), `GET /api/v1/news/search?q=`
(up to 100 published matches across headline/source/paragraphs/photo-alts **and the mentioned fishes'
names**, newest first — `dbo.fn_news_search`; blank `q` ⇒ 400), and the interchange
`GET /api/v1/news/export/{id}` + `POST /api/v1/news/import`. **Only export/import carry the full
document** (every field + the 3 paragraph photos embedded as base64, the same `fn_news_json` format the
portal's News.aspx "Save JSON" / AddNews "Import from JSON" round-trip use); the other endpoints keep
their existing lighter shapes.

The Fish entity adds one search endpoint: `GET /api/v1/fish/search?q=` — a relevance-ranked species
search over the primary name, Latin name, and alternative/common names (so "rosefish" or "ling"
resolves to the right species), best match first. It reuses the **same** lookup the Editor
`FishList.aspx` search box uses (`dbo.SearchFishList`), so no new DB object is needed. Each hit is
`{ fishId, name, latin, rank }` (`rank` — lower is better, 0 = exact); blank/missing `q` ⇒ 400.

The River entity adds three lookups. `GET /api/v1/river/unfished?country=&state=&river=` — the next
un-processed water body of a type in a state (no fish assigned, not flagged No Fish). It is a native
duplicate of the frontend `Resources/wbUnFish.aspx` endpoint used by the add-fish tooling, backed by
`dbo.fn_river_unfished_json`. Returns `{ found, country, state, river, lake_id, lake_name, mouth_name,
CGNDB, throwing }` (fields null when `found:false`); `country` is echoed only (the query filters by
state), and a bad `country`/`state` falls back to the default (CA/ON), a bad `river` to `2` — mirroring
the page (no 400s).

`GET /api/v1/river/description/{guid}` — the full description document for one water body (name/alt
names, description text, physical stats, source/mouth detail, assigned fish, photo gallery as base64).
A native duplicate of the admin "Save JSON" View-tab export
(`Editor/HandlerImage.ashx?lakejson=<guid>&tab=view`), backed by `dbo.fn_lake_view_json` — already live
in prod, no new DB object. Unknown guid ⇒ 404.

`GET /api/v1/river/fish/{guid}` — the assigned-species document for one water body (every `lake_fish`
row: name, latin, conservation status, last-catch, external link). A native duplicate of the admin
"Save JSON" Fishing-tab export (`Editor/EditLakeFish.aspx` → `HandlerImage.ashx?lakejson=<guid>&tab=
fishing`), backed by `dbo.fn_lake_fishing_json` — already live in prod (same 2026-08-13 rollout as
`fn_lake_view_json`), no new DB object. Unknown guid ⇒ 404.

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
- **News interchange** (`/export`, `/import`) uses its own objects, both in `envfish-db`:
  `dbo.fn_news_json(@id)` (already deployed) for export and `dbo.sp_news_import(@json)` (added
  test-first — `unit_test@NewsImport.sql`) for import. These carry the **full** article (all fields +
  base64 photos); the `fn_<entity>_doc` document reads above keep their existing lighter shapes.
- **News search** (`/api/v1/news/search`) → `dbo.fn_news_search(@q)`; **fish search**
  (`/api/v1/fish/search`) → `dbo.SearchFishList(@q)` (a `varchar(64)` TVF returning
  `num, fish_name, name, fish_latin, fish_id, irank`, ranked best-first — already in prod, backs
  `FishList.aspx`).
- **River unfished** (`/api/v1/river/unfished`) → `dbo.fn_river_unfished_json(@country, @state, @river)`
  (returns the whole JSON object — the `vw_lake` TOP-1 lookup + `Tributaries side=2` throwing list;
  added in `envfish-db` with `unit_test@RiverUnfished.sql`).
- **River description** (`/api/v1/river/description/{guid}`) → `dbo.fn_lake_view_json(@lake)`, and
  **river fish** (`/api/v1/river/fish/{guid}`) → `dbo.fn_lake_fishing_json(@lake)` — both pre-existing
  per-tab admin "Save JSON" export functions from the 2026-08-13 `envfish-db` rollout; docapi is the
  only new code for either endpoint.

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
