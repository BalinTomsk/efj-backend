# CLAUDE.md — Database (all services)

Guidance for Claude Code when changing the database for **any** Fish Find service.
This folder holds the SQL Server schema (`mssql/`) and the MySQL variant (`mysql/`).
Everything below is about `mssql/` unless stated otherwise.

## Golden rule: never edit the generated file

- **Make all schema changes in the `scriptNN_xxxxxx.sql` source files** under `mssql/`.
- **`mssql/ffi2.sql` is GENERATED — do not hand-edit it.** It is rebuilt from the
  `scriptNN` files by `mssql/generate_db_script_ffi2.cmd` and is the image consumed by
  the database unit tests. Any manual edit to `ffi2.sql` is overwritten on the next build.

## How `ffi2.sql` is generated

`generate_db_script_ffi2.cmd` concatenates these source files **in this order** into
`ffi2.sql`:

1. `script0.sql`              — DB/header preamble
2. `script01_createTable.sql` — tables, PKs, constraints, indexes
3. `script01_createView.sql`  — views
4. `script02_Funct.sql`       — scalar / table-valued functions
5. `script02_Proc.sql`        — stored procedures
6. `script08_Data.sql`        — seed/reference data
7. `script09_fish_data.sql`   — fish seed data
8. `script10_Data_limit.sql`  — rate-limit / misc data
9. `script20_Migration.sql`   — migrations applied after the base schema

Because concatenation is **append-only and ordered**, put each object in the right file
and respect dependencies (a proc that uses a new table must come after that table — i.e.
table goes in `script01_createTable.sql`, proc in `script02_Proc.sql`).

**Files NOT in the generated image** (editing them does not affect `ffi2.sql` or the unit
tests): `script01_createView.sql` IS included, but `script07_createLakeRiver.sql`,
`scriptA100_fillForecast.sql`, `fisheditor.sql`, `lakeeditor.sql`, and the `*_dump.sql`
files are standalone and are **not** concatenated. Don't rely on them for test coverage.

### Where each kind of change goes
- New / altered **table, index, constraint** → `script01_createTable.sql`
- New / altered **view** → `script01_createView.sql`
- New / altered **function** → `script02_Funct.sql`
- New / altered **stored procedure** → `script02_Proc.sql`
- **Seed / reference data** → `script08_Data.sql` (or `script09_fish_data.sql` for fish)
- **Moving DATA between databases / one-off backfills against a live DB** → `script20_Migration.sql`

**DDL belongs in the schema scripts, not the migration script.** `script20_Migration.sql` is for
*data* migration between databases. Do NOT put `CREATE TABLE` / `ALTER TABLE` / `CREATE PROCEDURE`
there — the table goes in `script01_createTable.sql`, the procedure in `script02_Proc.sql`, etc.
Those schema scripts already produce the final shape, so a fresh build needs nothing from the
migration script. Any one-off backfill placed in `script20` is transient: once it has been run
against the target database, remove it (it is not a permanent record of the schema).

Procs/functions use the idempotent `IF EXISTS (... ) DROP ... GO  CREATE ...` pattern —
follow it so the script is re-runnable.

### Idempotency (which scripts are safe to re-run)
- **`script01_createView.sql`, `script02_Funct.sql`, `script02_Proc.sql` are idempotent — they can
  be run any number of times against an existing database without errors and without applying or
  adding anything new on each run.** Every object drops-then-recreates itself (`IF EXISTS … DROP …
  GO CREATE …`), so re-running just refreshes the definitions. When editing these scripts, keep that
  property: each view/function/procedure must guard its `CREATE` with a matching drop.
- By contrast, `script01_createTable.sql`, `script08_Data.sql` / `script09_fish_data.sql`, and
  `script10_Data_limit.sql` are **not** re-runnable as-is (they `CREATE TABLE` / `INSERT` without
  guards) — they are meant for building a fresh database, not for re-applying to a live one.

## OAuth / external logins (`UserExternalLogin`)

OAuth identities live in their own table, **not** in `Users`. `dbo.UserExternalLogin` holds one row
per `(provider, providerUserId)` and FKs to `Users.id`; `Users.authType` is `'Local'` or `'OAuth'`.

- **Adding a provider** = widen the `CH_UEL_provider` CHECK constraint in `script01_createTable.sql`
  (`provider IN ('Google','Twitter','LinkedIn','Outlook','GitHub','Email', …)`). Wired up so far: **Google, Twitter, LinkedIn, Outlook, GitHub, Email** (magic link — one-time tokens in `EmailLoginToken`, see `script01_createTable.sql`).
