# docapi Changelog

Split out of `CLAUDE.md` for readability. Newest entries first.

- 2026-09-02: **1.7.4 — `sqlRetry` only retries transient failures now. BUILT AND TESTED, NOT
  DEPLOYED.**
  The list was `DataAccessException` + `SQLException` — the root of Spring's DAO hierarchy, so it
  retried *everything*, permanent faults included. During the 1.7.3 incident a
  `BadSqlGrammarException` (T-SQL sent to MySQL) was retried twice for nothing; a
  `DataIntegrityViolationException` on a write would be retried the same way, which on a write path
  can compound the damage rather than just wasting time.
  - **The fix is three types, and they are NOT redundant.** Spring files connection failures under
    different branches, so the tempting "just use `TransientDataAccessException`" simplification
    would silently stop retrying driver-level connect failures — the exact case this retry exists
    for:

    | failure | JDBC exception | Spring type | branch |
    |---|---|---|---|
    | Hikari pool timeout | `SQLTransientConnectionException` | `TransientDataAccessResourceException` | Transient |
    | driver connect failure | `SQLNonTransientConnectionException` | `DataAccessResourceFailureException` | **NonTransient** |
    | connection dropped mid-use | `SQLRecoverableException` | `RecoverableDataAccessException` | Recoverable |
  - **Tests.** `onlyTransientFailuresAreRetried` asserts the classification *behaviourally* (by
    assignability against the configured types, not by string-comparing the list): pool timeout,
    connect failure, dropped connection, query timeout and deadlock must retry; bad grammar,
    constraint violation, duplicate key, permission denied and API misuse must not.
    `retryExceptionListMirrorsProduction` pins `application-test.yml` to the same list — its faster
    timings are legitimate, a different exception list would mean the suite exercises retry
    semantics production does not have. **Verified both catch the old config:** restoring it fails
    with `bad SQL grammar - the 2026-09-02 case (BadSqlGrammarException) should NOT be retried` and
    the mirror assertion. 149 tests pass with the fix.
  - Confirmed the retry genuinely applied before this change: `JdbcFishQueryRepository.search()`
    lets the `DataAccessException` propagate (the `RuntimeException` wrapper seen in the incident
    logs is added *above* the Resilience4j proxy), so `@Retry` did see and retry the grammar error.

- 2026-09-02: **1.7.3 — CRITICAL: every SQL-Server-backed endpoint was sending T-SQL to MySQL.
  BUILT AND TESTED, NOT DEPLOYED.**
  **Live impact, present since the MySQL news migration (2026-08-31):** `/api/v1/fish/search`,
  `/api/v1/river/*` and `/api/v1/region/regulation/*` all returned `500`. The root exception was
  `SQLSyntaxErrorException: ... check the manual that corresponds to your **MySQL** server version
  ... near '('trout') ORDER BY irank ASC'` — the T-SQL `dbo.SearchFishList(?)` executed against
  MySQL. On the droplet, only `docapi-news-mysql-hikari` ever started; `docapi-hikari` never
  initialised and the logs contained **zero** SQL Server driver mentions. Only the MySQL-backed news
  endpoints worked.
  - **Cause.** `JdbcTemplateAutoConfiguration` is `@ConditionalOnMissingBean(JdbcOperations.class)`.
    `JdbcStoreConfig.mysqlNewsJdbcTemplate` registers a `JdbcTemplate` (which *is* a
    `JdbcOperations`), so the auto-configuration **backed off entirely** and the SQL Server template
    was never created. All thirteen beans injecting a bare `JdbcTemplate` — `fishQueryRepository`,
    `riverQueryRepository`, `river*CommandRepository`, `regulation*`, `sqlServerNewsStore`,
    `sqlServerNewsQueryRepository`, the fish/waterbody/station stores — silently got the MySQL one.
    The MySQL consumers were fine; they use `@Qualifier("mysqlNewsJdbcTemplate")`.
  - **The irony:** `mysqlNewsJdbcTemplate`'s own javadoc documents this exact hazard one layer down,
    for `DataSource`, and dodges it by keeping the `HikariDataSource` local. The identical trap for
    `JdbcTemplate` was walked straight into. That trick could not be reused here — the news
    repositories genuinely need a `JdbcTemplate` bean to inject.
  - **Fix.** Declare the SQL Server `JdbcTemplate` explicitly and mark it `@Primary`, so by-type
    injection is unambiguous and no longer depends on whether the auto-configuration runs.
  - **Why nothing caught it.** `DocApiJdbcWiringTest` asserted only that beans were AOP proxies —
    never *which database* they pointed at — and H2 stands in for SQL Server there, so a
    misdirected template still "worked". New test
    `sqlServerRepositoriesGetTheSqlServerTemplateNotTheMysqlOne` asserts the by-type `JdbcTemplate`
    is bound to the `docapi-hikari` pool and is a different object from the news pool. **Verified it
    reproduces the outage:** written before the fix, it failed with `expected: "docapi-hikari"`.
    147 tests pass with the fix.
  - Found only because the 1.7.2 timeout work turned a 30s hang into a 2.7s failure, which let the
    real exception surface instead of being swallowed by a proxy timeout.

