# docapi — Claude Context

> This file captures the specification and architectural rules needed to recreate, extend, or debug
> the `docapi` Spring Boot service.
> Source of truth: `efj-backend/service/docapi/docs/specification.md`.

---

## What this service is

`docapi` is a REST service that manages **JSON documents** for four entities — **news**,
**waterbody**, **fish**, **station**. Each entity has a controller with three operations:

- `GET  /api/v1/<entity>/{id}` — return the stored JSON document
- `POST /api/v1/<entity>`      — add a new document
- `PUT  /api/v1/<entity>/{id}` — update an existing document

It was scaffolded to mirror the sibling `waterservice` (same Spring Boot version, dotenv credential
loading, JDBC-to-stored-procedures data access, Resilience4j, private Actuator port, JSON logging,
digest-pinned Docker). Unlike `waterservice` (a background worker), `docapi` is a synchronous HTTP
API: **no scheduler, no worker threads, no upstream feed fetching.**

**Runs with no database by default.** The `DocumentStore` interface has two implementations:
`InMemoryDocumentStore` (default — process-local, no DB) and `JdbcDocumentRepository` (SQL Server,
active only under the `jdbc` Spring profile). The default profile **excludes** the JDBC/datasource
auto-configuration, so the service starts and serves every endpoint with zero DB config. Verified
live: POST/GET/PUT round-trip works in-memory and the startup log shows no Hikari/datasource activity.

---

## Keeping docs in sync — IMPORTANT

`docs/specification.md` is the single source of truth for recreating this service from scratch.
Treat every code change as two steps: ① change the code, ② update `docs/specification.md` (and this
file, when behaviour/structure/config changes). Never leave the spec describing behaviour that no
longer exists or omitting behaviour that was added.

**`docs/api-reference.html`** is a standalone, self-contained (no CDN/external assets) human-readable
reference for **every controller in this service** — `HealthController`, `NewsController`,
`FishController`, `RiverController`, `WaterbodyController`, `StationController` — with real
request/response examples captured live against the deployed service. It is a full document (`<!DOCTYPE html>` … `</html>`), not
an Artifact-style fragment; open it directly in a browser to review, no build step.

**Any interface change in any controller must update this file too, in the same change as the spec**:

- A new endpoint → a new "specimen tag" section (same pattern as the existing ones — method badge,
  path, param table, notes list, examples).
- A changed parameter, response shape, status code, or matching/parsing rule on an existing endpoint →
  edit that endpoint's section and its examples.
- An endpoint that no longer exists → remove its section.
- A `waterbody`/`fish`/`station` CRUD entity going from "SQL objects not created" (500) to real (200/
  404) → update that entity's status in the overview status strip, the `#waterbody`/`#station` section
  text, and the quick-reference table's expected status for it.
- A new controller entirely → add it to the sticky controller nav at the top, the status strip, and
  give it its own `<section>` in the same style.

Prefer editing examples in place over appending new ones — the point is that the file always reflects
current behaviour, not a change history. Re-verify an example against the running service (or at least
re-derive it from the code) rather than hand-editing JSON by guess.

---

## Git & DB rules

- **DO NOT COMMIT / PUSH / open-merge-close PRs without explicit user permission.** Make edits and
  stop with a status summary unless Git actions are explicitly requested.
- **Before any database change**, read `c:\envoinx\fishfind\envfish-db\CLAUDE.md` first — it is the
  authoritative DB workflow (edit `scriptNN_*.sql`, never the generated `ffi2.sql`; test-first: a
  FAILING unit test to confirm, then a PASSING one to verify; run `mssql\UNIT_TESTS\autorun.bat`).

---

## Project identity

| Key | Value |
|-----|-------|
| Service name | `docapi` |
| Language | Java 21 |
| Build | Maven |
| Framework | Spring Boot 3.3.x |
| Main class | `com.fishfind.docapi.DocApiApplication` |
| Artifact | `docapi-1.0.0.jar` |

---

## Package layout

```
com.fishfind.docapi
├── DocApiApplication              # @SpringBootApplication entry point
├── config
│   ├── DotenvEnvironmentPostProcessor   # local .env → low-precedence property source
│   ├── InMemoryStoreConfig        # @Profile("!jdbc") — 4 in-memory DocumentStore beans (default)
│   └── JdbcStoreConfig            # @Profile("jdbc")  — 4 JDBC DocumentStore beans
├── domain
│   └── DocumentType               # enum NEWS / WATERBODY / FISH / STATION (label per entity)
├── repo
│   ├── DocumentStore              # interface: get/add/update (String id, String json)
│   ├── InMemoryDocumentStore      # default backing — ConcurrentHashMap, ids like "news-1", no DB
│   ├── JdbcDocumentRepository     # abstract SQL base: per-entity SQL + Resilience4j (jdbc profile)
│   ├── NewsDocumentRepository     # SQL Server: dbo.fn_news_doc / sp_news_doc_add / sp_news_doc_update
│   ├── MySqlNewsDocumentRepository # MySQL backing (2026-08-31) for GET only (sp_news_doc_get);
│   │                              #   addDocument/updateDocument delegate to NewsDocumentRepository
│   ├── WaterbodyDocumentRepository
│   ├── FishDocumentRepository
│   ├── StationDocumentRepository
│   ├── NewsQueryRepository        # interface: list(country, offset, limit) + defaultNews()
│   │                              #   + resolveRefNames(lakeIds, fishIds) (news-page queries)
│   ├── InMemoryNewsQueryRepository # default backing — empty results (no DB)
│   ├── JdbcNewsQueryRepository    # SQL Server backing — dbo.fn_news_list / dbo.fn_default_news_json
│   │                              #   / dbo.fn_news_search / dbo.fn_news_json / dbo.sp_news_import
│   │                              #   / dbo.fn_news_ref_names_json (lake+fish id -> display name)
│   ├── MySqlNewsQueryRepository   # MySQL backing (2026-08-31) — list/defaultNews only, via
│   │                              #   sp_news_list_json/sp_news_default; defaultNews then fills
│   │                              #   lake_name/fishes from SQL Server (2026-09-02);
│   │                              #   search/export/import/resolveRefNames delegate to a wrapped
│   │                              #   JdbcNewsQueryRepository (SQL Server)
│   ├── FishQueryRepository        # interface: search(query) + codesToLatin(...) + namesToLatin(...)
│   ├── InMemoryFishQueryRepository # default backing — empty results (no DB)
│   ├── JdbcFishQueryRepository    # JDBC backing — dbo.SearchFishList, fn_fish_code_latin_json,
│   │                              #   fn_fish_latin_json
│   ├── RiverQueryRepository       # interface: unfished/description/fish/source/mouth(lakeId)
│   ├── InMemoryRiverQueryRepository # default backing — found:false / null docs (no DB)
│   ├── JdbcRiverQueryRepository   # JDBC backing — dbo.fn_river_unfished_json / fn_lake_view_json /
│   │                              #   fn_lake_fishing_json / fn_lake_source_json / fn_lake_mouth_json
│   ├── RiverFishCommandRepository # interface: upsertFish(lakeId, itemsJson) — batch species upsert
│   ├── InMemoryRiverFishCommandRepository / JdbcRiverFishCommandRepository (sp_lake_fish_upsert_batch)
│   ├── RiverDescriptionCommandRepository # interface: patchDescription(lakeId, patchJson)
│   ├── InMemoryRiverDescriptionCommandRepository / JdbcRiverDescriptionCommandRepository
│   │                              #   (sp_lake_description_update)
│   ├── RiverLinkCommandRepository # interface: patchSource/patchMouth(lakeId, patchJson) — one
│   │                              #   repository for both tabs, same mechanism vs. Tributaries.side
│   └── InMemoryRiverLinkCommandRepository / JdbcRiverLinkCommandRepository
│                                  #   (sp_lake_source_update / sp_lake_mouth_update)
├── service
│   ├── DocumentService            # abstract base: id/body validation, JSON well-formedness, 404 mapping
│   ├── NewsDocumentService … (one @Service per entity)
│   ├── DocumentNotFoundException  # → HTTP 404
│   └── InvalidDocumentException   # → HTTP 400
└── web
    ├── AbstractDocumentController # GET/POST/PUT shared surface; body consumed as raw JSON string
    ├── NewsController             # base-path CRUD + News-page queries (/list, /default) + interchange /export, /import
    ├── FishController             # base-path CRUD + search (/search) + base-path Latin lookups
    │                              #   (?province=&codes= and ?fishes=)
    ├── RiverController            # GET /river/unfished (wbUnFish.aspx duplicate) + /river/description/{guid}
    │                              #   (lakejson&tab=view) + /river/fish/{guid} (tab=fishing) +
    │                              #   /river/source/{guid} (tab=source) + /river/mouth/{guid} (tab=mouth),
    │                              #   PATCH on fish/description/source/mouth
    ├── RegulationController        # GET/PATCH /river/regulation/{guid} + /region/regulation/{country}[/{state}]
    │                              #   (LakeRegulation.aspx "regulation dialog" duplicate — water-body + region scopes)
    ├── WaterbodyController … (one @RestController per entity, @RequestMapping base path only)
    ├── HealthController           # GET /health → { status, version, uptime }
    ├── ApiResponse                # { data, error, meta } envelope (record)
    └── ApiExceptionHandler        # @RestControllerAdvice mapping exceptions → envelope
```

