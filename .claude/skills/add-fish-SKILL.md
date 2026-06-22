---
name: add-fish
description: >
  Assigns fish species to river water bodies via the fishfind.info API — faster than the
  browser-based assign-fish skill. Use when the user says "add fish via API", "run add-fish",
  "process fish API", "assign fish automatically", or wants to populate unprocessed rivers
  using API endpoints. Calls wbUnFish.aspx to get the next unprocessed river, searches the
  web for fish species, then POSTs to wbAddFish.aspx — no browser or authentication needed.
---

# add-fish

Assign fish species (or No Fish) to rivers using the fishfind.info JSON API.
All endpoints are public — call them directly with curl from the shell. No browser session,
no cookies, no Claude-in-Chrome required.

Repeat the full loop until no more unprocessed rivers remain.

## Step 1 — Get next unprocessed river

```bash
curl -s "https://fishfind.info/Resources/wbUnFish.aspx?Country=CA&State=ON&River=2"
```

**Parameters** — adjust to the target region:
- `Country`: two-letter ISO code (e.g. `CA`, `US`)
- `State`: province or state code (e.g. `ON`, `QC`, `BC`, `NY`)
- `River`: body type — `2` = river/stream, `1` = lake (use `2` for this skill)

Response shape:
```json
{
  "found": true,
  "lake_id": "5613f1e0-...",
  "lake_name": "Barnaby River",
  "mouth_name": "Southwest Miramichi River",
  "CGNDB": "DAVYE",
  "country": "CA",
  "state": "ON",
  "river": 2
}
```

If `found` is `false` or the response is empty → stop, all rivers processed.

The response may also include a `throwing` field — a comma-separated list of CGNDB codes for lakes
that this river flows through:

```json
{
  "found": true,
  "lake_id": "0c4c3795-...",
  "lake_name": "Resinosa River",
  "mouth_name": "Elbow Lake",
  "CGNDB": "FCKRM",
  "throwing": "FDDHE"
}
```

If `throwing` is present and non-empty, proceed to **Step 1b** before researching fish.

## Step 1b — Resolve lakes from the `throwing` field (only if present)

If the river response includes a `throwing` field, look up each CGNDB code in it to get the
lake's `lake_id`. Use the same `wbUnFish.aspx` endpoint but with `River=1` (lake body type):

```bash
curl -s "https://fishfind.info/Resources/wbUnFish.aspx?Country=CA&State=ON&River=1&CGNDB=FDDHE"
```

This returns the lake record (same shape as Step 1). Collect the `lake_id` and `lake_name` for
each lake — you'll need them in Step 3b and Step 4c.

If a CGNDB lookup returns `found: false` or fails, skip that lake and continue.

## Step 2 — Read toponymy info (optional)

```bash
curl -s "https://toponymes.rncan.gc.ca/search-place-names/unique?id=DAVYE"
```

Returns official name, province, and feature type. Useful for disambiguating rivers with
common names. Skip if not needed.

## Step 3 — Research fish species

Search the web for fish in **[lake_name]**. Good sources: Wikipedia, Fishbrain, Anglers Atlas.
**Exclude HookandBullet** entirely.

### Source confidence rules

Only add a species if at least one source **explicitly names the exact water body being processed**.
Neighboring water bodies (including the mouth lake/river), watersheds, regions, and province-wide
lists do not count — even if the river is a tributary of a well-documented lake or flows through
a famous fishing area. If no source names this specific river, mark No Fish.

Rank sources by reliability:
1. **Tier 1** (strongest): Government surveys, provincial fish inventories, university studies,
   DFO (Fisheries and Oceans Canada) records, state/province fish atlases
2. **Tier 2** (good): Wikipedia with an inline citation naming this specific river, Anglers Atlas
   with location-tagged catches on or near this river
3. **Tier 3** (use with caution): Fishbrain catch reports — only count if the catch is pinned to
   this specific river, not just the general area

If sources conflict, prefer Tier 1. If all available sources are Tier 3 only, mark No Fish rather
than risk polluting the database with unreliable guesses.

### Disambiguating common river names