- 2026-09-02: **DB timeout budget — every DB-backed endpoint could hang for ~94s. BUILT AND TESTED,
  NOT DEPLOYED.**
  **Symptom:** `/api/v1/fish/search`, `/api/v1/news/list` and `/api/v1/news/default` all hung; cproxy
  returned `502` after 20s (its 10s read timeout, twice). `/health` answered in 0.01s and
  `/api/v1/fish` in 0.008s throughout — those never touch a database, which made it look like a
  query problem.
  - **Not the query.** `dbo.SearchFishList('trout')` runs in **112ms** returning 22 rows against
    prod SQL Server. Not thread-pool exhaustion either — `/health` stayed instant the whole time.
  - **Root cause: an intermittently lossy network path from the droplet to the Winhost DB hosts.**
    Measured from the droplet, ~**2 of 6** TCP handshakes to the DB ports time out; the same probes
    from a workstation succeed consistently. A dropped SYN is *silence*, not a refusal, so each
    attempt sat until its timeout. **Both** stores are affected — MySQL and SQL Server are at the
    same provider over the same path, so moving news to MySQL never escaped this.
  - **The amplifier was our own config:** Hikari `connection-timeout: 30000` on both pools, **no**
    driver-level timeouts at all, and `sqlRetry` at 3 attempts × 2s. Worst case
    `3 × 30s + 2 × 2s ≈ 94s` for a single request — far past cproxy's 10s, so callers could only ever
    see an opaque `502`.
  - **Fix — a stated time budget, not just smaller numbers.** Hikari `connection-timeout` 30000 → 4000
    (both pools) with `validation-timeout` 5000 → 2000 to stay under it; driver-level
    `loginTimeout: 3` (mssql-jdbc, **seconds**) and `connectTimeout: 3000` (Connector/J,
    **milliseconds** — the unit differs, and getting it wrong would be expensive); `sqlRetry`
    3×/2s → **2×/500ms**. Worst case ≈ **6.5s**, comfortably inside cproxy's 10s, so a bad path now
    yields a real error instead of a hang. `socketTimeout` is set to 30s on both as a last-resort
    guard on a stalled read and is deliberately *outside* the budget, so a legitimately slow
    `/news/default` assembly is never cut off.
  - **Test:** `DocApiJdbcWiringTest.dbFailurePathFitsInsideTheProxyReadTimeout` asserts the budget
    (attempts × connect + waits < 10s) rather than the literal knob values, plus
    `bothPoolsSetADriverLevelConnectTimeout`. It reads the retry numbers **from the production yaml
    on purpose**: `application-test.yml` overrides `sqlRetry` to 3×/10ms so the suite runs fast, and
    asserting the running context would have passed while production stayed misconfigured — the
    exact blind spot the test exists to close. **Verified it catches the bug:** restoring the pre-fix
    values fails it with `3 attempts x 30000ms connect + 2 x 2000ms wait`, independently reproducing
    the 94s figure. 146 tests pass with the fix.
  - **Not fixed here:** the flaky droplet↔Winhost path itself. This change converts a hang into a
    prompt, diagnosable error; it does not make the network reliable. Worth checking Winhost's
    remote-access IP allowlist and any connection throttling for the droplet's address.

- 2026-09-01: **1.7.1 — Deployed to production (no code changes from 1.7.0).** MySQL news backing (added 2026-08-31) + cached `news.has_photo0` perf fix deployed live. Image `ghcr.io/balintomsk/docapi:1.7.1` on droplet <docapi-droplet>; configured with `MYSQL_NEWS_URL`, `MYSQL_NEWS_USERNAME`, `MYSQL_NEWS_PASSWORD` pointing to the Winhost MySQL host (<mysql-host>, database `mysql_111487_envfish`). `/health` reports `1.7.0` (build version unchanged; only config/environment changed). All endpoints verified live: `/api/v1/news/list` returns 650+ articles with photos, `/api/v1/news/default` returns assembled home page with photo data, unknown article GUIDs return 404 (proves `sp_news_doc_get` working live), full newscontroller surface healthy.