The **base-plus-subclass** idiom (abstract repo/service/controller + thin per-entity subclasses)
mirrors `waterservice`'s `StationProcessorBase`/CA/US pattern and gives Spring a distinct bean type
to inject per entity. Services inject their store by qualifier (`@Qualifier("newsStore")` …); the two
store configs register beans under the same names, so switching profiles swaps the backing only.

---

## Storage backends (profiles)

- **default (no profile)** — `InMemoryStoreConfig` provides four `InMemoryDocumentStore` beans and one
  `InMemoryNewsQueryRepository`. No DB. `application.yml` excludes `DataSourceAutoConfiguration` /
  `DataSourceTransactionManagerAutoConfiguration` / `JdbcTemplateAutoConfiguration` and turns the
  actuator `db` health indicator off.
- **`jdbc` profile** — `application-jdbc.yml` clears the exclusion and configures the Hikari datasource
  (SQL Server) from `DB_URL`/`DB_USERNAME`/`DB_PASSWORD`; `JdbcStoreConfig` provides four
  `JdbcDocumentRepository` beans and one `JdbcNewsQueryRepository`; the `db` health indicator +
  readiness `db` group are re-enabled. Run with `--spring.profiles.active=jdbc`. **This same profile
  also builds a second, dedicated MySQL `JdbcTemplate`** (`JdbcStoreConfig.mysqlNewsJdbcTemplate`,
  from `MYSQL_NEWS_URL`/`MYSQL_NEWS_USERNAME`/`MYSQL_NEWS_PASSWORD`) used only by the news read path
  — see "MySQL backing for news reads" below. It's deliberately never registered as a `DataSource`
  bean (only the `JdbcTemplate` it builds is), so it can't collide with the primary SQL Server
  datasource via Spring Boot's `@ConditionalOnMissingBean(DataSource.class)`.

---

## Database contract (jdbc profile only — all four now exist in `envfish-db`)

Per-entity SQL objects the JDBC repositories call (`<entity>` ∈ news, waterbody, fish, station):

| Operation | SQL | Contract |
|-----------|-----|----------|
| return | `SELECT dbo.fn_<entity>_doc(?)` | returns document JSON string; `NULL` ⇒ 404 |
| add    | `EXEC dbo.sp_<entity>_doc_add ?` | inserts, returns new id scalar |
| update | `EXEC dbo.sp_<entity>_doc_update ?, ?` | updates, returns affected id scalar |

- Reads via a JSON **function**, writes via **procedures** — matches the platform rule that app code
  never touches base tables directly.
- The id is passed as a **string**; SQL Server converts it to the real key type (`int` /
  `uniqueidentifier`), so the Java layer is key-type agnostic.
- `waterbody` = the `dbo.lake` entity.
- `fish` doc objects (`fn_fish_doc`, `sp_fish_doc_*`) are **distinct** from the existing
  `dbo.fn_fish_document` / `dbo.sp_add_fish_document` (a PDF blob).
- SQL statement strings are `static final` constants in each concrete repository, so the DB pass can
  rename procs in one place.
- **`news`'s `GET` has moved to MySQL** (`MySqlNewsDocumentRepository`, wraps `NewsDocumentRepository`
  for the still-SQL-Server `POST`/`PUT`) — see "MySQL backing for news reads" below. The other three
  entities (`waterbody`, `fish`, `station`) are unaffected — full SQL Server CRUD as documented above.

### MySQL backing for news reads (2026-08-31, deployed 2026-09-01 as docapi 1.7.1)

`GET /api/v1/news/{id}`, `/news/list`, and `/news/default` read from the **MySQL** `news` table
(Winhost — the same table `fishfind-frontend/News.aspx` reads via `MySqlNewsHelper`), not SQL Server.
Everything else on `NewsController` (`POST`/`PUT /{id}`, `/news/search`, `/news/export/{id}`,
`/news/import`) is unchanged, still SQL Server — the MySQL database has no `lake`/`fish` tables to
resolve names against and no interchange/full-text-search objects.

