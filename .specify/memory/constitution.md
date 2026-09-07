# Samgita Constitution

Version: 2.0.0
Amended: 2026-09-07
Authority: User-approved Agent Hub clean-start design.

This revision replaces the former local-orchestration constitution following explicit approval to replace the unused application. It governs the target product during the staged rebuild; it does not claim that implementation is already complete.

## I. External execution and two applications

Samgita is the authoritative control plane for external Agent runtimes. Keep only `samgita` and `samgita_web` as umbrella applications, with web depending on core.

Remove embedded provider execution, memory retrieval, PRD orchestration, Horde/local worker machinery, and their dedicated data/configuration/UI. No legacy compatibility layer or data migration is required. Preserve source history in Git.

## II. Single-tenant operators and authenticated machines

Do not add browser accounts, login, organizations, or browser RBAC. Protect browser access through deployment infrastructure.

Agent WebSocket connections always require machine credentials. Project-Agent bindings explicitly authorize work. REST API key protection and rate limits remain. These machine/API controls are required and are not prohibited by the absence of browser authentication.

## III. PostgreSQL authority

PostgreSQL holds Projects, Agents, credentials, connections, bindings, Tasks, Attempts, receipts, and audit events. PubSub and socket state are transient.

Commit state transitions, receipts, and audit events together; broadcast after commit. Use Oban for durable maintenance. Do not use Mnesia, DETS, or local files for authoritative server domain state.

Project `git_url` remains canonical identity, while UUIDs provide database relations. Samgita does not automatically clone or execute repositories in this milestone.

## IV. Fenced, idempotent execution

Keep logical Tasks separate from execution Attempts. Enforce one active Attempt with database constraints, serialize Agent capacity, and reject expired/stale ownership.

Use versioned protocol envelopes and durable replayable receipts. Identical messages return the original response; conflicting semantic payloads are rejected. Pure transition functions and transaction tests define permitted behavior.

Fencing governs accepted Samgita state; it does not promise exactly-once external side effects.

## V. Usable and verifiable first milestone

Deliver an operator LiveView UI, REST API, and a fake external Agent using the real WebSocket transport. No real LLM or Synapsis service is required for tests.

Use the existing DuskMoon family, Phoenix LiveView, Tailwind, Bun, and TypeScript. Keep views accessible, responsive, and bounded in query/payload size.

Cancellation/manual retry, real Synapsis, GitHub workflows, embedded providers, memory retrieval, multitenancy, and artifact storage are deferred.

## Development and evidence

Follow AGENTS.md and the bounded stages in docs/plan.md. Freeze shared schema/protocol contracts before parallel implementation. Keep one owner for migrations and shared runtime configuration.

Test actual behavior: constraints, independent-transaction races, real transport, replay/reconnect, expiry, secret redaction, UI interaction, and release boot. Do not treat a shared sandbox connection as evidence of database locking.

Use explicit fresh development/test databases. Approval of a fresh start does not identify an existing database for deletion.

Use Conventional Commits and worktrees under `.trees/codex/`. Preserve unrelated user work. Report unrelated failures rather than expanding scope.

## Governance

The approved product decisions in docs/agent-hub-rebuild-design.md and current user instructions govern scope. Keep docs/prd.md, docs/architecture.md, docs/plan.md, AGENTS.md, and this constitution consistent when a decision changes. Do not revive superseded legacy rules or infer authorization to publish issues, PRs, or releases from a documentation change.
