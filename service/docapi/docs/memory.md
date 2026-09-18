# docapi Session Memory

## 2026-09-18: droplet CPU incident — docapi was the victim, not the cause

`debian-jnode` sat at 99% CPU. Resizing it did not help, for two independent reasons:

1. **The resize added RAM, not cores.** `nproc` still reports **1**. The droplet is 1 vCPU / 2 GB and
   runs `docapi`, `water-station-pusher` and `weather-station-pusher` **on that one core**. Check
   `nproc` before believing a resize took effect.
2. **Two sibling containers were crash-looping**, and between them they held the core at 100%:
   - `weather-station-pusher` 1.15.1 — Spring could not instantiate `OpenMeteoConverter`: a
     `@Component` with two public constructors and no `@Autowired`, so it fell back to a no-arg
     constructor that does not exist. It had restarted ~800 times over 4.5 hours and had **never once
     started successfully**. Fixed and redeployed as 1.15.2.
   - `water-station-pusher` — `AccessDeniedException: /run/secrets/waterservice.env`. Still stopped;
     see the env-file collision below.

docapi itself was healthy throughout: `restarts=0`, ~0% CPU, `/health` answering. Nothing about this
incident was a docapi bug — but a saturated core degrades it all the same, which is why
`do-update.md` Step 10b now checks droplet load and sibling containers after a docapi deploy.

**Two traps worth keeping:**

- **A log tail cannot detect a crash loop.** Every restart prints a fresh, healthy-looking Spring
  banner, so `docker logs --tail 100` showed a clean boot for 4.5 hours. Verify with
  `docker inspect --format '{{.RestartCount}}'` read twice, and with
  `docker logs | grep -c 'Started <App>'` (must be 1). All three `do-update.md` files now lead with
  this.
- **Docker's restart backoff never engaged.** It only backs off when a container dies within 10s of
  starting; Spring Boot got ~13s in (Tomcat + context init) before failing, resetting the backoff
  every time. A loop like that restarts ~3×/min forever at ~100% CPU.
- **`RestartCount` under-reports.** It resets on daemon restart / droplet reboot — it read 32 while the
  log showed 803 starts. Check both.

**Env-file collision (unfixed, needs a decision).** `weather-station-pusher` mounts
`/mnt/volume_jnode/waterservice/waterservice.env` — *water's* file — and its `do-update.md` Step 5
chowns it to uid **1001**; waterservice's Step 5 chowns the same file to **10001**. Mode is `0400`, so
whichever deployed last works and the other breaks on its next restart. `weatherservice/weatherservice.env`
already exists owned by 1001 and is missing only `WUNDERGROUND_API_KEY` (copyable as its `enc:v1:` line,
no decryption needed). Both `do-update.md` files now carry the warning; the split itself is not done.

## 2026-09-18: Cache sizes moved to YAML (v1.15.2)

**Status:** Built, tested (241/241 passing), documented. NOT DEPLOYED.

The bounds from 1.15.0 are no longer constants — `docapi.cache.*`, bound by
`config/NewsCacheProperties`, registered via `@EnableConfigurationProperties` on `JdbcStoreConfig`.
Keys: `news.document` (25), `news.miss` (500), `news.list` (100), `news.export` (25), `news.search`
(25), `news.photo` (25), `fish` (25), `water-body` (25). Defaults reproduce the old constants exactly.

**Why it matters operationally:** 1.15.0 documented 25 as "the first number to lower if docapi starts
pressuring heap" and then made it a constant, so acting on that meant a rebuild + redeploy. It is now
`docker run -e DOCAPI_CACHE_NEWS_EXPORT=10` and a restart. `do-update.md` Step 10z is the runbook.

**Version skips 1.15.1 deliberately** — that GHCR tag is taken (see below), and reusing a tag destroys
its rollback point.

**Trap worth remembering:** the test asserting the runbook's *environment-variable* names bind
(`DOCAPI_CACHE_WATERBODY` for `docapi.cache.water-body`) caught a wrong claim in the doc as it was
written. Spring only applies env-var name mapping to a property source literally named
`systemEnvironment`, so a test using any other source name silently proves nothing.

---

## 2026-09-17: LRU Caching for News Read Endpoints (v1.15.0)

**Status:** Built, tested (237/237 passing), documented. **DEPLOYED as image tag `docapi:1.15.1`.**

⚠️ **The image tag and the reported version disagree.** `ghcr.io/balintomsk/docapi:1.15.1` was built
from the 1.15.0 pom, so the running container answers `{"status":"UP","version":"1.15.0"}` under a
`1.15.1` tag. Confirmed live on the droplet 2026-09-18. Do not read `/health` as the image tag.

### What Changed

Five read-only news endpoints got bounded LRU caches (size 25 each):
- `/news/export/{id}` — key: lowercase id
- `/news/photo/{id}` — key: lowercase id
- `/news/search` — key: `query|sorted fishIds|country|offset|limit`
- `/news/lake/{guid}` — key: `guid|limit`
- `/news/fish/{guid}` — key: `guid|limit`

### Implementation Details

