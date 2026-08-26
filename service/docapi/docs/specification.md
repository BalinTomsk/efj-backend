# docapi — Specification

> Single source of truth: this document must be sufficient on its own to recreate the `docapi`
> service from scratch. Keep it complete and accurate on every code change.

## Goal

A REST service exposing JSON-document CRUD for four entities — **news**, **waterbody**, **fish**,
**station**. Modelled on the sibling `waterservice`, but a synchronous HTTP API rather than a
background worker (no scheduler, no worker threads, no upstream feed fetching).

**Two storage backends behind a `DocumentStore` interface:**

- **default (no profile)** — an in-memory store, so the service runs with **no database** connection
  or configuration (the initial working service);
- **`jdbc` profile** — each entity backed by its own SQL Server objects (a JSON function for reads,
  stored procedures for writes).

The default profile excludes JDBC/datasource auto-configuration entirely, so nothing tries to reach a
database unless `jdbc` is active.

## Project identity

| Key | Value |
|-----|-------|
| Service name | `docapi` |
| Language | Java 21 |
| Build | Maven |
| Framework | Spring Boot 3.3.13 |
| groupId / artifactId / version | `com.fishfind` / `docapi` / `1.0.0` |
| Root package | `com.fishfind.docapi` |
| Main class | `com.fishfind.docapi.DocApiApplication` |
| App/health port | 8080 |
| Management (Actuator) port | 8082 (private) |

## Endpoints

For `<entity>` ∈ { `news`, `waterbody`, `fish`, `station` }:

| Verb | Path | Success status | Response `data` |
|------|------|----------------|-----------------|
| `GET`  | `/api/v1/<entity>/{id}` | 200 | the stored document (nested JSON) |
| `POST` | `/api/v1/<entity>`      | 201 | `{ "id": <newId> }` |
| `PUT`  | `/api/v1/<entity>/{id}` | 200 | `{ "id": <id> }` |
| `GET`  | `/health`               | 200 | `{ status, version, uptime }` |

