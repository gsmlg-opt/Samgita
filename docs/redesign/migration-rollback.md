# Migration and compatible rollback

This is an operator runbook, not authorization to run a production migration or deployment. The management UI adds no schema migration. P3 and P4 expansion migrations remain additive and forward-only; the historical main migration sources remain verbatim. Local qualification uses PostgreSQL 16, isolated `samgita_redesign_*_test` databases, fake services and no live secrets.

## Before any target cutover

1. Inventory the actual release, schema versions, both historical Repo migration histories, pgvector/memory storage, external processes, durable jobs and opaque artifact references. The restored source manifest in `test/fixtures/redesign/migration-sources.json` is not a deployment inventory.
2. Back up all storage and rehearse restoration into an isolated database. Record ID/reference/content digests before and after. Existing UUIDs remain canonical; `git_url` remains provenance. Repository associations and aliases never rekey, merge or transfer Project history.
3. Fence every old writer, timer, recovery hook, cron and worker before changing authority. Drain or explicitly quarantine retained jobs without deleting them. A cancelled Oban job does not prove a remote effect stopped. An unguarded historical binary is not a rollback candidate.
4. Apply expansion migrations with execution admissions closed. Review unresolved migration ledger entries, unadopted Tasks, relationship conflicts and execution holds. Repeated mapping must retain IDs and be idempotent. Do not reset the database or run down migrations.
5. Configure external versioned credential references and approved destinations, then verify the exact enabled Agent profiles and GitHub installation with read-only permissions. Registration alone starts nothing. Capability approval does not grant Project roles.
6. Activate only after recorded evidence establishes sole Hub authority and resolved prior effects. `POST /api/platform/activate` validates the authority version, mapping/Task/Attempt holds, configured lease key and legacy-job inventory. Operator attestations do not independently prove all old nodes are fenced.

Full dual-Repo/pgvector backup/restore, target-specific old-writer exclusion and external-provider conformance remain mandatory target gates. The local sentinel fixture does not clear them. The current manifest is **not deployable** for a target with those gates unresolved.

## Close authority and reconcile

Read `GET /api/platform` and submit `POST /api/platform/close` with a fresh UUID `command_id`, its `expected_version` and a reason. Closing takes the exclusive authority lock, changes owner to `none`, closes admissions and increments the execution epoch. Active Attempts become terminal with durable Task/capacity holds; delivery leases are fenced. Stale proofs, workers and callbacks cannot commit.

Keep the same schema and a guard-aware build available for read-only inspection. Closure never undoes remote Git/tool effects or constitutes cessation evidence. Inspect Task Attempts, progress, artifacts, event acknowledgements and administrative recovery history. An execution hold requires authenticated outcome/cessation evidence or an explicit audited operator resolution through the existing Attempt resolve API. Reopening a Task, reconnecting a socket or seeing a healthy HTTP endpoint cannot clear the hold.

Notification uncertainty is separate from execution uncertainty. Reconcile the original delivery `operation_id` by status query. Never blindly resend after an ambiguous disconnect. Explicit recovery records reason, evidence and any acknowledged duplicate-effect risk; it keeps the event ID and creation time. A dead letter or authentication failure is visible and is not successful notification or Task acceptance.

Before Hub writes, a compatible guarded rollback may serve preserved state with authority closed. After a fake or real execution begins, first close/fence and reconcile effects; use a compatible read-only rollback or fix forward. Do not boot the removed PRD executor, restore old admission logic, drop additive tables, replay jobs automatically or restore a database snapshot as a way to undo external effects.

## Reproducible local qualification

Use the environment and commands in [qualification](qualification.md). `restart_reconcile_test.exs` is tagged `e2e` because it restarts the actual application and commits state; run it alone against a fresh dedicated scratch database. It intentionally leaves an unresolved simulated effect for inspection. Ordinary database tests use sandboxed transactions; concurrency suites deliberately use independent transactions and backend PIDs. Do not share their database with a development server.

Existing preservation tests cover populated historical main rows, pinned migration hashes, opaque memory sentinels, neutral event/delivery identities and GitHub source records. They are bounded local evidence. No production migration, historical deletion, sibling service edit, deployment, external credential rotation or live replay was performed.