- 2026-08-31: **1.7.0 (committed but not yet deployed)** — News reads (`GET /api/v1/news/{id}`, `/news/list`, `/news/default`) moved from SQL
  Server to MySQL.** The `news` table migrated to Winhost MySQL on 2026-08-31 (`envfish-db/mysql/`),
  initially only for `fishfind-frontend`'s `News.aspx`; these three read endpoints now use it too via
  two new classes: `MySqlNewsDocumentRepository` (`DocumentStore`, wraps `sp_news_doc_get`;
  `addDocument`/`updateDocument` delegate unchanged to the SQL-Server-backed `NewsDocumentRepository`)
  and `MySqlNewsQueryRepository` (`NewsQueryRepository`, wraps `sp_news_list_json`/`sp_news_default`;
  `search`/`exportNews`/`importNews` delegate unchanged to the SQL-Server-backed
  `JdbcNewsQueryRepository`) — composition, not inheritance, so each method can pick its own backend
  while writes/search/export/import keep their existing Resilience4j-proxied delegate. Both classes
  are registered as `jdbc` profile beans under the **same bean names** (`jdbcNewsStore` /
  `jdbcNewsQueryRepository`) the SQL-Server-only implementations used to occupy — those SQL-Server
  instances moved to new `sqlServerNewsStore`/`sqlServerNewsQueryRepository` beans that the MySQL
  classes wrap, so `NewsDocumentCache`/`NewsQueryCache`/`NewsCacheEvictor` needed no changes.
  New `JdbcStoreConfig.mysqlNewsJdbcTemplate` bean builds a dedicated `HikariDataSource` from
  `MYSQL_NEWS_URL`/`MYSQL_NEWS_USERNAME`/`MYSQL_NEWS_PASSWORD` but never registers it as a
  `DataSource` bean (only the `JdbcTemplate` is returned) — a second `DataSource` bean would make
  Spring Boot's `DataSourceAutoConfiguration` back off from creating the *primary* SQL Server
  datasource, since its `@ConditionalOnMissingBean(DataSource.class)` fires on the first
  `DataSource`-typed bean found regardless of qualifier. New `mysql-connector-j` runtime dependency.
  New DB objects in `envfish-db/mysql/script02_Proc.sql`: `sp_news_doc_get`, `sp_news_list_json`,
  `sp_news_default` — applied to the live Winhost database 2026-08-31. New tests:
  `MySqlNewsDocumentRepositoryTest`, `MySqlNewsQueryRepositoryTest`; `DocApiJdbcWiringTest` extended
  with MySQL placeholder properties (its H2 stand-in never actually connects to MySQL — the Hikari
  pool used here initializes lazily on first real query).
