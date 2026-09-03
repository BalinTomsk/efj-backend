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

- `DB_URL` (SQL Server — waterbody, fish, station entities + news writes)
- `DB_USERNAME`
- `DB_PASSWORD`
- `MYSQL_NEWS_URL` (MySQL — news **reads** only: `GET /{id}`, `/news/list`, `/news/default`; as of 2026-08-31)
- `MYSQL_NEWS_USERNAME`
- `MYSQL_NEWS_PASSWORD`

Example `.env` (project root, do **not** commit — `.env.example` holds placeholders only):

```env
DB_URL=jdbc:sqlserver://host.docker.internal:1433;databaseName=your_database;encrypt=true;trustServerCertificate=true
DB_USERNAME=your_username
DB_PASSWORD=your_password

MYSQL_NEWS_URL=jdbc:mysql://my06.winhost.com:3306/mysql_111487_envfish
MYSQL_NEWS_USERNAME=your_mysql_user
MYSQL_NEWS_PASSWORD=your_mysql_password
```

**Why separate MySQL for news?** The `news` table migrated to Winhost MySQL on 2026-08-31 to match the `fishfind-frontend`'s `News.aspx` data source. The three news read endpoints now read from MySQL; everything else on `NewsController` (POST/PUT/{id}, `/search`, `/export`, `/import`) and all other entities (waterbody, fish, station) remain on SQL Server.

- Real process environment variables / JVM system properties always win over `.env`.
- Override the dotenv file location with `DOTENV_PATH`.
- **MySQL is optional**: if you run without MySQL config, the `jdbc` profile still starts (SQL Server only), news reads return empty/404, and writes + all other entities work normally. This is useful for local dev when you don't have MySQL access.

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
`GET /api/v1/news/default` (latest-news list + assembled home page — one call carries every field the
portal's `Default.aspx` renders for its 2 lead articles and 3 "More News" items, including each
article's `snippet` and its `lake_name` / `fishes:[{id,name,latin}]` tag row), its two halves
`GET /api/v1/news/featured` (the 2 leads with their photos, ~1.09 MB) and `GET /api/v1/news/more`
(the sidebar column, ~1.6 KB — fetch this instead of the whole page when you only need the list),
`GET /api/v1/news/search?q=`
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

The River entity adds five lookups and three writes. `GET /api/v1/river/unfished?country=&state=&river=` — the next
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

`PATCH /api/v1/river/fish/{guid}` — the write counterpart, a native duplicate of the "Add" form on that
same `EditLakeFish.aspx` page. Body is a JSON array of `{fishId, link, trustLevel, year, status}`
entries (`fishId` required, the rest optional), upserted in one batch by
`dbo.sp_lake_fish_upsert_batch`. **Deliberately narrow:** a species not yet assigned to the lake is
`inserted`; one already assigned but missing its `link` is `updated`; one already assigned **with** a
link is left alone (`skipped`) — this endpoint can never silently overwrite already-sourced data.
`unknown_fish` / `invalid_fish_id` cover an unrecognized guid and a non-guid. Empty/non-array/
over-500-entry body ⇒ 400; unknown lake guid ⇒ 404. This service's first write outside the generic
document CRUD endpoints — see the Database contract section below for the SQL. **Fronted through
cproxy as of 0.6.1** (`deploy/compose.yml`, `CPROXY_ALLOWED_METHODS` now includes `PATCH`), gated by
a per-day rotating credential (`X-Day-Guid` checked against a SQLite `DayKeyStore`), not a static API
key — see `efc-proxy` `CLAUDE.md` → "Day-key store".

`PATCH /api/v1/river/description/{guid}` — a second, independent write: a JSON **merge patch** (only
keys present in the body are touched) of the `Editor/LakeEditor.aspx` "General" tab's editable
fields, via the new `dbo.sp_lake_description_update`. Covers every field
`fn_lake_description_json` exports — name variants, `link`, `type`, the size/measurement fields,
`cgndb`, `roadAccess`, `fishingProhibited`, `isolated`, `noFish`, `reviewed`, `description` —
**except** the identity/linkage fields the same admin page shows read-only in this exact spot:
`lakeName`, `source`/`sourceId`, `mouth`/`mouthId`. Those are reported back as `protectedFields`
rather than silently dropped or applied. `noFish` is blocked (reported `ignored`) while the lake has
assigned species, mirroring the page's own client-side rule. Empty/non-object/over-100-key body ⇒
400; unknown lake guid ⇒ 404. Response: `{lakeId, updated:[{field}], ignored:[{field,reason}],
protectedFields:[{field,reason}]}`. Fronted through cproxy automatically — the day-key gate applies
to every PATCH, not a specific path.

`GET /api/v1/river/source/{guid}` / `GET /api/v1/river/mouth/{guid}` — the Source/Mouth-tab documents
for one water body: `{guid, lakeName, sources|mouths:[{id, pointId, pointName, lat, lon, elevation,
country, state, county, city, district, municipality, region, zone, coast, location, description,
stamp}]}` (normally one element per side — `UK_Tributaries_Source`/`UK_Tributaries_Mouth` allow at
most one `side=16`/`side=32` row per water body). Native duplicates of the admin "Save JSON"
Source/Mouth-tab export (`Editor/EditLakeLink.aspx?Type=16|32` →
`HandlerImage.ashx?lakejson=<guid>&tab=source|mouth`), backed by `dbo.fn_lake_source_json` /
`dbo.fn_lake_mouth_json` — already live in prod (2026-08-13 rollout), no new DB object for the read
side. Unknown guid ⇒ 404.

`PATCH /api/v1/river/source/{guid}` / `PATCH /api/v1/river/mouth/{guid}` — the write counterparts: a
JSON **merge patch** of that tab's editable fields on `Editor/EditLakeLink.aspx`
(`ButtonSubmit_Click`) — `lat`, `lon`, `elevation`, `country`, `state`, `county`, `city`, `district`,
`municipality`, `region`, `zone`, `coast`, `location`, `description` — via the new
`dbo.sp_lake_source_update` / `dbo.sp_lake_mouth_update`. **Deliberately excludes** every
identity/linkage field that same admin page shows read-only in this exact spot — the water body's own
`lakeName`/`guid`, and the linked point's `pointName`/`pointId` (plus the row's internal `id`/`stamp`,
neither a user-editable field) — reported back as `protectedFields`, same contract as `description`.
Empty/non-object/over-100-key body ⇒ 400; unknown lake guid ⇒ 404. Fronted through cproxy
automatically — same day-key gate, no cproxy change needed. **Not yet deployed to prod** (1.7.0).