Many rivers share names (e.g., "Salmon River", "Black Creek"). When search results are ambiguous:
- Include the province/state and `mouth_name` in your search query:
  `"Barnaby River" "Miramichi" fish species`
- Use the CGNDB code with toponymy (Step 2) to confirm you are reading about the right river
- If you still cannot confirm which river the source refers to, treat it as no evidence

Collect Latin (scientific) names for all confirmed species.

## Step 3b — Research fish in throwing lakes (only if Step 1b ran)

For each lake resolved in Step 1b, search the web for fish species in that lake using the same
source confidence rules as Step 3. Collect confirmed species (Latin names) per lake.

Also **merge** the lake fish into the river's species list: any fish confirmed for a throwing lake
should be included when assigning fish to the river (Step 4b), since the river flows through that
lake. Deduplicate across lakes and the river's own findings.

## Step 4a — If no fish found

```bash
curl -s -X POST "https://fishfind.info/Resources/wbAddFish.aspx" \
  -H "Content-Type: application/json" \
  -d '{"lake_id": "5613f1e0-...", "NoFish": true}'
```

Then loop back to Step 1.

## Step 4b — If fish found

```bash
curl -s -X POST "https://fishfind.info/Resources/wbAddFish.aspx" \
  -H "Content-Type: application/json" \
  -d '{"lake_id": "5613f1e0-...", "fish": [{"fish": "Salmo salar"}, {"fish": "Esox lucius"}]}'
```

Successful response shape:
```json
{
  "lake_id": "...",
  "results": [
    { "input": "Salmo salar", "fish": "Salmon, Atlantic", "status": "added" }
  ],
  "added": 1,
  "isFish": true
}
```

Rules:
- Use Latin (scientific) names only in the `fish` field — the API resolves them to common names
- Include all confirmed species; don't guess or pad
- Always assign to the river (lake_id from Step 1), not its mouth waterbody
- Check `status` in each result item — handle per the table below

## Step 4c — Assign fish to throwing lakes (only if Step 1b and 3b ran)

For each throwing lake that has confirmed fish (from Step 3b), POST to assign those fish to that
lake using its `lake_id`:

```bash
curl -s -X POST "https://fishfind.info/Resources/wbAddFish.aspx" \
  -H "Content-Type: application/json" \
  -d '{"lake_id": "<throwing-lake-id>", "fish": [{"fish": "Salmo salar"}]}'
```

If a throwing lake had no fish found, POST `NoFish` for it:

```bash
curl -s -X POST "https://fishfind.info/Resources/wbAddFish.aspx" \
  -H "Content-Type: application/json" \
  -d '{"lake_id": "<throwing-lake-id>", "NoFish": true}'
```

Handle response statuses the same way as Step 4b. Do Step 4c **before** looping to Step 5 so
that all throwing lakes are processed within the same river iteration.

### Handling individual species result statuses

| status | Meaning | Action |
|---|---|---|
| `added` | Success | Nothing to do |
| `duplicate` | Already in DB | Normal — skip |
| `not_found` | Latin name not in API taxonomy | Try the common name as fallback; if still not_found, log and skip |
| `error` | API-side failure | Retry once; if still failing, log and skip |

A river is considered processed even if some species returned `not_found` — what matters is the
POST succeeded and the river is no longer in the unprocessed queue.

## Step 5 — Loop and track progress

After each river, immediately loop back to Step 1 without waiting for user input. Keep a running
tally and report it after every 5 rivers (or at natural stopping points):

```
✓ Barnaby River (ON) — 3 species: Atlantic Salmon, Brook Trout, Brown Trout
✓ Beaver Creek (ON) — No Fish
✓ Resinosa River (ON) — 2 species: Walleye, Northern Pike  [+ 1 throwing lake: Elbow Lake (2 species)]
...
Session total: 12 processed | 9 with fish | 3 No Fish | 4 throwing lakes processed | 2 species not_found (logged)
```

Stop the loop when Step 1 returns `found: false` or the response is empty, and report the
final session summary to the user.

## Error handling

- Step 1 returns `found: false` or empty → stop, all done
- curl error or non-200 response → retry once; skip river if still failing
- Toponymy (Step 2) fails → skip and proceed with the river name alone