**News-page read queries** (news only, added on `NewsController` — call the SQL functions built in
`envfish-db`; see [Data access](#data-access)):

| Verb | Path | Success status | Response `data` |
|------|------|----------------|-----------------|
| `GET` | `/api/v1/news/list?country=&offset=&limit=` | 200 | `{ items:[{ rn, newsId, title, source, stamp, flag, hasPhoto, blockOrd }], total, offset, limit }` |
| `GET` | `/api/v1/news/default` | 200 | `{ items:[ <news JSON>, … ] }` (the assembled home page) |
| `GET` | `/api/v1/news/search?q=` | 200 | `{ items:[{ newsId, title, source, stamp, country, fishes:[…] }], total, query }` (≤100, newest first; blank `q` ⇒ 400) |

**Fish-catalogue search** (fish only, added on `FishController` — calls `dbo.SearchFishList`, which
already exists in `envfish-db`; see [Data access](#data-access)):

| Verb | Path | Success status | Response `data` |
|------|------|----------------|-----------------|
| `GET` | `/api/v1/fish/search?q=` | 200 | `{ items:[{ fishId, name, latin, rank }], total, query }` (best match first; blank/missing `q` ⇒ 400) |

- `GET /api/v1/fish/search` — relevance-ranked species search backed by `dbo.SearchFishList(@q)`,
  matching the term against the primary name, Latin name, and `alt_name` synonyms (the same lookup the
  Editor `FishList.aspx` search box uses). `rank` is the DB `irank` — lower is a better match (0 =
  exact) and rows are returned best-first. The term is trimmed and capped at 64 chars
  (`SearchFishList` takes a `varchar(64)`). Blank or missing `q` ⇒ 400 `invalid_document`.

**River / water-body lookups** (added on `RiverController` — calls `dbo.fn_river_unfished_json` /
`dbo.fn_lake_view_json` / `dbo.fn_lake_fishing_json` / `dbo.sp_lake_fish_upsert_batch` /
`dbo.sp_lake_description_update`, all existing in `envfish-db`; see [Data access](#data-access)):

| Verb | Path | Success status | Response `data` |
|------|------|----------------|-----------------|
| `GET` | `/api/v1/river/unfished?country=&state=&river=` | 200 | `{ found, country, state, river, lake_id, lake_name, mouth_name, CGNDB, throwing }` (fields null when `found:false`) |
| `GET` | `/api/v1/river/description/{guid}` | 200 | the full description document (name/alt names, description, stats, source/mouth, fish, base64 photo gallery); 404 if the guid is unknown |
| `GET` | `/api/v1/river/fish/{guid}` | 200 | the assigned-species document (every `lake_fish` row: name, latin, conservation status, last-catch, external link); 404 if the guid is unknown |
| `PATCH` | `/api/v1/river/fish/{guid}` | 200 | one result per input entry, in order: `[{fishId, fishName, action}, …]`, `action` one of `inserted`/`updated`/`skipped`/`unknown_fish`/`invalid_fish_id`; 400 on an invalid body, 404 if the guid is unknown |
| `PATCH` | `/api/v1/river/description/{guid}` | 200 | `{ lakeId, updated:[{field}], ignored:[{field,reason}], protectedFields:[{field,reason}] }`; 400 on an invalid body, 404 if the guid is unknown |

- `GET /api/v1/river/unfished` — the next un-processed water body of a type in a state (no fish
  assigned, not flagged No Fish), a native duplicate of the frontend `Resources/wbUnFish.aspx` endpoint
  used by the add-fish tooling. `throwing` is the comma-joined `CGNDB` of the `side=2` ("Throw")
  tributaries. `country` is echoed only (the query filters by state). Parameter handling mirrors the
  page: a bad `country`/`state` falls back to the default (`CA`/`ON`) and a bad `river` to `2`, so the
  endpoint always answers (no 400s).
- `GET /api/v1/river/description/{guid}` — a native duplicate of the admin "Save JSON" View-tab export
  (`Editor/HandlerImage.ashx?lakejson=<guid>&tab=view`), backed by `dbo.fn_lake_view_json` — already
  live in prod (added 2026-08-14 for the admin Save-JSON tabs), so no new DB object. Unknown/NULL guid
  ⇒ 404, mirroring `/news/export/{id}`. The frontend export path is admin-gated, but the underlying
  content is the same public data anonymous visitors already see on `Resources/wfRiverViewer.aspx` — a
  public docapi GET matches the rest of this service's unauthenticated surface.
- `GET /api/v1/river/fish/{guid}` — a native duplicate of the admin "Save JSON" Fishing-tab export
  (`Editor/EditLakeFish.aspx` → `HandlerImage.ashx?lakejson=<guid>&tab=fishing`), backed by
  `dbo.fn_lake_fishing_json` — already live in prod (same 2026-08-13 rollout as `fn_lake_view_json`),
  so no new DB object. Unknown/NULL guid ⇒ 404. Same public-data reasoning as `description`.
- `PATCH /api/v1/river/fish/{guid}` — the write counterpart, a native duplicate of the "Add" form on
  that same `EditLakeFish.aspx` (`AddFishToLake`). Body: a JSON array of `{fishId, link, trustLevel,
  year, status}` entries (`fishId` required); batch-upserted via the new `dbo.sp_lake_fish_upsert_batch`
  (`envfish-db`, 2026-08-25). Deliberately narrow: a species not yet assigned is `inserted`; one
  assigned but missing its `link` is `updated`; one already assigned **with** a link is `skipped` and
  left untouched — never silently overwritten. `unknown_fish` / `invalid_fish_id` cover a
  well-formed-but-unrecognized guid and a non-guid. Body must be a non-empty JSON array of at most 500
  entries or the request is rejected with 400 `invalid_document` before any SQL runs. This is the
  service's first write path outside the generic document CRUD endpoints, and — unlike every other
  river endpoint until now — is **fronted through cproxy as of 0.6.1**
  (`CPROXY_ALLOWED_METHODS` now includes `PATCH` in `deploy/compose.yml`), gated by a per-day
  rotating credential (`X-Day-Guid` checked against a SQLite-backed `DayKeyStore`), not a static API
  key. Verified live end-to-end through the public gateway.
- `PATCH /api/v1/river/description/{guid}` — a second, independent write: a JSON **merge patch** of
  the `Editor/LakeEditor.aspx` "General" tab's editable fields, via the new
  `dbo.sp_lake_description_update` (`envfish-db`, 2026-08-25). Only keys present in the body are
  touched (an explicit JSON `null` clears a field; an omitted key leaves it alone) — covers every
  field `fn_lake_description_json` exports **except** the identity/linkage fields the same admin page
  shows read-only in this exact spot: `lakeName`, `source`/`sourceId`, `mouth`/`mouthId`. Those are
  reported back as `protectedFields`, never silently dropped or applied. `noFish` is blocked
  (reported `ignored`) while the lake has assigned species, mirroring the page's own client-side
  rule. Body must be a non-empty JSON object of at most 100 keys or 400 `invalid_document` before any
  SQL runs. Fronted through cproxy automatically — the day-key gate (0.6.1) applies to every PATCH
  request, not a specific path; verified live end-to-end through the public gateway.

**Regulation lookups/writes** (added on `RegulationController` — calls `dbo.fn_lake_regulation_json` /
`dbo.fn_region_regulation_json` / `dbo.sp_regulation_upsert`; see [Data access](#data-access)). Covers
two of the three scopes `Editor/LakeRegulation.aspx`'s single "regulation dialog" edits through one
`dbo.regulations` table (water-body and region/country-state; zone-scoped rules have no dedicated
endpoint yet):

| Verb | Path | Success status | Response `data` |
|------|------|----------------|-----------------|
| `GET` | `/api/v1/river/regulation/{guid}` | 200 | this water body's own regulation rows (`{guid, lakeName, regulations:[...]}`); 404 if the guid is unknown |
| `PATCH` | `/api/v1/river/regulation/{guid}` | 200 | `{ id, action, scope }` on success, or `{id:null, action:null, error}` on a validation failure; 400 on a malformed/missing body |
| `GET` | `/api/v1/region/regulation/{country}` | 200 | whole-country rules, no specific state (`{country, state:null, regulations:[...]}`); never 404 — an unrecognized country returns an empty array |
| `GET` | `/api/v1/region/regulation/{country}/{state}` | 200 | province/state-wide rules (`{country, state, regulations:[...]}`); never 404 |
| `PATCH` | `/api/v1/region/regulation/{country}` | 200 | `{ id, action, scope }` / validation-error shape, same as the water-body PATCH |
| `PATCH` | `/api/v1/region/regulation/{country}/{state}` | 200 | `{ id, action, scope }` / validation-error shape, same as the water-body PATCH |

- **There is no separate INSERT verb.** Every PATCH above upserts by identity
  (`country`/`state`/`zoneId`/`lakeId`/`fishId`/`year`/`part`/`residentType` — the columns behind
  `dbo.regulations`' two filtered unique indexes): a body matching nothing existing inserts
  (`action:"inserted"`), one matching an existing row updates it in place (`action:"updated"`). A
  dedicated `POST` was deliberately skipped — cproxy's write surface only admits `GET`/`PATCH` (the
  day-key gate is verb-based, not path-based), so this reuses the fish/description endpoints'
  upsert-on-PATCH pattern and ships with **no cproxy change**.
- **Scope is inferred, not declared.** `lakeId` set → water-body rule; `zoneId` set (no `lakeId`) →
  zone rule; neither → region rule (whole-country when `state` is omitted, else province/state-wide).
  `zoneId` and `lakeId` are mutually exclusive — a body setting both is rejected.
- **The identifying fields always come from the URL, never the body.** `PATCH /river/regulation/{guid}`
  sets `lakeId` from the path and strips any `zoneId`/conflicting `lakeId` out of the body before it
  reaches SQL; `PATCH /region/regulation/{country}[/{state}]` sets `country`/`state` from the path and
  strips `zoneId`/`lakeId`. A caller can't accidentally write to a different scope than the route they
  called.
- **Country/state path segments are validated, not defaulted.** Unlike `/river/unfished`'s
  best-effort `country`/`state` query params (which fall back silently), a non-two-letter `country` or
  `state` **path** segment on any regulation route is 400 `invalid_document` — these identify which
  resource is being read/written, so a typo should fail loudly rather than silently reading/writing
  the wrong scope.
- **Validation failures are a 200 with an inline `error`, not a 4xx** — same contract as
  `sp_lake_description_update`'s malformed-JSON path: `{id:null, action:null, error:"..."}`. Missing
  `year`, an unknown `lakeId`/`fishId`, or `zoneId`+`lakeId` both set all take this shape.
- `dbo.TR_regulations` (`FOR INSERT`) auto-adds the row to `lake_fish` when a new water-body rule also
  carries a `fishId` not yet assigned to that lake — the same side effect the ASPX page's own INSERT
  triggers. Silent from this endpoint's point of view, same as it is in the UI.

**Fish Latin-name lookups** (fish only, on the `FishController` base path — call
`dbo.fn_fish_code_latin_json` / `dbo.fn_fish_latin_json`, which already exist in `envfish-db`):

| Verb | Path | Success status | Response `data` |
|------|------|----------------|-----------------|
| `GET` | `/api/v1/fish?province=&codes=&country=` | 200 | `[{ code, latin }]` — one element per match, in requested order |
| `GET` | `/api/v1/fish?fishes=` | 200 | `[{ query, name, latin }]` — one element per requested name, in order |

Both live on `GET` of the base path and are told apart by which parameter is present; `fishes` wins if
both are supplied. The path is free because `/{id}` and `/search` are more specific. They mirror the
portal's `/WebService/Fish/` endpoint.

- `GET /api/v1/fish?province=AB&codes=BURB,WALL` — regional fish code → Latin name for one province,
  backed by `dbo.fn_fish_code_latin_json(@country, @state, @codes)`. **`province` is required whenever
  `codes` are supplied** — `dbo.fish_code` is keyed on country+state+code, so a bare code has no meaning
  and the same code names different species in different provinces; omitting it ⇒ 400
  `invalid_document`. With no `codes` the **whole province** is published, ordered by code. `country` is
  optional and defaults to any (only `CA` exists today, but country is part of the key).
  **One element per match, not per requested code**: a code may legitimately name several species — on
  the live database BC `RB` is both Rock Bass and Rainbow Trout, `LS` both Lake Sturgeon and Largescale
  Sucker — so an ambiguous code returns several elements sharing the code rather than an arbitrary
  single winner. A code matching nothing still yields exactly one element with `latin` null, so the
  array never silently shrinks relative to the request. An **unknown province is not an error**: the
  codes come back unresolved, which cannot be mistaken for a larger result set. `code` echoes the
  requested spelling; matching is exact and case-insensitive by DB collation.

- `GET /api/v1/fish?fishes=Walleye,Burbot` — batch common name → Latin name, backed by
  `dbo.fn_fish_latin_json(@names)`. One element per requested name **in the requested order**, `query`
  echoing the caller's spelling so the response can be zipped back against the request. An unresolved
  name **keeps its slot** with null `name`/`latin`; dropping it would shift every later element and
  mis-pair everything after the first miss. Matching is a substring of the common or Latin name, so
  `Walley` resolves to `Walleye`.

**List parsing (both parameters).** Accepts `{…}` / `[…]` wrappers, comma or semicolon separators,
quoted items, and repeated parameters. The rule: **more than one value means the parameter was
repeated**, and each value is one entry verbatim; **exactly one value is split**, honouring quotes.
This matters because **762 of the 1041 species names contain a comma** ("Bass, Guadalupe",
"Dace, Longnose") — so `"Bass, Guadalupe",Burbot` and `?fishes=Bass, Guadalupe&fishes=Burbot` both
yield two entries. The values are read with `HttpServletRequest.getParameterValues`, **not**
`@RequestParam List<String>`, because Spring splits the latter on commas and would tear most of the
catalogue in half. Blank entries are dropped; a batch over 100 entries ⇒ 400 `invalid_document`.

- `GET /api/v1/news/list` — one page of the latest news, backed by `dbo.fn_news_list(@country,
  @offset, @fetch)`. `country` is an optional ISO-2 code (blank/absent ⇒ all countries; a non-CA
  country with fewer than 100 items is padded with the latest Canadian news up to 100, marked
  `blockOrd = 1`). `offset` defaults to 0 (clamped ≥ 0); `limit` defaults to **25** (capped at 200).
  `total` is the full filtered+padded row count (windowed `COUNT(*) OVER()`), so a numbered pager
  needs no second query. A non-2-letter `country` ⇒ 400 `invalid_document`.
- `GET /api/v1/news/default` — the home page, backed by `dbo.fn_default_news_ids()` +
  `dbo.fn_default_news_json(@news_id, @with_photo)`: the ids/slot-flag/order come from the first
  function, each item's JSON document from the second, in display order (two lead articles first,
  then three right-column items). The literal `/list` and `/default` paths are matched ahead of the
  templated `/{id}` document fetch. Both run with the default in-memory backing too, returning empty
  results (no DB), and are guarded by the same Resilience4j retry/breaker as the document reads.

**Interchange export / import** (news only, `fn_news_json` format — the self-contained JSON the portal
News.aspx "Save JSON" link and `AddNews.aspx` "Import from JSON" round-trip use):

| Verb | Path | Success status | Response `data` |
|------|------|----------------|-----------------|
| `GET`  | `/api/v1/news/export/{id}` | 200 | the full interchange document (nested JSON) |
| `POST` | `/api/v1/news/import`      | 201 | `{ "id": <newId> }` |

- **Only these two endpoints carry the FULL document** — every field plus all three paragraph photos
  embedded as **base64**; the `/{id}`, `/list`, `/default` endpoints above keep their existing lighter
  shapes and amount.
- `GET /api/v1/news/export/{id}` — backed by `dbo.fn_news_json(@id)`; `NULL` ⇒ 404. The literal
  `/export/…` prefix is matched ahead of the templated `/{id}` fetch. Read straight through the news
  cache (not cached — large per-id payload).
- `POST /api/v1/news/import` — backed by `dbo.sp_news_import(@json)`: creates a **published** article
  from an `fn_news_json` body (base64 photos decoded to binary; `lake_id`/`fish1..3` accept a GUID
  string or null), returns the new id. Blank/malformed body ⇒ 400 `invalid_document`. `news_title` is
  UNIQUE, so importing an existing title raises the duplicate-key error. Importing evicts the news
  cache (lists + home page) so the new article shows up immediately.
- Both run with the default in-memory backing too (export ⇒ 404, import ⇒ a synthetic id), and are
  guarded by the same Resilience4j retry/breaker as the document reads.

All non-health responses use the envelope `{ data, error, meta }` where `meta` carries a
`timestamp`. Exactly one of `data` / `error` is populated.

## Required files (complete list)

```
pom.xml
Dockerfile
.dockerignore
.gitignore
.env.example
README.md
CLAUDE.md
docs/specification.md
src/main/java/com/fishfind/docapi/DocApiApplication.java
src/main/java/com/fishfind/docapi/config/DotenvEnvironmentPostProcessor.java
src/main/java/com/fishfind/docapi/config/InMemoryStoreConfig.java
src/main/java/com/fishfind/docapi/config/JdbcStoreConfig.java
src/main/java/com/fishfind/docapi/domain/DocumentType.java
src/main/java/com/fishfind/docapi/repo/DocumentStore.java
src/main/java/com/fishfind/docapi/repo/InMemoryDocumentStore.java
src/main/java/com/fishfind/docapi/repo/JdbcDocumentRepository.java
src/main/java/com/fishfind/docapi/repo/NewsDocumentRepository.java
src/main/java/com/fishfind/docapi/repo/WaterbodyDocumentRepository.java
src/main/java/com/fishfind/docapi/repo/FishDocumentRepository.java
src/main/java/com/fishfind/docapi/repo/StationDocumentRepository.java
src/main/java/com/fishfind/docapi/repo/NewsQueryRepository.java
src/main/java/com/fishfind/docapi/repo/InMemoryNewsQueryRepository.java
src/main/java/com/fishfind/docapi/repo/JdbcNewsQueryRepository.java
src/main/java/com/fishfind/docapi/repo/FishQueryRepository.java
src/main/java/com/fishfind/docapi/repo/InMemoryFishQueryRepository.java
src/main/java/com/fishfind/docapi/repo/JdbcFishQueryRepository.java
src/main/java/com/fishfind/docapi/repo/RiverQueryRepository.java
src/main/java/com/fishfind/docapi/repo/InMemoryRiverQueryRepository.java
src/main/java/com/fishfind/docapi/repo/JdbcRiverQueryRepository.java
src/main/java/com/fishfind/docapi/repo/RiverFishCommandRepository.java
src/main/java/com/fishfind/docapi/repo/InMemoryRiverFishCommandRepository.java
src/main/java/com/fishfind/docapi/repo/JdbcRiverFishCommandRepository.java
src/main/java/com/fishfind/docapi/repo/RiverDescriptionCommandRepository.java
src/main/java/com/fishfind/docapi/repo/InMemoryRiverDescriptionCommandRepository.java
src/main/java/com/fishfind/docapi/repo/JdbcRiverDescriptionCommandRepository.java
src/main/java/com/fishfind/docapi/repo/RegulationQueryRepository.java
src/main/java/com/fishfind/docapi/repo/InMemoryRegulationQueryRepository.java
src/main/java/com/fishfind/docapi/repo/JdbcRegulationQueryRepository.java
src/main/java/com/fishfind/docapi/repo/RegulationCommandRepository.java
src/main/java/com/fishfind/docapi/repo/InMemoryRegulationCommandRepository.java
src/main/java/com/fishfind/docapi/repo/JdbcRegulationCommandRepository.java
src/main/java/com/fishfind/docapi/service/DocumentService.java
src/main/java/com/fishfind/docapi/service/NewsDocumentService.java
src/main/java/com/fishfind/docapi/service/WaterbodyDocumentService.java
src/main/java/com/fishfind/docapi/service/FishDocumentService.java
src/main/java/com/fishfind/docapi/service/StationDocumentService.java
src/main/java/com/fishfind/docapi/service/DocumentNotFoundException.java
src/main/java/com/fishfind/docapi/service/InvalidDocumentException.java
src/main/java/com/fishfind/docapi/web/AbstractDocumentController.java
src/main/java/com/fishfind/docapi/web/NewsController.java
src/main/java/com/fishfind/docapi/web/WaterbodyController.java
src/main/java/com/fishfind/docapi/web/FishController.java
src/main/java/com/fishfind/docapi/web/StationController.java
src/main/java/com/fishfind/docapi/web/RiverController.java
src/main/java/com/fishfind/docapi/web/RegulationController.java
src/main/java/com/fishfind/docapi/web/HealthController.java
src/main/java/com/fishfind/docapi/web/ApiResponse.java
src/main/java/com/fishfind/docapi/web/ApiExceptionHandler.java
src/main/resources/application.yml
src/main/resources/application-jdbc.yml
src/main/resources/logback-spring.xml
src/main/resources/META-INF/spring/org.springframework.boot.env.EnvironmentPostProcessor.imports
src/test/java/com/fishfind/docapi/DocApiApplicationTest.java
src/test/java/com/fishfind/docapi/DocApiContextTest.java
src/test/java/com/fishfind/docapi/DocApiJdbcWiringTest.java
src/test/java/com/fishfind/docapi/repo/NewsDocumentRepositoryTest.java
src/test/java/com/fishfind/docapi/service/DocumentServiceTest.java
src/test/java/com/fishfind/docapi/web/DocumentRoundTripTest.java
src/test/java/com/fishfind/docapi/web/HealthControllerTest.java
src/test/java/com/fishfind/docapi/web/NewsControllerTest.java
src/test/resources/application-test.yml
src/test/resources/application.properties
```

**Never include:** a real `.env`, secrets, or `.env` under `src/main/resources`.

## Dependencies (pom.xml)

Parent `spring-boot-starter-parent` 3.3.13; `java.version` 21; `mssql-jdbc.version` overridden to
`12.8.1.jre11`.

- `spring-boot-starter`, `spring-boot-starter-web`, `spring-boot-starter-jdbc`,
  `spring-boot-starter-aop`, `spring-boot-starter-actuator`
- `micrometer-registry-prometheus` (runtime)
- `resilience4j-spring-boot3` 2.2.0
- `mssql-jdbc`
- `dotenv-java` 3.2.0
- `slf4j-api`, `logback-classic`, `logstash-logback-encoder` 7.4
- test: `spring-boot-starter-test`, `h2`, `mockito-inline` 5.2.0

Build plugin `spring-boot-maven-plugin` with the `build-info` goal (so `/health` version tracks the
pom). `security` profile runs OWASP `dependency-check-maven` 12.2.2 (fail on CVSS ≥ 7), out of the
default lifecycle. (No `commons-csv` — there is no CSV parsing in this service.)

## Startup / credential loading

Identical to `waterservice`: `DotenvEnvironmentPostProcessor` (registered in the
`EnvironmentPostProcessor.imports` file) loads `.env` (default project root; override with
`DOTENV_PATH`) as the **lowest-precedence** property source (`addLast`), importing only
`DECLARED_IN_ENV_FILE` keys. Real env vars / system properties always win. Credentials are never
copied into JVM-global system properties. `main()` only calls `SpringApplication.run`.

## Profiles / storage backends

Storage is behind the `DocumentStore` interface, chosen by Spring profile. Additionally,
`NewsQueryRepository`, `FishQueryRepository`, and `RiverQueryRepository` each have two implementations
registered per profile:

- **default (no profile)** — `InMemoryStoreConfig` (`@Profile("!jdbc")`) registers four
  `InMemoryDocumentStore` beans (`newsStore`, `waterbodyStore`, `fishStore`, `stationStore`), one
  `InMemoryNewsQueryRepository` bean, one `InMemoryFishQueryRepository` bean, and one
  `InMemoryRiverQueryRepository` bean. No DB. `application.yml` sets `spring.autoconfigure.exclude`
  to `DataSourceAutoConfiguration`, `DataSourceTransactionManagerAutoConfiguration`,
  `JdbcTemplateAutoConfiguration`, and disables the actuator `db` health indicator (readiness group =
  `readinessState` only).
- **`jdbc` profile** — `JdbcStoreConfig` (`@Profile("jdbc")`) registers four `JdbcDocumentRepository`
  beans under the **same names**, each taking the shared `JdbcTemplate`, one `JdbcNewsQueryRepository`
  bean, one `JdbcFishQueryRepository` bean, and one `JdbcRiverQueryRepository` bean.
  `application-jdbc.yml` clears the auto-configure
  exclusion, configures the datasource, and re-enables the `db` health indicator + readiness `db` group.

Because both configs use the same bean names, each service/controller injects by name/qualifier
and is agnostic to the active profile.

### Datasource (`application-jdbc.yml`, jdbc profile only)

```yaml
spring:
  autoconfigure:
    exclude:                 # clears the default profile's exclusion
  datasource:
    url: ${DB_URL}
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}
    driver-class-name: com.microsoft.sqlserver.jdbc.SQLServerDriver
    hikari:
      pool-name: docapi-hikari
      maximum-pool-size: 8
      minimum-idle: 2
      connection-timeout: 30000
      max-lifetime: 1740000   # 29 min
      keepalive-time: 300000  # 5 min
      validation-timeout: 5000
```

## Data access

### `DocumentStore` (interface)

`String getDocument(String id)` (null when absent), `String addDocument(String json)` (returns new id),
`String updateDocument(String id, String json)` (returns affected id). Two implementations follow.

### `InMemoryDocumentStore implements DocumentStore` (default backing)

Constructor `(DocumentType type)`. Thread-safe `ConcurrentHashMap<String,String>` + `AtomicLong`
sequence. `getDocument` → map lookup (null if absent). `addDocument` → id `<label>-<n>` (e.g.
`news-1`), store, return id. `updateDocument` → put under the given id (PUT semantics, creates if
absent), return id. Process-local; contents lost on restart.

### `JdbcDocumentRepository implements DocumentStore` (abstract, jdbc profile)

Constructor: `(JdbcTemplate jdbc, DocumentType type, String getSql, String addSql, String updateSql)`.
Methods (each `@Retry("sqlRetry")` + `@CircuitBreaker("sqlBreaker", fallback…)`):

- `String getDocument(String id)` — `jdbc.query(getSql, ps->ps.setString(1,id), (rs,i)->rs.getString(1))`;
  returns the single scalar or `null` when no row.
- `String addDocument(String json)` — executes `addSql` (`?` = json) and returns the first scalar of
  the first result set (draining remaining results/update counts), or `null`.
- `String updateDocument(String id, String json)` — executes `updateSql` (`?,?` = id, json), same
  scalar-capture semantics.

`executeReturningScalar` uses `jdbc.execute(sql, PreparedStatementCallback)`: bind params, `execute()`,
capture the first column of the first row of the first result set, then loop `getMoreResults` /
`getUpdateCount` to drain everything so the driver completes cleanly. Fallbacks (`readFallback`,
`addFallback`, `updateFallback`) rethrow as `RuntimeException`.

The id is passed as a **string**; SQL Server converts it to the column's real key type.

### Concrete repositories

Plain classes extending `JdbcDocumentRepository` (instantiated by `JdbcStoreConfig`, not
component-scanned). Each supplies its three SQL strings as `static final` constants:

| Repository | get | add | update |
|------------|-----|-----|--------|
| `NewsDocumentRepository` | `SELECT dbo.fn_news_doc(?)` | `EXEC dbo.sp_news_doc_add ?` | `EXEC dbo.sp_news_doc_update ?, ?` |
| `WaterbodyDocumentRepository` | `SELECT dbo.fn_waterbody_doc(?)` | `EXEC dbo.sp_waterbody_doc_add ?` | `EXEC dbo.sp_waterbody_doc_update ?, ?` |
| `FishDocumentRepository` | `SELECT dbo.fn_fish_doc(?)` | `EXEC dbo.sp_fish_doc_add ?` | `EXEC dbo.sp_fish_doc_update ?, ?` |
| `StationDocumentRepository` | `SELECT dbo.fn_station_doc(?)` | `EXEC dbo.sp_station_doc_add ?` | `EXEC dbo.sp_station_doc_update ?, ?` |

**These DB objects are not created yet** (this pass is the Java service only). Contract:
`fn_<entity>_doc(@id)` returns the document JSON (or NULL); `sp_<entity>_doc_add(@json)` inserts and
returns the new id; `sp_<entity>_doc_update(@id,@json)` updates and returns the id.
`waterbody` = `dbo.lake`. The `fish` doc objects are distinct from the existing
`dbo.fn_fish_document` / `dbo.sp_add_fish_document` (a PDF blob).

### News-page query repository (`NewsQueryRepository`)

The two News-page read queries are delegated to `NewsQueryRepository` — a separate abstraction from
the document-store pattern, following the repository pattern established in the codebase. Two
implementations exist:

- **`InMemoryNewsQueryRepository`** (default profile) — returns empty results; no database access.
- **`JdbcNewsQueryRepository`** (jdbc profile) — calls functions that **exist** in `envfish-db`
  (`mssql/script02_Funct.sql`, covered by `UNIT_TESTS/unit_test@DefaultNews.sql`), reading through
  functions only — never base tables. Both methods carry `@Retry("sqlRetry")` + `@CircuitBreaker("sqlBreaker")`
  with fallbacks.

| Query | SQL | Returns |
|-------|-----|---------|
| latest-news page | `SELECT rn, news_id, title, source, stamp, flag, has_photo, block_ord, total FROM dbo.fn_news_list(?, ?, ?) ORDER BY rn` | one page of rows + windowed `total` |
| home page | `SELECT dbo.fn_default_news_json(news_id, with_photo) FROM dbo.fn_default_news_ids() ORDER BY ord` | one JSON document per home item, in display order |
| interchange export | `SELECT dbo.fn_news_json(?)` | the full interchange doc (all fields + 3 base64 photos), or `NULL` ⇒ 404 |
| interchange import | `EXEC dbo.sp_news_import ?` | creates a published article from an `fn_news_json` body, returns the new id |

**Interface:**

- `NewsListPage list(String country, int offset, int limit)` — `country` NULL ⇒ all countries;
  an ISO-2 code filters to it, and a **non-CA** country with fewer than 100 published items is
  padded with the latest Canadian news up to 100 (`blockOrd = 1`). Modern `OFFSET/FETCH` paging
  with a windowed `COUNT(*) OVER()` `total`. Returns `NewsListPage` with items list and paging metadata.
- `JsonNode defaultNews()` — returns `{ "items": [ <news>, … ] }` in display order (2 lead articles
  first, then 3 right-column items), each the per-item JSON document. With no JDBC backing
  (default profile), returns `{ "items": [] }`.
- `JsonNode exportNews(String id)` — the full `fn_news_json` interchange document for one article
  (every field + all 3 base64 photos), or `null` ⇒ 404. Only export/import carry this full shape;
  the other queries keep their existing amount. In-memory profile returns `null`.
- `String importNews(String json)` — creates a **published** article from an `fn_news_json` body
  (`dbo.sp_news_import`, base64 photos decoded to binary) and returns the new id. In-memory profile
  returns a synthetic id. The caching decorator (`NewsQueryCache`) reads `exportNews` straight
  through (not cached) and **evicts the cached lists + home page on `importNews`**.

**SQL details:**

- `dbo.fn_news_list(@country, @offset, @fetch)` — `@country` NULL ⇒ all countries; an ISO-2 code
  filters to it, and a **non-CA** country with fewer than 100 published items is padded with the
  latest Canadian news up to 100 (`block_ord = 1`). Modern `OFFSET/FETCH` paging with windowed
  `COUNT(*) OVER()` `total`.
- `dbo.fn_news_search(@q)` — up to 100 published articles, newest first, matching `@q` over one
  concatenation of headline, source, the 3 paragraphs, the 3 photo alts, and the up-to-3 mentioned
  fishes' common/latin/alt names (news `LEFT JOIN fish ×3`). Published-only; matched as
  `LIKE N'%'+@q+N'%' ESCAPE '\'` with the **caller** escaping `% _ [` (`JdbcNewsQueryRepository.escapeLike`);
  NULL/empty ⇒ latest 100. The repo projects `news_id, news_title, news_source, stamp, country,
  fish1/2/3` into `NewsSearchItem` (fishes de-duped). Not cached (`NewsQueryCache.search` reads through).
- `dbo.fn_default_news_ids()` — the home-page ids with `with_photo` (1 = lead/photo slot, 2 leads;
  0 = right column) and `ord` (1-based display position). `dbo.fn_default_news_json(@news_id,
  @with_photo)` — the per-item JSON document (info + base64 photo for a lead; compact for a
  right-column item).
- `dbo.fn_news_json(@news_id)` — the **full interchange document**: title, author, author/source
  links, source, video link, all 3 paragraphs, country, date, `lakeId`, `fish1/2/3Id`, and the 3
  paragraph photos embedded as base64 with each photo's author/alt. `NULL` for an unknown id. The
  same shape the portal's News.aspx "Save JSON" / AddNews "Import from JSON" round-trip uses.
- `dbo.sp_news_import(@json)` — inserts one article from an `fn_news_json` body (base64 photos decoded
  via `xs:base64Binary`; `lake_id`/`fish1..3` via `TRY_CONVERT`, bad text ⇒ null), `news_publish = 1`,
  absent date ⇒ now, and returns the new `news_id`. Added test-first in `envfish-db`
  (`UNIT_TESTS/unit_test@NewsImport.sql`, 4 tests incl. a fn_news_json export→import round-trip).

### Fish-catalogue query repository (`FishQueryRepository`)

The fish search query is delegated to `FishQueryRepository`, the same repository pattern as
`NewsQueryRepository`. Two implementations:

- **`InMemoryFishQueryRepository`** (default profile) — returns empty results; no database access.
- **`JdbcFishQueryRepository`** (jdbc profile) — calls `dbo.SearchFishList`, which **already exists**
  in `envfish-db` (`mssql/script02_Funct.sql`, covered by `UNIT_TESTS/unit_test@SearchFish.sql`) and
  backs the Editor `FishList.aspx` search box — so no new DB object was needed. Carries
  `@Retry("sqlRetry")` + `@CircuitBreaker("sqlBreaker")` with a fallback.

| Query | SQL | Returns |
|-------|-----|---------|
| species search | `SELECT fish_name, fish_latin, fish_id, irank FROM dbo.SearchFishList(?) ORDER BY irank ASC` | best-match-first species rows |

**Interface:** `FishSearchPage search(String query)` — returns `FishSearchItem` rows
`(fishId, name, latin, rank)` where `rank` is the DB `irank` (lower is better, 0 = exact).

**SQL details:** `dbo.SearchFishList(@search varchar(64))` is a multi-statement TVF that **normalizes
the term itself** (`dbo.NormalizeSearch`) and matches it against `fish_name`, `fish_latin`, and the
`;`-delimited `alt_name` synonyms, assigning `irank` (0 = exact name/latin, then synonym, then
substring). Because it normalizes and builds its own match variants, the Java layer binds the raw
(trimmed, ≤64-char) term as a plain parameter with **no LIKE-escaping**. Returns
`num, fish_name, name, fish_latin, fish_id, irank`; the repo projects `fish_name → name`,
`fish_latin → latin`, `fish_id → fishId`, `irank → rank`. **Not cached** (open-ended search key), so —
unlike `/news/list` — there is no cache decorator and no `@Primary`: just the one proxied bean per
profile.

### River query repository (`RiverQueryRepository`)

The river lookups are delegated to `RiverQueryRepository`, same pattern. Two implementations:

- **`InMemoryRiverQueryRepository`** (default profile) — `unfished` returns `{ found:false, country,
  state, river }`; `description` returns `null` (→ 404). No database access.
- **`JdbcRiverQueryRepository`** (jdbc profile) — `unfished` calls `dbo.fn_river_unfished_json`, added
  in `envfish-db` (`mssql/script02_Funct.sql`, `UNIT_TESTS/unit_test@RiverUnfished.sql`, 4 tests);
  `description` calls `dbo.fn_lake_view_json`, already live in `envfish-db` for the admin Save-JSON
  tabs (no new DB object for this endpoint). Both carry `@Retry("sqlRetry")` +
  `@CircuitBreaker("sqlBreaker")` with a fallback.

| Query | SQL | Returns |
|-------|-----|---------|
| next un-processed water body | `SELECT dbo.fn_river_unfished_json(?, ?, ?)` | one JSON object, parsed to `JsonNode` |
| water-body description | `SELECT dbo.fn_lake_view_json(?)` | one JSON object, parsed to `JsonNode`, or `null` if the function returns NULL/blank |

**Interface:** `JsonNode unfished(String country, String state, int river)` and
`JsonNode description(String lakeId)`.

**SQL details — `unfished`:** `dbo.fn_river_unfished_json(@country char(2), @state char(2), @river
int)` returns the whole document: a `TOP 1 … FROM dbo.vw_lake WHERE @state IN (source_state,
mouth_state) AND locType = @river AND ISNULL(isFish,0)=0 AND ISNULL(noFish,0)=0 ORDER BY lake_name`
(mirroring `wbUnFish.aspx`), plus `throwing` = `STRING_AGG(CGNDB, ',')` of the `dbo.Tributaries side=2`
rows joined to `dbo.Lake`. The raw-table access lives inside the function (per the no-raw-table rule);
the Java layer just parses the returned JSON. The controller cleans the parameters (bad
`country`/`state`→default, bad `river`→2) before the call.

**SQL details — `description`:** `dbo.fn_lake_view_json(@lake_id uniqueidentifier)` returns
`{ guid, lakeName, altName, nativeName, french, type, description, link, cgndb, basin, watershield,
drainage, discharge, length_km, width_km, maxDepth_m, volume_km3, surface_km2, shoreline_km,
sourceName, sourceId, sourceLat, sourceLon, …, mouthName, …, fish[], photos[] }` (assigned fish +
base64 photo gallery included) or `NULL` for an unknown/`Guid.Empty` id. The controller passes the
path `{guid}` straight through as a string — SQL Server converts it, so a malformed (non-GUID) value
fails the same way it does on the analogous `/news/{id}` doc-CRUD route (a conversion error, not a
client-side 400).

Both queries are **not cached** — one proxied bean per profile.

## Service layer

### `DocumentService` (abstract)

Constructor `(DocumentStore store, ObjectMapper, DocumentType)`.

- `JsonNode get(String id)` — validate id non-blank; `store.getDocument`; null/blank ⇒
  `DocumentNotFoundException`; else parse stored JSON with `objectMapper.readTree` (a parse failure
  here is `IllegalStateException`, a server-side data problem → 500).
- `String add(String rawBody)` — `requireValidJson` (blank or malformed ⇒ `InvalidDocumentException`),
  store the **normalized** `node.toString()`, log, return new id.
- `String update(String id, String rawBody)` — validate id + body, update with normalized body, return
  the store's id or the supplied id if null.

### Concrete services (`@Service`)

`NewsDocumentService`, `WaterbodyDocumentService`, `FishDocumentService`, `StationDocumentService` —
each injects its store via `@Qualifier("<entity>Store") DocumentStore` plus `ObjectMapper`, passing
them with the `DocumentType` to `super(...)`.

### Exceptions

- `DocumentNotFoundException(DocumentType, id)` → HTTP 404.
- `InvalidDocumentException(message[, cause])` → HTTP 400.

## Web layer

### `ApiResponse<T>` (record)

`(T data, ApiError error, Map<String,Object> meta)`; nested `ApiError(String code, String message)`.
Factories `ok(data)` and `fail(code, message)`; `meta` always carries `timestamp`
(`OffsetDateTime.now()`). Note: the private meta-builder is named `newMeta()` — it must **not** be
named `meta()` (that would collide with the record's component accessor).

### `AbstractDocumentController`

Constructor `(DocumentService, ObjectMapper)`.

- `@GetMapping("/{id}")` → `ApiResponse.ok(service.get(id))`.
- `@PostMapping(consumes=JSON)` `@ResponseStatus(CREATED)` → `service.add(body)`, return
  `ok({id})`.
- `@PutMapping(value="/{id}", consumes=JSON)` → `service.update(id, body)`, return `ok({id})`.

Body is `@RequestBody(required=false) String` so the service controls JSON parsing/validation rather
than binding a fixed DTO. `idNode` builds `{ "id": … }` via the injected `ObjectMapper`.

### Concrete controllers (`@RestController`)

`NewsController`/`WaterbodyController`/`FishController`/`StationController`, each
`@RequestMapping(value="/api/v1/<entity>", produces=JSON)`, constructor injecting the entity service
+ `ObjectMapper` into `super(...)`. `RiverController` (`/api/v1/river`) is a **standalone**
`@RestController` (no document CRUD) that injects only `RiverQueryRepository` and adds
`@GetMapping("/unfished")` — cleaning `country`/`state`/`river` (defaults on bad input) before
delegating.

`NewsController` additionally injects `NewsQueryRepository` and adds the two News-page read queries
as delegations to the repository:

- `@GetMapping("/list")` `list(country, offset, limit)` — normalizes/clamps params (a non-2-letter
  `country` ⇒ `InvalidDocumentException` → 400), then delegates to
  `queryRepository.list(normalizedCountry, safeOffset, safeLimit)`. The repository handles SQL
  execution (JDBC profile) or returns empty results (default profile).
- `@GetMapping("/default")` `defaultNews()` — delegates to `queryRepository.defaultNews()`,
  returning `{ "items": […] }` per the repository implementation.
- `@GetMapping("/export/{id}")` `export(id)` — `queryRepository.exportNews(id)`; a `null` result ⇒
  `DocumentNotFoundException` → 404, otherwise the full interchange document in the envelope.
- `@PostMapping(value="/import", consumes=JSON)` `@ResponseStatus(CREATED)` `importNews(body)` —
  rejects a blank/malformed body with `InvalidDocumentException` → 400 (validated via the injected
  `ObjectMapper`), then `queryRepository.importNews(body)`, returning `ok({ id })`.

The literal `/list`, `/default`, `/export/…`, and `/import` paths win over the inherited templated
`/{id}`. Resilience4j decorators (`@Retry` / `@CircuitBreaker`) live on the repository methods, not the
controller. `NewsController` stores the `ObjectMapper` (in addition to passing it to `super`) to
validate the import body and build the `{ id }` node.

`FishController` similarly injects `FishQueryRepository` and adds one search query:

- `@GetMapping("/search")` `search(q)` — rejects a blank/missing `q` with `InvalidDocumentException`
  → 400, trims it and caps it at 64 chars, then delegates to `queryRepository.search(term)`. The
  literal `/search` path wins over the inherited `/{id}`. The repository handles SQL execution (JDBC
  profile) or returns empty results (default profile).

`RegulationController` (`@RequestMapping("/api/v1")`, method-level full paths since its two resource
families — `/river/regulation/…` and `/region/regulation/…` — don't share a base) injects
`RegulationQueryRepository` + `RegulationCommandRepository` + `ObjectMapper`:

- `@GetMapping("/river/regulation/{guid}")` — `queryRepository.lakeRegulation(guid)`; `null` ⇒
  `DocumentNotFoundException` → 404.
- `@PatchMapping("/river/regulation/{guid}")` — parses the body to a mutable `ObjectNode`
  (`InvalidDocumentException` if missing/blank/non-object → 400), sets `lakeId` from the path
  (overriding anything the caller sent) and removes `zoneId`, then `commandRepository.upsert(...)`.
- `@GetMapping("/region/regulation/{country}")` / `@GetMapping("/region/regulation/{country}/{state}")`
  — two overloads (Spring has no optional path variable); each validates its code(s) are exactly two
  letters (`InvalidDocumentException` → 400, no silent fallback — these identify the resource) then
  `queryRepository.region(country, state-or-null)`.
- `@PatchMapping("/region/regulation/{country}")` / `.../{country}/{state}` — same `ObjectNode`
  pattern: sets `country` (and `state`, for the two-segment route) from the path, strips
  `state`/`zoneId`/`lakeId` (single-segment route) or `zoneId`/`lakeId` (two-segment route) out of the
  body, then `commandRepository.upsert(...)`.

No dedicated `POST`/insert endpoint: every PATCH above upserts by identity inside
`sp_regulation_upsert` — matching nothing existing inserts, matching an existing row updates it. This
keeps the whole feature on cproxy's existing `GET`/`PATCH`-only allow-list.

### `HealthController`

`GET /health` → `{ status:"UP", version, uptime }`; version from `@Nullable BuildProperties`
(fallback `"unknown"`); uptime from `ManagementFactory` start time.

### `ApiExceptionHandler` (`@RestControllerAdvice`)

- `DocumentNotFoundException` → 404 `fail("not_found", …)`.
- `InvalidDocumentException` / `HttpMessageNotReadableException` → 400 `fail("invalid_document", …)`.
- `Exception` → log error, 500 `fail("internal_error", "An unexpected error occurred")` (no internal
  details leaked).

## Resilience4j (`application.yml`)

```yaml
resilience4j:
  retry:
    retry-aspect-order: 1
    instances:
      sqlRetry: { max-attempts: 3, wait-duration: 2s,
                  retry-exceptions: [org.springframework.dao.DataAccessException, java.sql.SQLException] }
  circuitbreaker:
    circuit-breaker-aspect-order: 2   # outermost, wraps Retry
    instances:
      sqlBreaker: { sliding-window-size: 10, minimum-number-of-calls: 5,
                    failure-rate-threshold: 50, wait-duration-in-open-state: 30s }
```

No HTTP-feed retry/breakers (this service makes no upstream HTTP calls).

## Logging (`logback-spring.xml`)

JSON via `net.logstash.logback.encoder.LogstashEncoder`, `customFields {"service":"docapi"}`,
`timestamp` field renamed, logback `version` field ignored. Console appender + rolling file appender
(`logs/docapi.log`, daily pattern, `maxHistory 7`). `com.fishfind.docapi` and root at INFO.

## Observability & ops (`application.yml`)

`management.server.port: 8082` (private — never exposed publicly). Exposed web endpoints only
`health,info,prometheus,metrics`. `health.show-details: never`; probes enabled with groups
`liveness: livenessState` and `readiness: readinessState,db`; `health.db.enabled: true`. `/health`
on 8080 is the lightweight external/HEALTHCHECK probe.

## Docker

Multi-stage: `maven:3.9.9-eclipse-temurin-21` (pinned by digest) builds with `mvn -B -DskipTests
package`; runtime `eclipse-temurin:21-jre` (pinned by digest) copies `target/docapi-1.0.0.jar` to
`/app/docapi.jar`. Installs `wget` (Temurin JRE has none) for the HEALTHCHECK. Non-root
`USER 10001:10001`; `/app/logs` pre-created and owned by that user (read-only-rootfs friendly).
`EXPOSE 8080`; `HEALTHCHECK wget -qO- http://localhost:8080/health`;
`ENTRYPOINT sh -c "java $JAVA_OPTS -jar /app/docapi.jar"`. `.dockerignore` excludes `.env`, secrets,
build artifacts. Never bake a real `.env` into the image.

## Tests

`mvn test` runs 111 tests, none requiring a database:

- `DocApiApplicationTest` — mocks static `SpringApplication.run`.
- `DocApiContextTest` — `@SpringBootTest` boots the full context on the default (in-memory) profile.
- `DocApiJdbcWiringTest` — `@SpringBootTest` `@ActiveProfiles("test","jdbc")` with an H2 datasource
  supplied via `@TestPropertySource`, proving the `jdbc` profile still wires (no procs invoked).
- `NewsDocumentRepositoryTest` — mocks `JdbcTemplate`, asserts get scalar mapping + the SQL string.
- `DocumentServiceTest` — mocks `DocumentStore`, real `ObjectMapper`: get/parse, not-found, blank-id,
  add normalization, blank/malformed body rejection, update id fallback.
- `NewsControllerTest` — `@WebMvcTest(NewsController.class)`, `@MockBean` service and `NewsQueryRepository` (16 tests): the CRUD envelope (GET/404/POST-201/400/PUT); the News-page queries via mocked repository (empty `/list` echoing paging, 400 on a non-2-letter country, empty `/default`, successful queries returning paginated items or home-page JSON), offset/limit clamping, country validation, **and the interchange `/export/{id}` (200 doc / 404) + `/import` (201 id / 400 on empty/malformed body)**.
- `NewsCacheTest` — `NewsQueryCache` unit tests: US/CA bucketing, LRU of other requests, deep-paging read-through, clear/eviction, **`/export` read-through (never cached) and `/import` evicting the cached lists + home page**.
- `FishControllerTest` — `@WebMvcTest(FishController.class)`, `@MockBean` service and `FishQueryRepository` (22 tests): the CRUD envelope (GET 200 doc / 404) plus `/fish/search` — result mapping into the envelope, term trimming before the query, empty-result echo, and blank/missing `q` ⇒ 400. The two base-path lookups are covered too: envelope shape, the `{"BURB", "WALL"}` literal, bracket/semicolon lists, repeated parameters staying un-split, blank entries dropped, province/country trimming, whole-province mode, a quoted name keeping its comma, `fishes` taking precedence, and the 400s (codes without province, no parameter at all, over-limit batches).
- `RiverControllerTest` — `@WebMvcTest(RiverController.class)`, `@MockBean` `RiverQueryRepository` + `RiverFishCommandRepository` + `RiverDescriptionCommandRepository` (20 tests): `/river/unfished` result mapping into the envelope, default fallback (missing params → CA/ON/2), bad-code/river cleaning (never rejected), lower-case state upper-casing, `GET /river/description/{guid}` (200 doc / 404 on an unknown guid), `GET /river/fish/{guid}` (200 doc / 404 on an unknown guid), `PATCH /river/fish/{guid}` (200 result envelope, 404 unknown lake, 400 empty array, 400 non-array body, 400 missing body, 400 over-`MAX_FISH_BATCH`), and `PATCH /river/description/{guid}` (200 result envelope, 404 unknown lake, 400 empty object, 400 array body, 400 missing body, 400 over-`MAX_PATCH_FIELDS` — the 400 cases across both PATCH endpoints also assert the repository is never invoked).
- `RegulationControllerTest` — `@WebMvcTest(RegulationController.class)`, `@MockBean`
  `RegulationQueryRepository` + `RegulationCommandRepository` (11 tests): `GET /river/regulation/{guid}`
  (200 doc / 404 unknown), `PATCH /river/regulation/{guid}` (200 result envelope, asserts via an
  `ArgumentCaptor` that `lakeId` is injected from the path and `zoneId` is stripped even when the body
  supplies one, 400 missing body, 400 array body), `GET /region/regulation/{country}` and
  `.../{country}/{state}` (null-vs-set state passed through, upper-casing, 400 on a non-two-letter
  country), and `PATCH /region/regulation/{country}` / `.../{country}/{state}` (asserts `country`/
  `state` set from the path and `state`/`zoneId`/`lakeId` stripped from the body, 400 on a
  non-two-letter state).
- `DocumentRoundTripTest` — `@SpringBootTest` + `@AutoConfigureMockMvc`, default in-memory backing:
  POST→GET→PUT→GET round-trip, 404 on unknown id, all four entities accept documents, and the News
  `/list` + `/default` queries return well-formed empty payloads with no DB.
- `HealthControllerTest` — version-from-build-info and fallback.
- Test resources: `application.properties` (`spring.profiles.active=test`) and `application-test.yml`
  (no datasource — small resilience4j config, WARN logging; the JDBC datasource for
  `DocApiJdbcWiringTest` comes from its `@TestPropertySource`).

## .env.example (project root, placeholders only)

```dotenv
DB_URL=jdbc:sqlserver://host.docker.internal:1433;databaseName=your_database;encrypt=true;trustServerCertificate=true
DB_USERNAME=your_username
DB_PASSWORD=your_password
# DOTENV_PATH=/app/.env
# JAVA_OPTS=-Xms256m -Xmx512m
```