| Endpoint | Backing | Notes |
|----------|---------|-------|
| `GET /api/v1/news/{id}` | MySQL `CALL sp_news_doc_get(?)` | `MySqlNewsDocumentRepository.getDocument`; `addDocument`/`updateDocument` delegate to the wrapped `NewsDocumentRepository` (SQL Server) |
| `GET /api/v1/news/list` | MySQL `CALL sp_news_list_json(?, ?, ?)` | `MySqlNewsQueryRepository.list`; same CA-padding contract as `dbo.fn_news_list` |
| `GET /api/v1/news/default` | MySQL `CALL sp_news_default()` **+ SQL Server `dbo.fn_news_ref_names_json`** | `MySqlNewsQueryRepository.defaultNews`; one shared JSON shape per item (no separate lead/compact shape), carrying `snippet`. The **only hybrid read in the service**: MySQL has no `lake`/`fish` tables, so the mentioned `lake_id`/`fish1..3_id` are resolved to `lake_name` + `fishes:[{id,name,latin}]` in one SQL Server round trip for the whole page. **Degrades, never fails** — an unreachable SQL Server logs a WARN and the page returns 200 with `lake_name: null` / `fishes: []`, since surviving a SQL Server outage is why news reads moved to MySQL at all |
| `search`/`export`/`import` | SQL Server (unchanged) | `MySqlNewsQueryRepository` delegates these three to a wrapped `JdbcNewsQueryRepository` |

New MySQL objects live in `envfish-db/mysql/script02_Proc.sql` (`sp_news_doc_get`,
`sp_news_list_json`, `sp_news_default`) — see that repo's `CLAUDE.md` → "MySQL (`mysql/`)" for the
schema-source/apply workflow. **Applied to the live Winhost database 2026-08-31.**

**⚠️ `sp_news_list_json` and `sp_news_default` depend on `news.has_photo0`** (a cached
`news_photo0 IS NOT NULL` flag, maintained by triggers) — the live Winhost host hangs indefinitely
on any query that references the actual `news_photo0`/`news_photo1` BLOB columns while materializing
more than one row (a temp table, a window function), even a bare `IS NOT NULL` check. This was
found live, post-deploy, and fixed the same day — see `envfish-db/CLAUDE.md` → "Cached flags on
`news`" and the `⚠️` warning above it before changing either procedure or adding a new one that
touches these columns at scale.

### News-page read queries (functions that already exist in `envfish-db`)

Separate from the CRUD above, `NewsController` exposes two read endpoints that delegate to
`NewsQueryRepository` — a separate abstraction for news-page queries. The repository has two
implementations: `InMemoryNewsQueryRepository` (default, returns empty results; no DB needed) and
`JdbcNewsQueryRepository` (jdbc profile, calls existing functions tested by `unit_test@DefaultNews.sql`).
Reads go through functions only (never base tables); both methods carry the same `sqlRetry`/`sqlBreaker`
Resilience4j guards as the document reads.

| Endpoint | SQL | Notes |
|----------|-----|-------|
| `GET /api/v1/news/list?country=&offset=&limit=` | `dbo.fn_news_list(?, ?, ?)` | latest news; ISO-2 country filter (a non-CA country < 100 items is padded with CA news to 100); `OFFSET/FETCH` paging + windowed `total`; limit default 25 / cap 200; bad country ⇒ 400 |
| `GET /api/v1/news/default` | `dbo.fn_default_news_json(news_id, with_photo) FROM dbo.fn_default_news_ids() ORDER BY ord` | assembled home page — 2 lead items then 3 right-column, each the per-item JSON document. **One call renders every news section of `fishfind-frontend`'s `Default.aspx`**: both lead articles (headline, byline + `author_link`, `flag`, `source`/`source_link`, photo `credit`/`photo_alt`, base64 `photo`, both paragraphs, and the tag row as `lake_id`/`lake_name` + `fishes`) and all three "More News" items (title, `source` — falling back to `author` when blank — `date`, `snippet`, `source_link`). The only thing on that page that is *not* news-table data is the "Latest Catch" sidebar card (`dbo.fn_default_latest_catch_json`, `catch_memo`), which has no endpoint here |
| `GET /api/v1/news/featured` | *(projection of `/default`)* | **just the 2 lead articles**, full documents incl. their base64 `photo`. Same cached assembly as `/default` — no extra query |
| `GET /api/v1/news/more` | *(projection of `/default`)* | **just the "More News" column**, compact: `news_id`, `date`, `title`, `source`, `link`, `snippet`. **~1.6 KB versus `/default`'s ~1.09 MB** (measured on prod) — that size gap is the entire reason the split exists. `source` falls back to `author`, and `snippet` is derived in Java from `paragraph0`/`paragraph1` when the DB does not supply one, so this works **without** the MySQL `snippet` view |
| *(internal)* `resolveRefNames(lakeIds, fishIds)` | `SELECT dbo.fn_news_ref_names_json(?, ?)` | batch guid → display name for the lake and fishes an article mentions. Both arguments are JSON **arrays** of guid strings (Jackson-rendered, so a value carrying a quote cannot reshape the argument) and the answer is 1:1 with the request in the order asked, an unresolved id keeping its slot with a null `name`. Not an HTTP endpoint — called by `MySqlNewsQueryRepository.defaultNews` beneath `NewsQueryCache`, so it needs no cache of its own |
| `GET /api/v1/news/search?q=` | `SELECT … FROM dbo.fn_news_search(?)` | up to 100 published matches, newest first, over headline/source/paragraphs/photo-alts + the up-to-3 mentioned fishes' names; caller escapes `% _ [`; blank `q` ⇒ 400; not cached (free-form key) |

### Fish-catalogue search query (function that already exists in `envfish-db`)

`FishController` exposes one read endpoint beyond the CRUD, delegating to `FishQueryRepository`
(interface + `InMemoryFishQueryRepository` default / `JdbcFishQueryRepository` jdbc). It reuses the
**same** relevance-ranked lookup the Editor `FishList.aspx` search box uses, so no new DB object was
needed — `dbo.SearchFishList` already exists in prod. Same `sqlRetry`/`sqlBreaker` guards; **not
cached** (open-ended search key), so no `@Primary`/cache layer like news list — just the one proxied
bean per profile.

| Endpoint | SQL | Notes |
|----------|-----|-------|
| `GET /api/v1/fish/search?q=` | `SELECT fish_name, fish_latin, fish_id, irank FROM dbo.SearchFishList(?) ORDER BY irank ASC` | relevance-ranked species search over primary name / Latin / `alt_name` synonyms; `SearchFishList` is a TVF that normalizes the term itself (no LIKE-escaping in Java), `varchar(64)` so the term is trimmed+capped at 64; `FishSearchItem` = (fishId, name, latin, rank — lower is better, 0 = exact); blank/missing `q` ⇒ 400. Literal `/search` matched ahead of `/{id}`. |

