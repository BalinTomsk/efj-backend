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
│   ├── NewsDocumentRepository     # binds dbo.fn_news_doc / sp_news_doc_add / sp_news_doc_update
│   ├── WaterbodyDocumentRepository
│   ├── FishDocumentRepository
│   ├── StationDocumentRepository
│   ├── NewsQueryRepository        # interface: list(country, offset, limit) + defaultNews() (news-page queries)
│   ├── InMemoryNewsQueryRepository # default backing — empty results (no DB)
│   └── JdbcNewsQueryRepository    # JDBC backing — calls dbo.fn_news_list / dbo.fn_default_news_json
├── service
│   ├── DocumentService            # abstract base: id/body validation, JSON well-formedness, 404 mapping
│   ├── NewsDocumentService … (one @Service per entity)
│   ├── DocumentNotFoundException  # → HTTP 404
│   └── InvalidDocumentException   # → HTTP 400
└── web
    ├── AbstractDocumentController # GET/POST/PUT shared surface; body consumed as raw JSON string
    ├── NewsController             # base-path CRUD + News-page queries (/list, /default) + interchange /export, /import
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
  from `DB_URL`/`DB_USERNAME`/`DB_PASSWORD`; `JdbcStoreConfig` provides four `JdbcDocumentRepository`
  beans and one `JdbcNewsQueryRepository`; the `db` health indicator + readiness `db` group are
  re-enabled. Run with `--spring.profiles.active=jdbc`.

---

## Database contract (jdbc profile only — NOT yet created)

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
| `GET /api/v1/news/default` | `dbo.fn_default_news_json(news_id, with_photo) FROM dbo.fn_default_news_ids() ORDER BY ord` | assembled home page — 2 lead items then 3 right-column, each the per-item JSON document |

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

- `sqlRetry` — 3×/2s on `DataAccessException` / `SQLException`.
- `sqlBreaker` — window 10, min 5 calls, 50% threshold, open 30s.
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
- **Actuator** on private `management.server.port: 8081`; exposed endpoints only
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

`mvn test` — no DB needed (65 tests):

- `DocumentServiceTest` — validation, normalization, not-found (mocks `DocumentStore`).
- `NewsDocumentRepositoryTest` — get mapping + SQL string (mocks `JdbcTemplate`).
- `NewsControllerTest` — `@WebMvcTest` slice: CRUD envelope (404, 201, 400) **plus** the News-page
  queries via mocked `NewsQueryRepository` — empty `/list`+`/default` with a 400 on a bad country,
  successful queries returning paginated items or home-page JSON, **and the interchange
  `/export/{id}` (200 doc / 404) + `/import` (201 id / 400 on empty/malformed body)**.
- `NewsCacheTest` — `NewsQueryCache` behaviour incl. `/export` read-through (never cached) and
  `/import` evicting the cached lists + home page.
- `DocumentRoundTripTest` — `@SpringBootTest` + MockMvc, default in-memory backing: POST→GET→PUT→GET
  round-trip, 404, all four entities accept documents, and the News `/list`+`/default` queries return
  empty payloads (the "it actually works with no DB" proof).
- `HealthControllerTest`, `DocApiApplicationTest` (mocks `SpringApplication.run`).
- `DocApiContextTest` — full context boot on the default (in-memory) profile.
- `DocApiJdbcWiringTest` — boots the `jdbc` profile with an H2 stand-in to keep that wiring verified.

---

## API / platform architectural rules (shared across services)

- All endpoints versioned: `/api/v1/...`
- Standard response envelope: `{ data, error, meta }`
- Every external/DB call: timeout + retry with backoff; circuit breaker on downstream deps.
- Health check: `GET /health` → `{ status, version, uptime }`.
- Each service owns its data store exclusively.

## Changelog

- 2026-08-01: **1.2.0 — news interchange export/import endpoints (`fn_news_json` format).**
  `NewsController` gained `GET /api/v1/news/export/{id}` (→ `dbo.fn_news_json`, full self-contained doc:
  every field + all 3 paragraph photos as base64; `NULL` ⇒ 404) and `POST /api/v1/news/import`
  (→ new `dbo.sp_news_import`, creates a **published** article from that JSON, base64 photos decoded to
  binary, 201 `{ id }`; blank/malformed body ⇒ 400). This is the same interchange format the portal's
  News.aspx "Save JSON" link and `AddNews.aspx` "Import from JSON" use, so news round-trips
  API↔portal. **Only these two carry the full document** — `GET /{id}`, `/list`, `/default` keep their
  existing lighter shapes. Wired through `NewsQueryRepository` (interface + JDBC + in-memory);
  `NewsQueryCache` reads export through uncached and **evicts the cached lists/home page on import**.
  Tests: `NewsControllerTest` (+5) and `NewsCacheTest` (+2) → **65 pass**. DB side is
  `dbo.sp_news_import` (envfish-db, added test-first — `unit_test@NewsImport.sql`, 4 tests incl. a
  fn_news_json export→import round-trip); `dbo.fn_news_json` already existed. Docs: this file, `README.md`,
  `docs/specification.md`. **Deployed to prod 2026-08-01** (`sp_news_import` applied to the DB first;
  image `ghcr.io/balintomsk/docapi:1.2.0` on the droplet; `/health` reports 1.2.0; `/news/list`,
  `/default`, `/export/{guid}` → 200; import verified live end-to-end — POST 201 → export 200 with a
  byte-perfect base64 photo round-trip — then the test article was deleted and the cache cleared via a
  container restart).
  **Deploy gotcha (now baked into the `update-docapi` skill + `docs/do-update.md`):** since 2026-07-29
  the `DB_*` values in `docapi.env` are **encrypted** (`SecretCodec`), so the container run command MUST
  mount the master key — `-e FF_MASTER_KEY_FILE=/run/master.key -v /mnt/volume_jnode/docapi/master.key:/run/master.key:ro`
  — or it crash-loops with *"Value of DB_USERNAME is encrypted but no master key is configured."*
