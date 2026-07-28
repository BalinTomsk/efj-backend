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
| Management (Actuator) port | 8081 (private) |

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
`NewsQueryRepository` has two implementations registered per profile:

- **default (no profile)** — `InMemoryStoreConfig` (`@Profile("!jdbc")`) registers four
  `InMemoryDocumentStore` beans (`newsStore`, `waterbodyStore`, `fishStore`, `stationStore`) and one
  `InMemoryNewsQueryRepository` bean. No DB. `application.yml` sets `spring.autoconfigure.exclude`
  to `DataSourceAutoConfiguration`, `DataSourceTransactionManagerAutoConfiguration`,
  `JdbcTemplateAutoConfiguration`, and disables the actuator `db` health indicator (readiness group =
  `readinessState` only).
- **`jdbc` profile** — `JdbcStoreConfig` (`@Profile("jdbc")`) registers four `JdbcDocumentRepository`
  beans under the **same names**, each taking the shared `JdbcTemplate`, and one `JdbcNewsQueryRepository`
  bean. `application-jdbc.yml` clears the auto-configure exclusion, configures the datasource, and
  re-enables the `db` health indicator + readiness `db` group.

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

**Interface:**

- `NewsListPage list(String country, int offset, int limit)` — `country` NULL ⇒ all countries;
  an ISO-2 code filters to it, and a **non-CA** country with fewer than 100 published items is
  padded with the latest Canadian news up to 100 (`blockOrd = 1`). Modern `OFFSET/FETCH` paging
  with a windowed `COUNT(*) OVER()` `total`. Returns `NewsListPage` with items list and paging metadata.
- `JsonNode defaultNews()` — returns `{ "items": [ <news>, … ] }` in display order (2 lead articles
  first, then 3 right-column items), each the per-item JSON document. With no JDBC backing
  (default profile), returns `{ "items": [] }`.

**SQL details:**

- `dbo.fn_news_list(@country, @offset, @fetch)` — `@country` NULL ⇒ all countries; an ISO-2 code
  filters to it, and a **non-CA** country with fewer than 100 published items is padded with the
  latest Canadian news up to 100 (`block_ord = 1`). Modern `OFFSET/FETCH` paging with windowed
  `COUNT(*) OVER()` `total`.
- `dbo.fn_default_news_ids()` — the home-page ids with `with_photo` (1 = lead/photo slot, 2 leads;
  0 = right column) and `ord` (1-based display position). `dbo.fn_default_news_json(@news_id,
  @with_photo)` — the per-item JSON document (info + base64 photo for a lead; compact for a
  right-column item).

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
+ `ObjectMapper` into `super(...)`.

`NewsController` additionally injects `NewsQueryRepository` and adds the two News-page read queries
as delegations to the repository:

- `@GetMapping("/list")` `list(country, offset, limit)` — normalizes/clamps params (a non-2-letter
  `country` ⇒ `InvalidDocumentException` → 400), then delegates to
  `queryRepository.list(normalizedCountry, safeOffset, safeLimit)`. The repository handles SQL
  execution (JDBC profile) or returns empty results (default profile).
- `@GetMapping("/default")` `defaultNews()` — delegates to `queryRepository.defaultNews()`,
  returning `{ "items": […] }` per the repository implementation.

The literal `/list` and `/default` paths win over the inherited templated `/{id}`. Resilience4j
decorators (`@Retry` / `@CircuitBreaker`) live on the repository methods, not the controller.

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

`management.server.port: 8081` (private — never exposed publicly). Exposed web endpoints only
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

`mvn test` runs 30 tests, none requiring a database:

- `DocApiApplicationTest` — mocks static `SpringApplication.run`.
- `DocApiContextTest` — `@SpringBootTest` boots the full context on the default (in-memory) profile.
- `DocApiJdbcWiringTest` — `@SpringBootTest` `@ActiveProfiles("test","jdbc")` with an H2 datasource
  supplied via `@TestPropertySource`, proving the `jdbc` profile still wires (no procs invoked).
- `NewsDocumentRepositoryTest` — mocks `JdbcTemplate`, asserts get scalar mapping + the SQL string.
- `DocumentServiceTest` — mocks `DocumentStore`, real `ObjectMapper`: get/parse, not-found, blank-id,
  add normalization, blank/malformed body rejection, update id fallback.
- `NewsControllerTest` — `@WebMvcTest(NewsController.class)`, `@MockBean` service and `NewsQueryRepository` (11 tests): the CRUD envelope (GET/404/POST-201/400/PUT); the News-page queries via mocked repository (empty `/list` echoing paging, 400 on a non-2-letter country, empty `/default`, successful queries returning paginated items or home-page JSON), offset/limit clamping, and country validation.
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
