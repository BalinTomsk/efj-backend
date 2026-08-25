# docapi Changelog

Split out of `CLAUDE.md` for readability. Newest entries first.

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
  **cproxy** (`http://159.89.113.225/api/v1/river/fish/a55caadf-2892-e811-9104-00155d007b12` → 200,
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