### Fish Latin-name lookups (functions that already exist in `envfish-db`)

`FishController` exposes two more read endpoints on its **base path**, told apart by the parameter
supplied (`fishes` wins if both are given). `/{id}` and `/search` are more specific, so the base path
was free. Both delegate to `FishQueryRepository` and mirror the portal's `/WebService/Fish/` endpoint.

| Endpoint | SQL | Notes |
|----------|-----|-------|
| `GET /api/v1/fish?province=&codes=&country=` | `SELECT dbo.fn_fish_code_latin_json(?, ?, ?)` | regional code → latin, `[{code, latin}]`. **`province` required with `codes`** (`dbo.fish_code` is keyed country+state+code, so a bare code is meaningless) ⇒ else 400; no `codes` ⇒ the whole province; `country` optional, default any. **One element per MATCH, not per code** — BC `RB` is both Rock Bass and Rainbow Trout, `LS`/`WS` likewise; `TOP 1` would hide half the answer. A miss keeps its slot with `latin` null; an unknown province is 200-with-nulls, not an error. |
| `GET /api/v1/fish?fishes=` | `SELECT dbo.fn_fish_latin_json(?)` | batch name → latin, `[{query, name, latin}]`, one per requested name **in order**; `query` echoes the input so the response zips back against the request; a miss keeps its slot (dropping it would mis-pair everything after it). Substring match, so `Walley` → `Walleye`. |

**List parsing.** Both accept `{…}`/`[…]` wrappers, comma or semicolon separators, quoted items, and
repeated parameters: **>1 value ⇒ each is one entry verbatim; exactly 1 ⇒ split it, honouring quotes.**
This is load-bearing — **762 of the 1041 species names contain a comma** ("Bass, Guadalupe"), so values
are read via `HttpServletRequest.getParameterValues`, **not** `@RequestParam List<String>`, which Spring
splits on commas and which would tear most of the catalogue in half. The DB argument is a JSON array
built with Jackson (escaping handled), because `OPENJSON` also supplies the element index that preserves
ordering. Batch cap 100 ⇒ 400.

### River / water-body query (`RiverController`)

`RiverController` exposes five read endpoints, delegating to `RiverQueryRepository` (interface +
`InMemoryRiverQueryRepository` default / `JdbcRiverQueryRepository` jdbc). Same `sqlRetry`/
`sqlBreaker` guards on all five; **not cached** — one proxied bean per profile.