- 2026-08-31: **Post-deploy fix — `sp_news_list_json`/`sp_news_default` hung indefinitely on the
  live Winhost host** (never reproduced on the local test DB, same schema but far fewer rows).
  Root cause: both referenced `news_photo0`/`news_photo1` in a query that materializes multiple rows
  (a temp table, a window function) — even a bare `IS NOT NULL`, no `LENGTH()`/base64 — and this
  specific host is catastrophically slow whenever that happens, confirmed via `SHOW FULL
  PROCESSLIST` (`State: executing`, not a lock wait) and three independent rewrites. Fixed in
  `envfish-db` by adding a cached `news.has_photo0` flag column + maintenance triggers (see that
  repo's changelog and `CLAUDE.md` → "Cached flags on `news`") and rewriting both procedures to read
  it instead of the BLOB columns for anything scanning more than one row. No docapi code changes —
  the fix is entirely in `envfish-db/mysql/`. Verified post-fix: both procedures return in 1-3s on
  prod (previously 90s+ / never returned).
- 2026-08-26: **1.7.0 — `RiverController` gains `GET`/`PATCH /api/v1/river/source/{guid}` and
  `GET`/`PATCH /api/v1/river/mouth/{guid}`.** The Source/Mouth-tab counterparts of the existing
  description/fish endpoints, for `Editor/EditLakeLink.aspx?Type=16|32`.
  **Reads** reuse the already-live `dbo.fn_lake_source_json` / `dbo.fn_lake_mouth_json` (the same
  functions the admin "Save JSON" button on that page already calls via
  `HandlerImage.ashx?lakejson=&tab=source|mouth`) through two new `RiverQueryRepository` methods
  (`source`/`mouth`) — no new DB object for the read side. **Writes** are a JSON **merge patch** of
  that tab's editable fields — `lat`, `lon`, `elevation`, `country`, `state`, `county`, `city`,
  `district`, `municipality`, `region`, `zone`, `coast`, `location`, `description` (the exact set
  `EditLakeLink.aspx`'s `ButtonSubmit_Click` writes for this tab) — via two new stored procedures,
  `dbo.sp_lake_source_update` / `dbo.sp_lake_mouth_update` (`envfish-db`, 2026-08-26), fronted by one
  new **`RiverLinkCommandRepository`** (`patchSource`/`patchMouth`) — a single repository for both
  tabs rather than two, since they are the identical merge-patch mechanism against a different
  `Tributaries.side` (16 vs 32; `UK_Tributaries_Source`/`UK_Tributaries_Mouth` guarantee at most one
  row per side per water body). **Deliberately protects every identity/linkage field
  `EditLakeLink.aspx` shows read-only in this exact spot** — the main water body's own
  `lakeName`/`guid`, and the linked point's `pointName`/`pointId` (plus the row's internal `id`/
  `stamp`, neither a user-editable field on that page) — reported back as `protectedFields` rather
  than silently dropped or applied, same contract as `sp_lake_description_update`. Empty/non-object/
  over-100-key body ⇒ 400 `invalid_document`; unknown lake guid ⇒ 404 for every one of the four new
  routes. **No cproxy change needed**: cproxy is a transparent method/path passthrough (GET/PATCH
  admitted since 0.6.1) with no per-path allowlist, so these routes reach production automatically the
  moment docapi itself is redeployed; the PATCH routes pick up the existing day-key gate the same way.
  **DB (envfish-db):** `unit_test@LakeJson.sql` TEST 15–18 (writes all 14 editable fields and reports
  them updated; 6 identity/linkage fields reported `protectedFields` and applied to none of them;
  mouth PATCH touches only the `side=32` row, leaving `side=16` untouched; unknown lake id ⇒ `NULL`
  for both procs, malformed JSON ⇒ a `protectedFields`-shaped error) — all pass via `autorun.bat`.
  **docapi:** `RiverControllerTest` gained 9 tests (GET 200/404 ×2, PATCH 200/protected-fields/404/400
  ×2) — full suite is 135 tests, 0 failures.
  **Deployed to prod 2026-08-26** — DB procs applied, then the `docapi` JAR/container; all four new
  routes reachable live through the cproxy gateway. **The two PATCH routes shipped broken**: both
  `dbo.sp_lake_source_update` and `dbo.sp_lake_mouth_update` were created on prod by a hand-run script
  that skipped `SET QUOTED_IDENTIFIER ON` before the `CREATE PROCEDURE` — SQL Server bakes that setting
  in at create time, not call time, so every call hit error 1934 ("UPDATE failed because the following
  SET options have incorrect settings: 'QUOTED_IDENTIFIER'") against `dbo.Tributaries` (it carries the
  filtered unique indexes `UK_Tributaries_Source`/`UK_Tributaries_Mouth`), surfaced to callers as a
  generic `500 internal_error`. The two GET routes were unaffected (they only read the already-live
  `fn_lake_source_json`/`fn_lake_mouth_json`). This is the identical incident class as the
  `sp_lake_description_update` QUOTED_IDENTIFIER bug below (1.5.4, 2026-08-25) recurring on the next
  two procs deployed the same way. **Fixed same day**: both procs `DROP`+recreated on prod with
  `SET QUOTED_IDENTIFIER ON` immediately before each `CREATE PROCEDURE` (body unchanged, matches
  `envfish-db/mssql/script02_Proc.sql:2100`/`:2177`) — `OBJECTPROPERTY(...,'ExecIsQuotedIdentOn')` now
  reports `1` for both. Verified via a rolled-back direct-DB call (clean result envelope, no error) and
  a live end-to-end `PATCH`+`GET` round trip through the cproxy gateway with real day-key auth against
  Fleuve Churchill's source and mouth rows, then reverted the test value back to `null`.
- 2026-08-25: **1.6.0 — new `RegulationController`: `GET`/`PATCH /api/v1/river/regulation/{guid}` +
  `GET`/`PATCH /api/v1/region/regulation/{country}[/{state}]`.** Covers two of the three scopes
  `Editor/LakeRegulation.aspx`'s single "regulation dialog" edits through one `dbo.regulations` table —
  water-body rules and region (country/state) rules; zone-scoped rules have no dedicated endpoint yet.
  **No separate INSERT verb**: every PATCH upserts by identity via the new `dbo.sp_regulation_upsert`
  (envfish-db, 2026-08-25) — identity = `country`/`state`/`zoneId`/`lakeId`/`fishId`/`year`/`part`/
  `residentType` (the columns behind `dbo.regulations`' two filtered unique indexes); a body matching
  nothing existing inserts, one matching an existing row updates it in place. Scope is *inferred*, not
  declared: `lakeId` → water-body; `zoneId` (no `lakeId`) → zone; neither → region (whole-country when
  `state` omitted, else province/state-wide); `zoneId`+`lakeId` both set is rejected. The identifying
  fields always come from the URL, never the body, on every write route. Validation failures are a
  `200` with an inline `error` (missing `year`, unknown `lakeId`/`fishId`, the mutual-exclusivity
  violation), not a `4xx` — same graceful contract as `sp_lake_description_update`'s malformed-JSON
  path. **Deliberately no `POST`**: cproxy's write surface only admits `GET`/`PATCH` (the day-key gate
  is verb-based, not path-based), so reusing the fish/description endpoints' upsert-on-PATCH pattern
  ships this with **zero cproxy change**. `dbo.TR_regulations` auto-adds the row to `lake_fish` when a
  new water-body rule also carries a `fishId` not yet assigned to that lake — same side effect the
  ASPX page's own INSERT triggers.
  **Schema change required** on `dbo.regulations`: it had no `country` column and `state` was
  `NOT NULL`, so a genuine "whole country, no state" rule wasn't representable. Added
  `country char(2) NOT NULL DEFAULT 'CA'`, relaxed `state` to nullable, and folded `country` into both
  filtered unique indexes — SQL Server treats two NULLs as equal for unique-index purposes, so without
  `country` in the key a second country's state-less rule would collide with the first country's.
  Migration is idempotent/guarded (`script01_createTable.sql`, applies to any pre-existing database);
  the base `CREATE TABLE` was also updated for fresh builds.
  New `dbo.fn_lake_regulation_json` field: `country` (function already existed from the 2026-08-13
  per-tab Save-JSON rollout, extended rather than replaced). New `dbo.fn_region_regulation_json(
  @country, @state=NULL)`.
  Tests: `RegulationControllerTest` (11, new) → **122 pass** (full docapi suite). DB:
  `unit_test@RegulationUpsert.sql` (11 tests) + `unit_test@RegulationRead.sql` (3 tests), both pass via
  `autorun.bat` (2 pre-existing, unrelated `FishCodeLatinJson.sql` failures — not touched by this
  change).
  **Deployed to prod 2026-08-26** — image `ghcr.io/balintomsk/docapi:1.6.0` on the droplet; startup
  clean (no exceptions in the startup-window scan), `GET /health` reports `1.6.0`, and all three new
  routes verified live: `GET /api/v1/river/regulation/{guid}`, `GET /api/v1/region/regulation/ca/on`,
  `GET /api/v1/region/regulation/us` all `200` with real rows.
  Docs: this file, `README.md`, `docs/specification.md`, `docs/api-reference.html` (per the
  API-change rule) — the `docs/api-reference.html` "verified live" version chips bumped to 1.6.0 now
  that the endpoint has been exercised against the live deployment.

- 2026-08-25: **1.5.4 — river description write `PATCH /api/v1/river/description/{guid}` (admin
  Save-JSON "General"-tab merge patch) — a second, independent write.** Native docapi duplicate of
  `Editor/LakeEditor.aspx`'s "General" tab (`SaveLakeGeneral`): body is a JSON **object**, and only
  keys actually present are touched (true merge-patch semantics, not a full-document overwrite) via
  the new `dbo.sp_lake_description_update` (envfish-db, 2026-08-25) through a new
  `RiverDescriptionCommandRepository` bean. Covers every editable field `fn_lake_description_json`
  exports — `altName`, `nativeName`, `french`, `link`, `type`, `length_km`, `width_km`,
  `shoreline_km`, `maxDepth_m`, `volume_km3`, `surface_km2`, `discharge_m3s`, `basin_km2`,
  `watershield_km2`, `drainage`, `cgndb`, `roadAccess`, `fishingProhibited`, `isolated`, `noFish`,
  `reviewed`, `description` — **except the identity/linkage fields the same admin page shows
  read-only in this exact spot**: `lakeName`, `source`/`sourceId`, `mouth`/`mouthId`. Those are
  reported back as `protectedFields` rather than silently dropped or applied, so a caller knows they
  did not take effect. `noFish` honors the same client-side rule `LakeEditor.aspx` enforces: blocked
  (reported `ignored`) while the lake has any assigned species. Request validation (non-empty JSON
  object, ≤ `MAX_PATCH_FIELDS` = 100 keys) happens in the controller before any SQL, reusing
  `InvalidDocumentException` like every other write here. Unknown lake guid ⇒ 404. **Fronted through
  cproxy automatically** — the day-key gate (0.6.1) applies to every PATCH request, not a specific
  path, so no cproxy code change was needed; verified live end-to-end through the public gateway with
  both the correct day-key (200, real field update, `lakeName` correctly protected) and a
  wrong/missing one (500). Tests: `RiverControllerTest` (+6) → **111 pass** (full suite). DB:
  `unit_test@LakeDescriptionUpdate.sql` (8 tests) passes via `autorun.bat` (full suite 513 PASS / 2
  pre-existing FAIL, unrelated). **Deployed to prod 2026-08-25 as 1.5.4** (image
  `ghcr.io/balintomsk/docapi:1.5.4`; `dbo.sp_lake_description_update` applied to prod first, gated on
  a real patch/verify/restore smoke test round-tripped through the proc itself, not a raw `UPDATE`).
  **Deploy gotcha hit twice, worth remembering:** (1) `DECLARE @v TYPE = (SELECT …)` — a subquery
  inside an inline `DECLARE` initializer — is rejected by this SQL Server instance ("Subqueries are
  not allowed in this context"); fixed by declaring then `SET`-ing separately, everywhere in both the
  proc and the ad-hoc apply script. (2) A stored procedure bakes in the `QUOTED_IDENTIFIER` session
  setting **at CREATE time**, not at call time — `dbo.lake` has a filtered unique index
  (`UK_lake_CGNDB`), so a proc created without `SET QUOTED_IDENTIFIER ON` first fails **every** UPDATE
  against that table at runtime with error 1934, regardless of the caller's own session settings.
  `envfish-db/script0.sql` sets this once for the whole concatenated build (why the local `autorun.bat`
  DB never hit it), but a hand-run apply script against prod must set it explicitly before any
  `CREATE PROCEDURE`.
  Docs: this file, `README.md`, `docs/specification.md`, `docs/api-reference.html` (per the
  API-change rule).

- 2026-08-25: **cproxy day-key decision, now deployed (no docapi change).** The security posture left
  open in the 1.5.3 entry below — how/whether to front `PATCH /api/v1/river/fish/{guid}` through
  cproxy — was resolved and shipped: cproxy 0.6.1 (0.6.0 plus a same-day Content-Type-forwarding fix
  found during this deploy) adds a `DayKeyStore` (SQLite, 365 rows, one rotating GUID per day of the
  year) gating every PATCH via a new `X-Day-Guid` header, in place of a static `CPROXY_API_KEY`.
  **Deployed and verified end-to-end through the public gateway** — see `efc-proxy` `CLAUDE.md` →
  "Day-key store" for the full design and the Content-Type bug. Nothing here changes: docapi's
  endpoint itself is unaware of cproxy's auth layer.

- 2026-08-25: **1.5.3 — river fish endpoint `PATCH /api/v1/river/fish/{guid}` (admin Save-JSON
  Fishing-tab "Add" form duplicate) — the service's first genuine write path outside document CRUD.**
  Native docapi duplicate of `Editor/EditLakeFish.aspx`'s "Add" form (`AddFishToLake`): body is a JSON
  array of `{fishId, link, trustLevel, year, status}` entries, batch-upserted via the new
  `dbo.sp_lake_fish_upsert_batch` (envfish-db, 2026-08-25) through a new `RiverFishCommandRepository`
  bean (Jdbc via `jdbc.execute` + manual result-set drain — same pattern as every other
  `EXEC dbo.sp_...` call in this service, not `jdbc.query`, since a proc's DML can interleave update
  counts with its final `SELECT`; in-memory returns `null`). **Deliberately narrow about what it
  writes:** a species not yet on the lake is `inserted`; one already assigned but with an empty/NULL
  `link` is `updated`; one already assigned **with** a link is `skipped` — this batch endpoint can
  never silently overwrite already-sourced data. `unknown_fish`/`invalid_fish_id` cover a
  well-formed-but-unrecognized guid and a non-guid respectively. Request validation (non-empty JSON
  array, ≤ `MAX_FISH_BATCH` = 500 entries) happens in the controller before any SQL — `RiverController`
  reuses `InvalidDocumentException` (400 `invalid_document`) rather than inventing a second validation
  path. Unknown lake guid ⇒ 404, same contract as every other river endpoint.
  **Security posture, deliberately left as-is for now:** cproxy's `CPROXY_ALLOWED_METHODS` is pinned to
  `GET` in `deploy/compose.yml` ("write surface stays 405"), and docapi itself is never publicly bound
  — so this PATCH is reachable only from inside the DigitalOcean VPC today, not from the public
  internet. Fronting it through cproxy (allowing `PATCH` + requiring `CPROXY_API_KEY`) is a follow-up
  decision, not bundled into this change. Tests: `RiverControllerTest` (+6) → **105 pass** (full
  suite). DB: `unit_test@LakeFishUpsertBatch.sql` (8 tests) passes via `autorun.bat` (full DB suite 505
  PASS / 2 pre-existing FAIL, unrelated). Docs: this file, `README.md`, `docs/specification.md`,
  `docs/api-reference.html` (per the API-change rule). **Deployed to prod 2026-08-25 as 1.5.3**
  (image `ghcr.io/balintomsk/docapi:1.5.3`, digest `sha256:01e98e89…dd66b`). `dbo.sp_lake_fish_
  upsert_batch` applied to prod first, gated on a real insert/verify/delete smoke test inside one
  transaction (committed only after the proc round-tripped correctly against "Little Somme River",
  a real lake with zero assigned species). `/health` reports 1.5.3, clean startup, full smoke matrix
  clean, breaker closed within 1 poll. `PATCH /river/fish/{guid}` verified directly against docapi
  (insert → GET confirms it → test row deleted) and — once cproxy 0.6.1 shipped with the day-key gate
  and a Content-Type-forwarding fix — through the public gateway too (see `efc-proxy` `CLAUDE.md`).

- 2026-08-25: **1.5.2 — river fish endpoint `GET /api/v1/river/fish/{guid}` (admin Save-JSON
  Fishing-tab duplicate).** Native docapi duplicate of `Editor/EditLakeFish.aspx`'s Save JSON button
  (`HandlerImage.ashx?lakejson=<guid>&tab=fishing`) — the assigned-species document for one water body
  (every `lake_fish` row: name, latin, conservation status, last-catch, external link). Backed by
  `dbo.fn_lake_fishing_json`, which **already exists in prod** (same 2026-08-13 per-tab Save-JSON
  rollout as `fn_lake_view_json`) — **no new DB object**, pure docapi addition, same shape as the
  2026-08-24 `/river/description/{guid}` entry below. `RiverQueryRepository` gained `fish(lakeId)`
  (Jdbc proxied + in-memory `null`); `NULL`/unknown guid ⇒ 404. **Access note:** same reasoning as
  `description` — the frontend export path is admin-gated, but the assigned-species list is already
  shown publicly on `Resources/wfRiverViewer.aspx`. Tests: `RiverControllerTest` (+2) → **99 pass**
  (full suite). Docs: this file, `README.md`, `docs/specification.md`, `docs/api-reference.html` (per
  the API-change rule). **Deployed to prod 2026-08-25 as 1.5.2** (image
  `ghcr.io/balintomsk/docapi:1.5.2`, digest `sha256:8a760b0c…53887a`; no DB step —
  `fn_lake_fishing_json` already live). `/health` reports 1.5.2, clean startup (no exceptions in the
  startup window, `restarts=0`). `/river/fish/{guid}` verified both directly on docapi and through
  **cproxy** (`http://<cproxy-droplet>/api/v1/river/fish/a55caadf-2892-e811-9104-00155d007b12` → 200,
  real data "Little Somme River" — the exact link that had 404'd against the still-1.5.1 prod before
  this deploy); unknown guid → 404 in both paths. Full smoke matrix re-run clean: healthy endpoints
  200 pre-breaker, doc-CRUD 500s at the documented expected state, breaker closed within 1 poll after.

- 2026-08-24: **1.5.1 — river description endpoint `GET /api/v1/river/description/{guid}`
  (admin Save-JSON View-tab duplicate).** Native docapi duplicate of
  `Editor/HandlerImage.ashx?lakejson=<guid>&tab=view` — the full description document (name/alt
  names, description text, physical stats, source/mouth detail, assigned fish, photo gallery base64)
  for one water body. Backed by `dbo.fn_lake_view_json`, which **already exists in prod** (added
  2026-08-14 for the admin Save-JSON tabs) — **no new DB object**, pure docapi addition.
  `RiverQueryRepository` gained `description(lakeId)` (Jdbc proxied + in-memory `null`); `NULL`/unknown
  guid ⇒ 404, mirroring `/news/export/{id}`. **Access note:** the frontend export path is
  admin-gated, but the content itself is the same public data `Resources/wfRiverViewer.aspx` already
  shows anonymous visitors — the gate is about that download convenience, not sensitivity, so a public
  docapi GET matches this service's existing (unauthenticated) surface. Tests: `RiverControllerTest`
  (+2) → **97 pass**. Docs: this file, `README.md`, `docs/specification.md`, `docs/api-reference.html`
  (per the API-change rule). **Deployed to prod 2026-08-24 as 1.5.1** (image
  `ghcr.io/balintomsk/docapi:1.5.1`, digest `sha256:7afcaabb…deee`; no DB step — `fn_lake_view_json`
  already live). `/health` reports 1.5.1, clean startup; `/river/description/{guid}` verified both
  directly on docapi and through **cproxy** (`http://<cproxy-host>/api/v1/river/description/{guid}`)
  — 200 with real data (Undersill Lake) for a known guid, 404 for an unknown one, 405 on POST. No
  cproxy redeploy needed (generic `/api/*` passthrough); its `docs/api-guide.html` updated to match.
- 2026-08-24: **1.5.0 — river endpoint `GET /api/v1/river/unfished` (wbUnFish.aspx duplicate).** Returns
  the next un-processed water body of a type in a state (no fish assigned, not flagged No Fish) —
  `{ found, country, state, river, lake_id, lake_name, mouth_name, CGNDB, throwing }` — a native docapi
  duplicate of the frontend `Resources/wbUnFish.aspx` endpoint the add-fish tooling uses. `country`
  echoed only; bad `country`/`state`→default, bad `river`→2 (mirrors the page; no 400s). New
  `RiverController` + `RiverQueryRepository` (interface + proxied `Jdbc…` with `sqlRetry`/`sqlBreaker` +
  in-memory default); not cached. **DB (envfish-db):** new `dbo.fn_river_unfished_json(@country,@state,@river)`
  in `script02_Funct.sql` (TOP-1 `vw_lake` query mirroring the page + `STRING_AGG` throwing from
  `Tributaries side=2`; raw-table access kept inside the DB), `unit_test@RiverUnfished.sql` 4 tests pass
  via `autorun.bat`. Tests: `RiverControllerTest` (+4) → **95 pass** (incl. this session's fish-code work).
  **Deployed to prod 2026-08-24 as 1.5.0** in order: DB function applied via `sqlcmd` (verified
  `CA/NL/2` → "Adies River", matches the raw wbUnFish query) → image `ghcr.io/balintomsk/docapi:1.5.0`
  (digest `sha256:87480f68…`) deployed with the VPC dual-bind. Verified end-to-end through **cproxy**
  (`http://<cproxy>/api/v1/river/unfished?country=CA&state=NL&river=2` → real data). cproxy needs no
  change — it already forwards GET `/api/*`.
- 2026-08-04: **Fish search endpoint `GET /api/v1/fish/search?q=`.** Relevance-ranked species search
  over the primary name, Latin name, and `alt_name` synonyms — the **same lookup the Editor
  `FishList.aspx` search box uses**, so "rosefish" / "ling" resolves to the right species even when it
  isn't the primary name. Backed by `dbo.SearchFishList` (a `varchar(64)` TVF that normalizes the term
  itself and ranks by `irank`, best-first) — it **already exists in prod**, so this is a **docapi-only
  change with NO DB object to create/apply**. New `FishQueryRepository` (interface + `Jdbc…` proxied
  bean with `sqlRetry`/`sqlBreaker` + in-memory default); **not cached** (open-ended key, so no
  `@Primary`/cache layer like `/news/list`). `FishSearchItem` = (fishId, name, latin, rank — lower is
  better, 0 = exact); term trimmed + capped at 64; blank/missing `q` ⇒ 400; literal `/search` matched
  ahead of `/{id}`. Tests: `FishControllerTest` (+7) → **76 pass**. Docs: this file, `README.md`,
  `docs/specification.md`. **Deployed to prod 2026-08-04 as 1.4.0** (image
  `ghcr.io/balintomsk/docapi:1.4.0`, digest `sha256:7c7a962c…`; **no DB step** — `SearchFishList`
  already live). `/health` reports 1.4.0; startup clean, Tomcat 8080 + 8082, jdbc profile;
  `/fish/search?q=pike` → 200 with ranked real rows ("Pike, Northern" rank 1 first), `q=rosefish`
  resolves via synonym to "Acadian redfish"; the four doc-CRUD `/{id}=1` endpoints still the
  documented expected 500s; breaker polled closed; GHCR logout on both machines.
- 2026-08-02: **1.3.1 — management/Actuator port moved 8081 → 8082.** `management.server.port` in
  `application.yml` (still private/unpublished; only `/health` on 8080 is externally probed). Docs +
  the `update-docapi` skill/`do-update.md` updated so startup verification expects `Tomcat started on
  port 8082`. **Deployed to prod 2026-08-02** (image `ghcr.io/balintomsk/docapi:1.3.1`; `/health`
  reports 1.3.1; startup shows Tomcat 8080 + 8082; healthy endpoints incl. `/news/search` → 200).
- 2026-08-02: **1.3.0 — news search endpoint `GET /api/v1/news/search?q=`.** Up to 100 published
  matches, newest first, over headline/source/paragraphs/photo-alts **and the up-to-3 mentioned fishes'
  names** — so "walleye" finds an article tagged with walleye even when the headline doesn't say it.
  Compact `NewsSearchItem` (newsId, title, source, stamp, country, fishes[]); blank `q` ⇒ 400; not
  cached (`NewsQueryCache.search` reads through). DB side: `dbo.fn_news_search(@q)` (envfish-db, inline
  TVF over news + `fish ×3` LEFT JOIN, published-only, `LIKE '%@q%' ESCAPE '\'` with the caller
  escaping `% _ [`; `unit_test@NewsSearch.sql`, 4 tests incl. match-by-fish-name). Also applied the two
  missing write procs `sp_news_doc_add` / `sp_news_doc_update` so POST/PUT are backed. Tests: 69 pass.
  **Deployed to prod 2026-08-02** (3 DB objects applied via SqlClient txn first — `fn_news_search`,
  `sp_news_doc_add`, `sp_news_doc_update`; the read side + `sp_news_import` were already live; image
  `ghcr.io/balintomsk/docapi:1.3.0`; `/health` reports 1.3.0; `/news/search?q=fish` → 200 with real
  matches + associated fishes; full smoke matrix as expected).
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