**[src/main/java/com/fishfind/docapi/repo/NewsQueryCache.java](../src/main/java/com/fishfind/docapi/repo/NewsQueryCache.java)**
- Added five new bounded LRU maps: `exportDocs`, `searches`, `lakePages`, `fishPages`, `photos`
- Generic `cached(map, key, loader)` helper implements striped locks (16 stripes) + double-check pattern for single-flight loading under concurrency
- All five LRUs use `LRU_ENTRIES = 25` (matches `NewsDocumentCache` existing size for `GET /news/{id}`)
- Misses (null results) are NOT stored — a 404 costs a round trip each time, but export/photo are day-key gated at cproxy, so not crawlable
- Search terms are case-sensitive (response echoes verbatim); IDs are case-insensitive (matching MySQL collation)
- Species IDs in search keys are sorted for cache coalescing
- `clear()` empties all nine caches; `sizes()` returns 9 elements (was 4: us, ca, other, default; now adds export, search, lake, fish, photo)

**Other unchanged:**
- `OTHER_ENTRIES` (`/news/list` LRU) remains at 100 (not reduced to 25)
- `NewsDocumentCache` unchanged (60s miss-TTL for `GET /news/{id}`, crawlable)
- Single-flight behavior for cachedPage carried forward via refactored `cached()` helper

### Tests

**[src/test/java/com/fishfind/docapi/repo/NewsCacheTest.java](../src/test/java/com/fishfind/docapi/repo/NewsCacheTest.java)**
- Grew from 27 to 41 tests
- New tests: exportIsReadOnceThenServedFromItsLruCache, exportKeysAreCaseInsensitiveSoOneArticleIsOneEntry, exportCacheKeepsOnlyTheLastTwentyFive, anUnknownIdIsNotCachedSoItIsRetriedRatherThanRememberedAsMissing (with NullRepo)
- Added photoIsReadOnceThenServedFromItsLruCache, photoCacheKeepsOnlyTheLastTwentyFive
- Added searchIsReadOnceThenServedFromItsLruCache, eachPageOfOneSearchIsItsOwnEntryAndTheTermIsNotCaseFolded, speciesIdOrderDoesNotSplitOneSearchAcrossTwoEntries, searchCacheKeepsOnlyTheLastTwentyFive
- Added lakeNewsIsReadOnceThenServedFromItsLruCache, aDifferentLimitIsADifferentLakeEntryRatherThanATruncatedHit, lakeCacheKeepsOnlyTheLastTwentyFive
- Added fishNewsIsReadOnceThenServedFromItsLruCache, fishCacheKeepsOnlyTheLastTwentyFive
- Added aColdPerRequestEntryIsAlsoLoadedOnlyOnceUnderAStampede for export/search/photo (concurrent load testing)
- SlowRepo extended with exportNews, search, newsPhoto overrides to simulate delays
- All 237 tests passing

### Heap Cost

**Measured live data (2026-09-12/2026-09-17):**
- Photos: 525,222 bytes typical → ~13 MB for full 25-entry LRU
- Export documents: 512,506 bytes on wire, parsed as JsonNode → ~1–1.5 MB each → ~25–35 MB full LRU

**JVM memory:** Container sets no `-Xmx` (`JAVA_OPTS=""`), so JVM defaults to 1/4 of container memory. Heap cost is first tuning knob if memory pressure rises.

### Documentation

**docapi:**
- [CLAUDE.md](../CLAUDE.md) — updated news-caching table to document export, search, lake, fish, photo caching; updated "Deliberately uncached" section with rationale
- [specification.md](../docs/specification.md) — replaced stale "not cached" / "deliberately uncached" claims with 1.15.0 caching note + detailed miss-cost rationale
- [do-update.md](../docs/do-update.md) — added caching note: time first call not second when verifying deploys
- [api-reference.html](../docs/api-reference.html) — major updates: caching intro section with GET endpoint table, per-endpoint caching notes, callout on unknown IDs never cached, timing consequences
- Version bumped pom.xml 1.14.0 → 1.15.0
- CHANGELOG.md entry documenting all changes + heap implications

**cproxy:**
- [api-guide.html](../../cproxy/docs/api-guide.html) — added "Upstream caching" callout in News section noting docapi 1.15.0 not deployed, timing consequences
- [gen-postman.py](../../cproxy/docs/gen-postman.py) — export request description updated with caching note (~2s baseline, milliseconds on repeat)
- postman-collection.json regenerated from gen-postman.py (corrected after initially hand-editing JSON; per cproxy CLAUDE.md, always regenerate from Python, not vice versa)

### User Intent & Rationale

**Root cause:** `GET /api/v1/news/export/{id}` taking 2s was not missing application cache, but cold TCP connections to Winhost MySQL (pool `minimumIdle=0`, `idleTimeout=15s` on quiet minutes).

**Trade-off resolved:** Old reasoning priced miss rate in isolation (expensive if crawled, cheap if rare). New reasoning counts cold-connection cost: a 25-entry LRU holding ~26–48 MB of heap (photos + exports) buys back the 2s baseline and keeps crawlers/quiet-period clients at millisecond latencies on repeat calls. Misses (unknown IDs) stay expensive by design—they're not crawlable at cproxy (day-key gated), and remembering them for 60s would risk stale state in a news feed.

### Known Gaps

1. **~2s figure unverified in prod.** Only measured indirectly and via cproxy gate (45ms baseline). Re-measure with real token after deploy to confirm the split between cold connection + application latency.
2. **Heap monitoring.** No alerting on cache eviction churn or heap pressure. Watch GC logs early after deploy.
3. **Postman timing.** Collection documents ~2s baseline + millisecond repeats; confirm with live endpoint after deploy.

### Deployment

Use `.claude/skills/update-docapi` to deploy 1.15.0. The change is backward-compatible (adds caches, does not modify API contract or response shape). First call after deploy will be slow; subsequent calls within 25-request window will be cached.