| Endpoint | SQL | Notes |
|----------|-----|-------|
| `GET /api/v1/river/unfished?country=&state=&river=` | `SELECT dbo.fn_river_unfished_json(?, ?, ?)` | **Native docapi duplicate of the frontend `Resources/wbUnFish.aspx`** endpoint the add-fish tooling uses — backed by `dbo.fn_river_unfished_json`, added test-first (`unit_test@RiverUnfished.sql`, 4 tests). The next un-processed water body of a type in a state (no fish assigned, not flagged No Fish), as `{ found, country, state, river, lake_id, lake_name, mouth_name, CGNDB, throwing }` (fields null when `found:false`). `throwing` = comma-joined `CGNDB` of the `side=2` ("Throw") tributaries. `country` is **echoed only** (the query filters by state). **No 400s** — a bad `country`/`state` falls back to the default (CA/ON) and a bad `river` to `2`, mirroring `wbUnFish.aspx` `CleanCode`/`ParseRiver`. The DB function keeps the raw-table access (`Tributaries`/`Lake`) inside the DB per the no-raw-table rule. |
| `GET /api/v1/river/description/{guid}` | `SELECT dbo.fn_lake_view_json(?)` | **Native docapi duplicate of the admin "Save JSON" View-tab export** (`Editor/HandlerImage.ashx?lakejson=<guid>&tab=view`). Returns the full description document — name/alt names, description text, physical stats, source/mouth detail, assigned fish, and the photo gallery (base64). `dbo.fn_lake_view_json` **already exists in prod** (added 2026-08-14 for the admin Save-JSON tabs — see the 2026-08-14 entry in the root `CLAUDE.md`), so this is a **docapi-only change with no new DB object**. `NULL` (unknown guid) ⇒ 404, mirroring `/news/export/{id}`. **Note on access:** the frontend export path is admin-gated (`IsRequestAdmin`), but the underlying data is the same content anonymous visitors already see on `Resources/wfRiverViewer.aspx` — the admin gate is about that download convenience, not data sensitivity, so exposing it as a public docapi GET matches the rest of this service's (unauthenticated) surface. Literal `/description/…` matched ahead of any future templated route on this controller. |
| `GET /api/v1/river/fish/{guid}` | `SELECT dbo.fn_lake_fishing_json(?)` | **Native docapi duplicate of the admin "Save JSON" Fishing-tab export** (`Editor/EditLakeFish.aspx` → `HandlerImage.ashx?lakejson=<guid>&tab=fishing`). Returns the assigned-species document for one water body — every `lake_fish` row (name, latin, conservation status, last-catch, external link). `dbo.fn_lake_fishing_json` **already exists in prod** (same 2026-08-13 per-tab Save-JSON rollout as `fn_lake_view_json`), so this is again a **docapi-only change with no new DB object**. `NULL` (unknown guid) ⇒ 404. Same public-data reasoning as `/description/{guid}` — the assigned species list is shown publicly on `Resources/wfRiverViewer.aspx`. Literal `/fish/…` matched ahead of any future templated route on this controller. |
| `PATCH /api/v1/river/fish/{guid}` | `EXEC dbo.sp_lake_fish_upsert_batch ?, ?` | **The write counterpart — a native duplicate of the "Add" form on `Editor/EditLakeFish.aspx`** (`AddFishToLake`). Body is a JSON array of `{fishId, link, trustLevel, year, status}` entries (`fishId` required, the rest optional), upserted in one batch by `RiverFishCommandRepository` / `sp_lake_fish_upsert_batch` (new DB object, 2026-08-25). **Unlike every other river endpoint this is a genuine write** — the shared `sqlBreaker`/`sqlRetry` guards still apply, but there's no cache in front of it and it's a separate `RiverFishCommandRepository` bean (not a method on `RiverQueryRepository`) precisely because it mutates `lake_fish`. Per entry: `inserted` (new), `updated` (existing row whose `link` is empty/NULL — the only case an existing row is touched), `skipped` (existing row **with** a link — deliberately never overwritten), `unknown_fish` (guid not in `dbo.fish`), `invalid_fish_id` (not a guid). Empty/non-array/over-500-entry body ⇒ 400 `invalid_document`; unknown guid ⇒ 404. **Fronted through cproxy as of 0.6.1** (deployed 2026-08-25) — `CPROXY_ALLOWED_METHODS` now admits `PATCH`, gated by a per-day rotating credential (`X-Day-Guid` checked against a SQLite `DayKeyStore`), not a static API key. Verified live end-to-end through the public gateway. See `efc-proxy` `CLAUDE.md` → "Day-key store". |
| `PATCH /api/v1/river/description/{guid}` | `EXEC dbo.sp_lake_description_update ?, ?` | **A second, independent write — a JSON merge patch of the `Editor/LakeEditor.aspx` "General" tab's editable fields**, via `RiverDescriptionCommandRepository` / `sp_lake_description_update` (new DB object, 2026-08-25). Body is a JSON **object** (not an array like the fish endpoint) of `fieldName: value`; only keys actually present are touched — an explicit JSON `null` clears that field, an omitted key leaves it alone. Covers `altName`, `nativeName`, `french`, `link`, `type`, `length_km`, `width_km`, `shoreline_km`, `maxDepth_m`, `volume_km3`, `surface_km2`, `discharge_m3s`, `basin_km2`, `watershield_km2`, `drainage`, `cgndb`, `roadAccess`, `fishingProhibited`, `isolated`, `noFish`, `reviewed`, `description`. **Deliberately protects the identity/linkage fields `LakeEditor.aspx` shows read-only in this exact spot** — `lakeName`, `source`/`sourceId`, `mouth`/`mouthId` — reporting them back as `protectedFields` rather than silently dropping or applying them; `noFish` is blocked (reported `ignored`) while the lake has assigned species, mirroring the page's own client-side rule. Empty/non-object/over-100-key body ⇒ 400 `invalid_document`; unknown guid ⇒ 404. Response: `{lakeId, updated:[{field}], ignored:[{field,reason}], protectedFields:[{field,reason}]}`. **Fronted through cproxy automatically** — the day-key gate applies to every PATCH, not a specific path, so no cproxy change was needed; verified live end-to-end through the public gateway. |
| `GET /api/v1/river/source/{guid}` | `SELECT dbo.fn_lake_source_json(?)` | **Native docapi duplicate of the admin "Save JSON" Source-tab export** (`Editor/EditLakeLink.aspx?Type=16` → `HandlerImage.ashx?lakejson=<guid>&tab=source`). Returns `{guid, lakeName, sources:[{id, pointId, pointName, lat, lon, elevation, country, state, county, city, district, municipality, region, zone, coast, location, description, stamp}]}` — normally one element (`UK_Tributaries_Source` allows at most one `side=16` row per water body). `dbo.fn_lake_source_json` **already exists in prod** (2026-08-13 rollout), so this is a **docapi-only change with no new DB object** for the read side. `NULL` (unknown guid) ⇒ 404. Same public-data reasoning as `/description/{guid}`. |
| `GET /api/v1/river/mouth/{guid}` | `SELECT dbo.fn_lake_mouth_json(?)` | Same shape as `/source/{guid}` above (`mouths` key instead of `sources`), for the `side=32` row (`Editor/EditLakeLink.aspx?Type=32`, `UK_Tributaries_Mouth`). `NULL` ⇒ 404. |
| `PATCH /api/v1/river/source/{guid}` | `EXEC dbo.sp_lake_source_update ?, ?` | **The write counterpart — a JSON merge patch of `Editor/EditLakeLink.aspx?Type=16`'s editable fields**, via the new `RiverLinkCommandRepository` / `sp_lake_source_update` (new DB object, 2026-08-26). Body is a JSON object; only keys present are touched. Covers `lat`, `lon`, `elevation`, `country`, `state`, `county`, `city`, `district`, `municipality`, `region`, `zone`, `coast`, `location`, `description` — the exact set `ButtonSubmit_Click` writes for this tab. **Deliberately protects every identity/linkage field `EditLakeLink.aspx` shows read-only in this exact spot** — the main water body's own `lakeName`/`guid`, and the linked point's `pointName`/`pointId` (plus the row's internal `id`/`stamp`, neither a user-editable field) — reported back as `protectedFields`, same contract as `description`. Empty/non-object/over-100-key body ⇒ 400 `invalid_document`; unknown lake guid ⇒ 404. Response shape matches the description PATCH. **Fronted through cproxy automatically** — the day-key gate is verb-based, not path-based, so no cproxy change is needed. **Not yet deployed to prod** — see the 2026-08-26 changelog entry. |
| `PATCH /api/v1/river/mouth/{guid}` | `EXEC dbo.sp_lake_mouth_update ?, ?` | Same contract as `PATCH /river/source/{guid}` above, targeting the `side=32` row via the new `sp_lake_mouth_update`. Both PATCH procedures live behind one shared `RiverLinkCommandRepository` bean (`patchSource`/`patchMouth`), not two separate repositories, since they are the identical merge-patch mechanism against a different `Tributaries.side`. |

### Regulation query/write (`RegulationController`)

`RegulationController` (`@RequestMapping("/api/v1")`, method-level full paths — its two resource
families don't share a base) covers two of the three scopes `Editor/LakeRegulation.aspx`'s single
"regulation dialog" edits through one `dbo.regulations` table (water-body and region/country-state;
zone-scoped rules have no dedicated endpoint yet). Delegates to `RegulationQueryRepository` /
`RegulationCommandRepository` (interface + `InMemory…`/`Jdbc…` pair each, same `sqlRetry`/`sqlBreaker`
guards, not cached).

| Endpoint | SQL | Notes |
|----------|-----|-------|
| `GET /api/v1/river/regulation/{guid}` | `SELECT dbo.fn_lake_regulation_json(?)` | This water body's OWN regulation rows only — never the region/zone rules that also apply to it. Pre-existing per-tab admin "Save JSON" export function (2026-08-13 rollout), **extended 2026-08-25** to also emit the new `country` field. `NULL` ⇒ 404. |
| `PATCH /api/v1/river/regulation/{guid}` | `EXEC dbo.sp_regulation_upsert ?` | `lakeId` always taken from the path (overrides anything the body sends) and `zoneId` stripped, so this route can only write the water-body scope. See the upsert contract below. |
| `GET /api/v1/region/regulation/{country}` | `SELECT dbo.fn_region_regulation_json(?, NULL)` | Whole-country rules — rows with **no** state at all, not a roll-up of every province. Never 404 (an unrecognized country just yields an empty `regulations` array). Non-two-letter `country` ⇒ 400. |
| `GET /api/v1/region/regulation/{country}/{state}` | `SELECT dbo.fn_region_regulation_json(?, ?)` | Province/state-wide rules — a *different*, non-overlapping row set from the country-only route. Same 400/never-404 rules. |
| `PATCH /api/v1/region/regulation/{country}[/{state}]` | `EXEC dbo.sp_regulation_upsert ?` | `country`/`state` taken from the path; `state`/`zoneId`/`lakeId` stripped from the body on the single-segment route, `zoneId`/`lakeId` stripped on the two-segment one. |

**Upsert contract (`dbo.sp_regulation_upsert`, new proc, `envfish-db` 2026-08-25,
`unit_test@RegulationUpsert.sql`, 11 tests):** **there is no separate INSERT verb.** Identity =
`country`/`state`/`zoneId`/`lakeId`/`fishId`/`year`/`part`/`residentType` — the columns behind
`dbo.regulations`' two filtered unique indexes. A body matching nothing existing inserts
(`action:"inserted"`); one matching an existing row updates it in place (`action:"updated"`). Scope is
*inferred*, not declared: `lakeId` set → water-body; `zoneId` set (no `lakeId`) → zone; neither →
region (whole-country when `state` omitted, else province/state-wide). `zoneId`+`lakeId` both set is
rejected. Response `{id, action, scope}` on success, or `{id:null, action:null, error}` on a
validation failure (missing `year`, unknown `lakeId`/`fishId`, or the mutual-exclusivity violation) —
**a 200 with an inline error, not a 4xx**, the same graceful contract as
`sp_lake_description_update`'s malformed-JSON path. `dbo.TR_regulations` (`FOR INSERT`) auto-adds the
row to `lake_fish` when a new water-body rule carries a `fishId` not yet assigned to that lake — same
side effect the ASPX page's own INSERT triggers, silent from this endpoint's point of view.

**No dedicated POST, and no cproxy change.** cproxy's write surface only admits `GET`/`PATCH` (the
day-key gate is verb-based, not path-based) — reusing the fish/description endpoints' upsert-on-PATCH
pattern means this whole feature is automatically fronted through cproxy with zero proxy-side change.