- **`dbo.spOAuthLoginOrCreateUser`** (in `script02_Proc.sql`) is the single entry point the web app
  calls for **every** provider — keep its signature stable so no C# change is needed. It looks up by
  `(provider, providerUserId)`, else links to an existing `Users.email`, else creates the user, then
  inserts the `UserExternalLogin` link row.
- **Emailless providers:** every `Users` row needs a unique email, but some providers don't expose one
  (the **Twitter/X OAuth2 API has no email scope**). The web caller passes a **synthetic**
  `twitter_<id>@users.fishfind.info` address. The proc sets `userName` to the provider's
  **display name** (`@givenName` + `@familyName`, or the @handle for X) for **every** provider,
  including Google, falling back to the email only when no name is supplied. A returning login
  also **self-heals** a `userName` still stored as the email (legacy Google rows) to the display
  name. (Until 2026-06-13 Google was special-cased to keep the email as `userName`.)
- Cover any new provider in `mssql/UNIT_TESTS/unit_test@OAuthLogin.sql`.

## Running the database unit tests

1. `cd mssql\UNIT_TESTS`
2. Run `autorun.bat`. It will:
   - regenerate `ffi2.sql` (via `generate_db_script_ffi2.cmd`),
   - create a fresh temp database from it (`dbcreator.cmd`),
   - run every `unit_test@*.sql` in the folder (`autorunlocal.bat` → `scriptrunlocal.bat`),
   - verify output with `averify.py`,
   - drop the temp database.
3. **Check `mssql\UNIT_TESTS\cleaned.txt` for errors.**

**Reading `cleaned.txt`:** a clean run contains only
(a) test-file name headers (`unit_test@Foo.sql`),
(b) `Unit tests for …` banner lines, and
(c) `TEST n PASS [..ms]: …` lines.
Anything else is a failure — look for `FAIL`, SQL `Msg ####, Level ## …`, RAISERROR text,
or stack/exception lines. `cleaned.txt` is filtered (PASSED/row-count/warning/dash/blank
lines are stripped), so noise is already removed; treat any unexpected line as a real error.

`averify.py` also computes `md5(cleaned.txt)` and compares it to `[mail].crcstate` in
`config.ini`; on a mismatch it emails the configured recipient. So after **intentionally**
adding or changing tests (which legitimately changes the output), the stored `crcstate`
must be updated — otherwise every run keeps reporting a diff.

### Prerequisites
- `SQLCMD.EXE` on PATH, a reachable SQL Server (`config.ini → server`, default `localhost`,
  Windows auth `-E`), and `python` (uses `configparser`, runs on Py3).
- Settings live in `mssql/UNIT_TESTS/config.ini` (`[app]` server/script/dbmaker, `[mail]`).
- **`NoDefaultCurrentDirectoryInExePath` must be unset.** These batch files `call` each other by
  bare name (`call autorun.bat` → `generate_db_script_ffi2.cmd` → `dbcreator.cmd` → `autorunlocal.bat`),
  which relies on cmd searching the current directory. Some shells (incl. the Claude Code harness)
  set `NoDefaultCurrentDirectoryInExePath=1`, which disables that and makes every call fail with
  `'xxx' is not recognized`. Clear it for the run, e.g. from PowerShell:
  `cmd /c "set NoDefaultCurrentDirectoryInExePath=&& pushd mssql\UNIT_TESTS && call autorun.bat"`.
- The FishImage test prints `[Nms]` timings, so `cleaned.txt` changes every run and `averify.py`
  emails on each run — that crc churn is expected and not an error.

## Writing unit tests (`mssql/UNIT_TESTS/readme.md`)
- Use **real tables — no stubs**; you may use a table as a value/fixture.
- A test must **not leave the database in a changed state** when it finishes (clean up).
- Normal success output is a **single line** per assertion, e.g.
  `TEST 5 PASS: fn_fish_image_handler returned correct image binary`.
- Add new tests for new schema objects, then re-run `autorun.bat` and confirm `cleaned.txt`.

## Secrets
- `mssql/UNIT_TESTS/config.ini` contains **live SMTP credentials** under `[mail]`.
  Do **not** copy those values into other files, commits, or logs.

## Typical change checklist
1. Edit the correct `scriptNN_xxxxxx.sql` source file(s) — never `ffi2.sql`.
2. Add/extend a `unit_test@*.sql` covering the change.
3. Run `mssql\UNIT_TESTS\autorun.bat`.
4. Open `mssql\UNIT_TESTS\cleaned.txt` and confirm no error lines (only headers/banners/PASS).
5. If output legitimately changed, update `[mail].crcstate` in `config.ini`.