The Regulation entity exposes two of the three scopes `Editor/LakeRegulation.aspx`'s single
"regulation dialog" edits through one `dbo.regulations` table (zone-scoped rules have no dedicated
endpoint yet): water-body rules and region (country/state) rules.

`GET /api/v1/river/regulation/{guid}` — this water body's OWN regulation rows (never the region/zone
rules that also apply to it), via `dbo.fn_lake_regulation_json`. Unknown guid ⇒ 404.

`GET /api/v1/region/regulation/{country}` — whole-country rules (no specific state); `GET
/api/v1/region/regulation/{country}/{state}` — province/state-wide rules. These are two *different*,
non-overlapping row sets, not a country roll-up of every province's rules. Both via
`dbo.fn_region_regulation_json`; an unrecognized `country`/`state` returns an empty `regulations`
array rather than 404 (there's no single "country" row to be missing). A non-two-letter `country`/
`state` ⇒ 400.

`PATCH` on all three routes upserts one row of `dbo.regulations` via `dbo.sp_regulation_upsert` —
**there is no separate INSERT verb.** The identity (`country`/`state`/`zoneId`/`lakeId`/`fishId`/
`year`/`part`/`residentType` — the columns behind the table's two filtered unique indexes) decides
insert vs. update: a body matching nothing existing inserts (`action:"inserted"`), one matching an
existing row updates it in place (`action:"updated"`). A dedicated `POST` was deliberately skipped —
cproxy's write surface only admits `GET`/`PATCH` (the day-key gate is verb-based, not path-based), so
reusing the fish/description endpoints' upsert-on-PATCH pattern ships this with **no cproxy change**.
`lakeId` (water-body route) or `country`/`state` (region routes) are always taken from the URL, never
the body — a caller can't accidentally write to a different scope than the one they PATCHed. Response:
`{id, action, scope}` on success, or `{id:null, action:null, error}` when the body fails validation
(missing `year`, an unknown `lakeId`/`fishId`, or `zoneId`+`lakeId` both set) — the same
graceful-error-in-a-200 contract as `sp_lake_description_update`'s malformed-JSON path, not a 4xx.
Note: `dbo.TR_regulations` auto-adds the row to `lake_fish` when a new water-body rule also carries a
`fishId` not yet assigned to that lake — the same side effect the ASPX page's own INSERT triggers.

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
  **river fish read** (`GET /api/v1/river/fish/{guid}`) → `dbo.fn_lake_fishing_json(@lake)` — both
  pre-existing per-tab admin "Save JSON" export functions from the 2026-08-13 `envfish-db` rollout;
  docapi is the only new code for either endpoint.
- **River source/mouth read** (`GET /api/v1/river/source/{guid}` / `GET /api/v1/river/mouth/{guid}`) →
  `dbo.fn_lake_source_json(@lake)` / `dbo.fn_lake_mouth_json(@lake)` — same 2026-08-13 rollout as the
  functions above, no new DB object for the read side.
- **River fish write** (`PATCH /api/v1/river/fish/{guid}`) → `EXEC dbo.sp_lake_fish_upsert_batch @lake,
  @fish` (new proc, `envfish-db` 2026-08-25, `unit_test@LakeFishUpsertBatch.sql`), and **river
  description write** (`PATCH /api/v1/river/description/{guid}`) →
  `EXEC dbo.sp_lake_description_update @lake, @patch` (new proc, `envfish-db` 2026-08-25,
  `unit_test@LakeDescriptionUpdate.sql`) — the two write procedures this service calls outside the
  generic `sp_<entity>_doc_add`/`_update` pair above. Both invoked via `jdbc.execute` with a manual
  result-set drain (see `JdbcDocumentRepository.executeReturningScalar` /
  `JdbcNewsQueryRepository.importNews`), not `jdbc.query`, for the same reason those calls do: a
  proc's DML can interleave update counts with its final `SELECT`.
- **River source/mouth write** (`PATCH /api/v1/river/source/{guid}` / `PATCH /api/v1/river/mouth/{guid}`)
  → `EXEC dbo.sp_lake_source_update @lake, @patch` / `EXEC dbo.sp_lake_mouth_update @lake, @patch` (new
  procs, `envfish-db` 2026-08-26, `unit_test@LakeJson.sql` TEST 15–18), same `jdbc.execute` drain
  pattern, one shared `RiverLinkCommandRepository` bean for both. **Not yet applied to the production
  database** — see the docapi CHANGELOG 2026-08-26 entry.
- **River regulation read** (`GET /api/v1/river/regulation/{guid}`) → `dbo.fn_lake_regulation_json(@lake)`
  (pre-existing per-tab admin "Save JSON" export function, 2026-08-13 rollout — extended 2026-08-25 to
  also emit the new `country` field, `unit_test@RegulationRead.sql`), and **region regulation read**
  (`GET /api/v1/region/regulation/{country}[/{state}]`) → `dbo.fn_region_regulation_json(@country,
  @state)` (new function, `envfish-db` 2026-08-25, same test file).
- **Regulation write** (`PATCH` on all three regulation routes) → `EXEC dbo.sp_regulation_upsert @body`
  (new proc, `envfish-db` 2026-08-25, `unit_test@RegulationUpsert.sql`, same `jdbc.execute` drain
  pattern). Required a schema change on `dbo.regulations` — added `country char(2) NOT NULL DEFAULT
  'CA'` and relaxed `state` to nullable (a whole-country rule has no state), with `country` folded
  into both filtered unique indexes so two countries can each have their own whole-country rule for
  the same year without colliding — see the "PRODUCTION MIGRATION — regulations: add `country`…" block
  in `envfish-db/mssql/script01_createTable.sql`.

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