**Schema change required:** `dbo.regulations` had no `country` column and `state` was `NOT NULL`, so a
genuine "whole country, no state" rule wasn't representable. Added `country char(2) NOT NULL DEFAULT
'CA'`, relaxed `state` to nullable, and folded `country` into both `UIX_reg_with_fish`/`UIX_reg_no_fish`
filtered unique indexes — SQL Server treats two NULLs as equal for unique-index purposes, so without
`country` in the key a second country's state-less rule would collide with the first country's. See the
"PRODUCTION MIGRATION — regulations: add `country`…" block in `envfish-db/mssql/script01_createTable.sql`
(idempotent, guarded, for databases created before this change) — the base `CREATE TABLE` was also
updated directly for fresh builds.

### Interchange export / import (`fn_news_json` format)

`NewsController` also exposes an **export** (read) and **import** (write) pair on `NewsQueryRepository`,
using the **`fn_news_json` interchange format** — the same self-contained JSON the portal's News.aspx
"Save JSON" link and `AddNews.aspx` "Import from JSON" round-trip use. **Only these two endpoints carry
the FULL document** (every field + all 3 paragraph photos embedded as base64); the endpoints above keep
their existing lighter shapes / amount. Export reads through `NewsQueryCache` uncached (large per-id
payload); import evicts the cached lists + home page so a new article shows up immediately.

| Endpoint | SQL | Notes |
|----------|-----|-------|
| `GET /api/v1/news/export/{id}` | `SELECT dbo.fn_news_json(?)` | full interchange doc (all fields + 3 base64 photos); `NULL` ⇒ 404. Literal `/export/…` prefix is matched ahead of `/{id}`. |
| `POST /api/v1/news/import` | `EXEC dbo.sp_news_import ?` | creates a **published** article from an `fn_news_json` body (base64 photos decoded to binary), returns `201 { id }`; blank/malformed body ⇒ 400 |

`dbo.fn_news_json` already exists in `envfish-db`; `dbo.sp_news_import` was added there test-first
(`unit_test@NewsImport.sql`). `news_title` is UNIQUE, so importing an existing title raises the
duplicate-key error. Both methods carry the same `sqlRetry`/`sqlBreaker` guards.

---

## News caching — read from memory, touch the database only on a cold entry

**Every news read endpoint is served from an in-process cache; the database is queried only when the
entry that answers it is empty.** This is not a nice-to-have: the `news` table lives on a remote
Winhost MySQL whose pool is 5 connections and which sits behind cproxy's 10 s read timeout, so a read
that reaches it on every request is a latency and availability problem, not just a slow one. Two
decorators, both wired in `JdbcStoreConfig` as the bean the controller/service actually injects:

| Endpoint | Cache | Key / unit held |
|----------|-------|-----------------|
| `GET /api/v1/news/{id}` | `NewsDocumentCache` | LRU of the last 25 documents, keyed by lower-cased guid, **plus** a bounded set of recently-seen unknown ids (see below) |
| `GET /api/v1/news/list` | `NewsQueryCache` | US and CA as 100-**row** buckets (one fetch answers every offset/limit inside them); everything else — the unfiltered request, other countries, and US/CA pages past their bucket — as whole responses in an LRU of 100, keyed `country\|offset\|limit` |
| `GET /api/v1/news/default` | `NewsQueryCache` | the single assembled home page |

Three rules keep the "only on a cold entry" promise honest — **do not regress them**:

1. **Nothing reads through repeatedly.** Every path that can reach the database stores what it
   loaded. The deep-paging branch of `/news/list` used to be the exception: a window past the cached
   100 rows re-queried on *every* request, so anything walking the pager hit MySQL each time. It now
   falls through to the same keyed LRU (fixed 2026-09-02).
2. **A cold entry is loaded once, not once per concurrent request.** Both caches load under a striped
   lock with a double-check, so a burst on an empty cache produces one query and N answers. This
   holds a lock across the database call *on purpose*: with a 5-connection pool a stampede would
   queue on the pool anyway, having done the same work many times over first.
3. **A miss is an answer too.** An unknown/unpublished id used to reach the database on every
   request — so a crawler walking guids could hammer MySQL indefinitely, no matter how well real
   articles were cached. Unknown ids are now remembered for `NewsDocumentCache.MISS_TTL_MS` (60 s) in
   a separate bounded map. **The TTL is the point**: `AddNews.aspx` writes straight to the database
   and never notifies docapi, so a newly published article must become visible on its own — within a
   minute, not at the next daily clear. A publish/update *through* docapi drops the remembered miss
   immediately. This is the only entry in either cache that expires by itself.

**Deliberately not cached:** `/news/search` (open-ended term, unbounded key space) and
`/news/export/{id}` (large per-id document with base64 photos, rarely re-requested). Also
`resolveRefNames` — it is called *beneath* `NewsQueryCache` while `/news/default` is being assembled,
so the cached home page already covers it; a cache of its own would just hold a second copy.

**Invalidation** is `NewsCacheEvictor`: one clear a day at 00:00 UTC, **skipped while SQL Server is
unreachable** (clearing mid-outage would turn a database outage into a total content outage) and
retried every 5 minutes until a `SELECT 1` probe succeeds. `POST /news/import` clears the query cache
so a new article appears at once.

⚠️ **Consequence worth knowing:** the caches are per-process and hold whatever was loaded, including
a `/news/default` assembled while SQL Server was down (ids only, no `lake_name`/`fishes` — see the
degrade behaviour above). That degraded page is served until the next eviction.

---

## Request/response behaviour

- Request bodies are consumed as a **raw JSON string** (`@RequestBody String`, `consumes` JSON), then
  validated in `DocumentService.requireValidJson` via Jackson `readTree`. Blank/malformed body ⇒
  `InvalidDocumentException` ⇒ HTTP 400. The stored body is the **normalized** (re-serialized) JSON.
- `GET` returns the stored document parsed to a `JsonNode` so it nests as real JSON in `data` (not an
  escaped string). Missing document ⇒ `DocumentNotFoundException` ⇒ HTTP 404.
- `POST` returns HTTP 201 with `data = { "id": <newId> }`; `PUT` returns 200 with `data = { "id": <id> }`
  (falls back to the supplied id when the update proc returns no scalar).
- Every response is an `ApiResponse` envelope `{ data, error, meta }` with a `meta.timestamp`.
  `ApiExceptionHandler` maps: not-found → 404 `not_found`; invalid/unreadable body → 400
  `invalid_document`; anything else → **logged** and 500 `internal_error` (no internal details leak).

---

## Resilience4j

Only SQL is guarded (no HTTP feeds, unlike `waterservice`):

- `sqlRetry` — **2×/500ms**, and only on **transient** failures (was 3×/2s on the root
  `DataAccessException` until 2026-09-02, i.e. it retried everything).
  **The three configured types are not redundant** — Spring files connection failures under
  different branches, so "just use `TransientDataAccessException`" would stop retrying driver-level
  connect failures, the very case this exists for:
  | failure | JDBC exception | Spring type |
  |---|---|---|
  | Hikari pool timeout | `SQLTransientConnectionException` | `TransientDataAccessResourceException` (Transient) |
  | driver connect failure | `SQLNonTransientConnectionException` | `DataAccessResourceFailureException` (**NonTransient**) |
  | connection dropped mid-use | `SQLRecoverableException` | `RecoverableDataAccessException` (Recoverable) |
  Permanent faults (`BadSqlGrammarException`, `DataIntegrityViolationException`, …) must never be
  retried — it only multiplies latency, and on a write path it can compound the damage.
  `DocApiJdbcWiringTest.onlyTransientFailuresAreRetried` asserts the classification behaviourally,
  and `retryExceptionListMirrorsProduction` pins `application-test.yml` to the same list so the
  suite cannot exercise different retry semantics from production.
- `sqlBreaker` — window 10, min 5 calls, 50% threshold, open 30s.

**TWO DATASOURCES — never let Spring pick the JdbcTemplate by accident.** docapi has a SQL Server
datasource *and* a MySQL news datasource. `JdbcTemplateAutoConfiguration` is
`@ConditionalOnMissingBean(JdbcOperations.class)`, so **defining any `JdbcTemplate` bean makes it
back off entirely**. `JdbcStoreConfig.mysqlNewsJdbcTemplate` does exactly that, which between
2026-08-31 and 2026-09-02 left the SQL Server template uncreated and handed the MySQL one to all
thirteen beans that inject `JdbcTemplate` by type — production sent T-SQL to MySQL and every
SQL-Server-backed endpoint 500'd, while `docapi-hikari` never even started. The SQL Server
`JdbcTemplate` is therefore declared explicitly and marked `@Primary`; MySQL consumers must keep
using `@Qualifier("mysqlNewsJdbcTemplate")`. **If you add a third datasource, qualify everything and
extend `DocApiJdbcWiringTest.sqlServerRepositoriesGetTheSqlServerTemplateNotTheMysqlOne`** — that
test asserts pool *names*, because H2 stands in for SQL Server in tests and a misdirected template
otherwise still appears to work.

**TIME BUDGET — the DB failure path must finish inside cproxy's 10s read timeout.** cproxy fronts
this service and gives up after 10s (twice for idempotent GETs), so anything slower reaches the
caller as an opaque `502` with no diagnosis. The knobs that decide this are the Hikari
`connection-timeout` (both pools), the driver-level `loginTimeout` (mssql-jdbc, **seconds**) /
`connectTimeout` (Connector/J, **milliseconds**), and `sqlRetry`. Current worst case ≈ 6.5s
(2 × 3s connect + 500ms wait).

**Why it matters (2026-09-02):** the settings were 30s Hikari connect, no driver timeouts, and
3×/2s retry — a worst case near **94s for one request**. The droplet's network path to the Winhost
DB hosts intermittently drops TCP handshakes (measured ~2 of 6 probes timing out), and a dropped SYN
is silence rather than a refusal, so every attempt sat the full 30s. Every `/api/*` call that touched
a database appeared to hang; `/health` and validation-only paths stayed instant, which made it look
like a query problem when it was not — `dbo.SearchFishList('trout')` runs in 112ms. **Both** pools
are affected, since MySQL and SQL Server sit at the same provider over the same path; moving news to
MySQL did not escape it. `DocApiJdbcWiringTest.dbFailurePathFitsInsideTheProxyReadTimeout` asserts
the budget, and reads the retry numbers from the production yaml on purpose — `application-test.yml`
overrides `sqlRetry` to 3×/10ms for speed, so asserting the running context would have passed while
production stayed broken.
- Aspect order: breaker (2) outermost, retry (1) inner — an open breaker fails fast without burning
  retries. Every `DocumentRepository` method carries `@Retry` + `@CircuitBreaker` with a fallback that
  rethrows as an unchecked exception (→ handled as 500).

---

## Config, logging, observability

- **Datasource** (jdbc profile only, `application-jdbc.yml`) from `DB_URL`/`DB_USERNAME`/`DB_PASSWORD`;
  Hikari pool `docapi-hikari` (`maximum-pool-size: 8`, `min-idle: 2`, `max-lifetime 29m`,
  `keepalive 5m`). The default profile configures no datasource.
- **Credential loading**: `DotenvEnvironmentPostProcessor` registered via
  `META-INF/spring/org.springframework.boot.env.EnvironmentPostProcessor.imports`; loads `.env`
  (or `DOTENV_PATH`) as the **lowest-precedence** source — never `System.setProperty`.
- **Actuator** on private `management.server.port: 8082`; exposed endpoints only
  `health,info,prometheus,metrics`; `health.show-details: never`; liveness (not DB-dependent) vs
  readiness (includes `db`). Lightweight `/health` on 8080 is the Docker HEALTHCHECK target;
  `version` from Maven `build-info`.
- **Logging**: JSON via `logstash-logback-encoder` (`"service":"docapi"`), console + rolling file
  (`logs/docapi.log`, 7-day history), `com.fishfind.docapi` at INFO.

---

## Docker

Multi-stage (Maven build → `eclipse-temurin:21-jre`), both base images **pinned by digest**. Runs as
non-root `USER 10001:10001` with `/app/logs` pre-created (read-only-rootfs friendly). Installs `wget`
so `HEALTHCHECK wget -qO- http://localhost:8080/health` works. `.dockerignore` excludes `.env`,
secrets, and build artifacts. Never bake a real `.env` into the image.

```
CMD: java $JAVA_OPTS -jar /app/docapi.jar
```

---

## Dependency scanning

OWASP Dependency-Check via a Maven `security` profile: `mvn -Psecurity verify` (fails on CVSS ≥ 7;
set `NVD_API_KEY`). Kept out of the default lifecycle.

---

## Tests

`mvn test` — no DB needed (144 tests):

- `DocumentServiceTest` — validation, normalization, not-found (mocks `DocumentStore`).
- `NewsDocumentRepositoryTest` — get mapping + SQL string (mocks `JdbcTemplate`), SQL Server.
- `MySqlNewsDocumentRepositoryTest` — `getDocument` reads via `CALL sp_news_doc_get(?)` against the
  mocked MySQL `JdbcTemplate`; `addDocument`/`updateDocument` delegate to a mocked `DocumentStore`
  (never touching MySQL).
- `MySqlNewsQueryRepositoryTest` — `list`/`defaultNews` read via `CALL sp_news_list_json(?, ?, ?)` /
  `CALL sp_news_default()` against the mocked MySQL `JdbcTemplate`; `search`/`exportNews`/`importNews`
  delegate to a mocked `NewsQueryRepository` (never touching MySQL). Also covers the home-page name
  enrichment: names merged onto each item from ONE `resolveRefNames` call, empty slots skipped, no
  lookup at all when nothing is mentioned, and **ids-only degradation when that lookup throws**.
- `JdbcNewsQueryRepositoryTest` — the SQL Server side of `resolveRefNames`: SQL string, both
  arguments bound as JSON arrays (`[]` for a null/empty list), and an empty object when the function
  yields nothing.
- `NewsControllerTest` — `@WebMvcTest` slice: CRUD envelope (404, 201, 400) **plus** the News-page
  queries via mocked `NewsQueryRepository` — empty `/list`+`/default` with a 400 on a bad country,
  successful queries returning paginated items or home-page JSON, **and the interchange
  `/export/{id}` (200 doc / 404) + `/import` (201 id / 400 on empty/malformed body)**.
- `NewsCacheTest` — both news caches: what is held, `/export` read-through (never cached), `/import`
  evicting the cached lists + home page, and the three "only on a cold entry" guarantees — deep pages
  cached after their first load, cold entries loaded **once** under concurrency (16 threads ⇒ 1
  query, for both `/list` and `/default`, and for a document), and unknown ids remembered, bounded,
  TTL-expiring, and dropped on update. **All six verified failing first** against the pre-2026-09-02
  behaviour.
- `DocumentRoundTripTest` — `@SpringBootTest` + MockMvc, default in-memory backing: POST→GET→PUT→GET
  round-trip, 404, all four entities accept documents, and the News `/list`+`/default` queries return
  empty payloads (the "it actually works with no DB" proof).
- `HealthControllerTest`, `DocApiApplicationTest` (mocks `SpringApplication.run`).
- `DocApiContextTest` — full context boot on the default (in-memory) profile.
- `DocApiJdbcWiringTest` — boots the `jdbc` profile with an H2 stand-in to keep that wiring verified.
- `FishControllerTest` — `@WebMvcTest` slice: CRUD envelope (200 doc / 404) **plus** `/fish/search`
  via a mocked `FishQueryRepository` — result mapping, term trimming, empty result, blank/missing
  `q` ⇒ 400.
- `RiverControllerTest` — `@WebMvcTest(RiverController.class)`, `@MockBean` `RiverQueryRepository` +
  `RiverFishCommandRepository` + `RiverDescriptionCommandRepository` + `RiverLinkCommandRepository`
  (33): `/river/unfished` result mapping, default fallback (missing params → CA/ON/2), bad-code/river
  cleaning (never rejected), lower-case state upper-casing, `GET /river/description/{guid}` (200 doc /
  404 on an unknown guid), `GET /river/fish/{guid}` (200 doc / 404 on an unknown guid),
  `PATCH /river/fish/{guid}` (6: 200 result envelope, 404 unknown lake, 400 empty array, 400 non-array
  body, 400 missing body, 400 over-`MAX_FISH_BATCH`), `PATCH /river/description/{guid}` (6: 200 result
  envelope, 404 unknown lake, 400 empty object, 400 array body, 400 missing body, 400
  over-`MAX_PATCH_FIELDS`), and **`GET`/`PATCH /river/source/{guid}` + `GET`/`PATCH /river/mouth/{guid}`**
  (9: 200 doc / 404 unknown guid for each GET; 200 result envelope incl. a protected-fields case, 404
  unknown lake, 400 empty object, 400 missing/array body for each PATCH) — the 400 cases across every
  PATCH endpoint also assert the repository is never called, i.e. validation happens before any SQL.
- `RegulationControllerTest` — `@WebMvcTest(RegulationController.class)`, `@MockBean`
  `RegulationQueryRepository` + `RegulationCommandRepository` (11): `GET /river/regulation/{guid}` (200
  doc / 404 unknown), `PATCH /river/regulation/{guid}` (200 result envelope — an `ArgumentCaptor`
  asserts `lakeId` is injected from the path and `zoneId` stripped even when the body supplies both,
  400 missing/array body), `GET /region/regulation/{country}` and `.../{country}/{state}` (null-vs-set
  state passed through, upper-casing, 400 on a non-two-letter country), and
  `PATCH /region/regulation/{country}` / `.../{country}/{state}` (asserts `country`/`state` set from
  the path and `state`/`zoneId`/`lakeId` stripped from the body, 400 on a non-two-letter state).

---

## API / platform architectural rules (shared across services)

- All endpoints versioned: `/api/v1/...`
- Standard response envelope: `{ data, error, meta }`
- Every external/DB call: timeout + retry with backoff; circuit breaker on downstream deps.
- Health check: `GET /health` → `{ status, version, uptime }`.
- Each service owns its data store exclusively.

## Changelog

Moved to [`CHANGELOG.md`](./CHANGELOG.md) (same directory) for readability — this file was getting
long. Newest entries first there.
