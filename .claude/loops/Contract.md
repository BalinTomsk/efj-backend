# Loop Contract - EFJ Backend

Safety guardrails for Java backend automation loops.

## Stop Conditions (Non-Negotiable)

- **Never deploy without explicit user approval** — ask first, wait for "yes"
- **Stop on permission denial** — never retry or work around
- **Stop on Maven/Gradle build failures** — don't ignore compilation errors
- **Stop on test failures** — let user decide on fixes
- **Stop on Docker/container errors** — verify image before pushing
- **Max 5 retries per task** — no infinite loops

## Tone & Scope

- **Terse output** — no trailing summaries
- **Commit-first** — no uncommitted work
- **Test before shipping** — run unit + integration tests locally
- **Verify prod schema** — don't assume main branch is current
- **No force-push** — clean merge only

## Secrets & Safety

- **Never commit credentials** — use `.env.local` (gitignored)
- **No automated prod deploys** — user approval required
- **No direct prod DB writes** — test locally first
- **Container images: scan before push** — no secrets in images

## Scope for This Project

- **Java/Spring Boot code** — microservices, APIs
- **SQL operations** — read-only; DDL/DML needs approval
- **Maven builds** — local testing only
- **Docker/Kubernetes** — local minikube or staging only

## Database & Schema

- **Verify prod schema before any change** — compare live vs. committed migrations
- **Test migrations on local DB first** — use stub data
- **JPA/Hibernate gotchas** — verify mapping before deploy
- **Connection pooling** — don't exhaust connections in loops

## When to Loop

**Loop for:** iterating fixes, retrying CI, running tests repeatedly
**Single-shot for:** one-time features, architectural changes
