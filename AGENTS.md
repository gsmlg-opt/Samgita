# Repository Guidelines

## Product

Samgita is an agent-neutral, single-tenant project and task management platform. It registers Agents and Projects, connects repositories and GitHub, validates authoritative Task/Attempt state, and emits scheduled and external events. Registered Agents own reasoning, planning, delegation and execution. Synapsis, Sigma and Codex follow the same registration and authorization rules; an implementation label grants nothing.

Samgita does not run LLMs, embedded providers, local workers, PRD orchestration or a central reasoning loop. Do not infer compatibility requirements from removed legacy code.

### Target workflow (confirmed 2026-11-09)

Samgita connects external Agents and manages their collaborative development work:

1. A GitHub event (for example a new issue) is ingested and routed as a Project event to the Project's responsible coordinator Agent (for example Synapsis, with the `manager` role).
2. The coordinator Agent reasons about the work and decomposes it into a Task tree (`parent_task_id`, `depends_on_ids`) through Samgita's API. Decomposition is the coordinator's job; Samgita stores, validates and enforces the tree but never decomposes on its own.
3. The coordinator explicitly assigns each Task to a named executor Agent (for example Codex or Sigma). Samgita validates membership, capability and capacity, then notifies the assigned Agent, which claims and runs it as a fenced Attempt.
4. Samgita monitors execution through Attempt leases, progress and reports, plus observed GitHub PR/check/workflow/release facts, and notifies the coordinator of outcomes.
5. Executor Agents open PRs, merge and release with their own GitHub credentials. Samgita stays read-only toward GitHub and only observes.
6. Acceptance (`awaiting_review` -> `accepted`) is configurable per Project: either the coordinator Agent holds the `reviewer` role and accepts automatically, or only a human operator accepts.

Not yet implemented: explicit executor assignment and assignment notification (today executors claim by capability), release-event ingestion, and the rule that an executor cannot accept its own work. Coordinator outcome notification already works through the `responsible` subscription but lacks acceptance coverage. The proposed contract for these is `docs/redesign/design.md` §10; extend the implementation plan and acceptance ledger before coding.

## Documentation Map

Authoritative:

- `docs/redesign/design.md`: domain ownership, protocol boundaries, subsystem inventory, migration mapping and security contracts.
- `docs/redesign/implementation-plan.md`: bounded stages, file ownership, rollback, blockers and verification gates.
- `docs/redesign/acceptance.md`: review checklist and executable acceptance scenarios.
- `docs/redesign/dependency-modernization.md`: approved infrastructure amendment (see below).
- `docs/architecture.md`: the current implementation.

Reference and phase records: `docs/redesign/{management-api,capability-matrix,migration-rollback}.md`, phase records (`protocol-phase-2`, `domain-phase-3`, `coordination-phase-4`, `github-phase-4`, `qualification`), and Agent setup guides in `docs/redesign/integrations/`. Phase records describe their recorded revision; later amendments take precedence.

Codex client/driver work lives in `docs/codex-app-server/`: `goal.md`, `design.md`, `implementation-plan.md`, `ordinary-functional-delivery.md`, `platform-integration.md`, per-topic qualification records, and `compatibility-manifest.json` (consumed by `scripts/codex/`).

The former clean-start PRD, plan, rebuild design and removal inventory were removed; they survive only in Git history and never authorized deleting data or migrations.

## Infrastructure

Per `docs/redesign/dependency-modernization.md`: DuskmoonBundler replaces Bun/Tailwind CLI, Gaoxy replaces Bandit, Styx replaces Oban, and http_fetch/http_web_socket (published 1.0.0-rc.5 APIs) replace production Mint HTTP/WebSocket clients. Mint remains test-only as the independent raw-wire oracle.

The 2026-11-08 clarification removes Oban and Bandit completely from production, test and release dependencies, with no migration shims or test-only retention. The two Oban migration sources are removed; their source and evidence stay in Git history. Platform job admission/status reads Styx only. Existing database rows (including `oban_jobs`) are not deleted, migrated or replayed; deployment inventory and old-writer exclusion remain separate cutover obligations. Gaoxy's pinned Abyss/Hell RC refresh is tracked by gsmlg-dev/gaoxy#22; do not override it.

Functional verification does not qualify the unrun pin/TLS/authentication/security checks. Historical phase records do not qualify the replacement libraries.

## Umbrella Layout

- `apps/samgita_protocol`: independently reusable protocol core, versioned schemas, capability negotiation, correlation, client dispatch, handler contracts and bounded replay. No platform/Repo/Phoenix dependency, configuration inheritance or automatic listener/runtime startup.
- `apps/samgita_protocol_websocket`: optional standalone authenticated WebSocket transport and explicitly started in-memory fake Agent at `/app-server`.
- `apps/samgita_protocol_codex`: pinned Codex `rust-v0.163.0` native wire/schema layer plus the neutral convenience adapter. Source/schema conformance does not establish full compatibility.
- `apps/samgita_codex_driver`: explicitly started Codex sessions and transports. No Repo, Phoenix, platform configuration, automatic execution or listener dependency. Borrowed service resources remain owned by their service.
- `apps/samgita`: Ecto Repo, Projects, repositories/GitHub, Agents, Tasks/Attempts, events, schedules, and durable delivery/maintenance with Styx. No Oban dependency, compatibility module or historical-job reader.
- `apps/samgita_web`: Phoenix endpoint, REST API, protocol host adapter, GitHub ingress and DuskMoon LiveView operator UI.

Dependency direction is web -> core -> protocol, with optional web -> transport integration. Core never depends on web. The root umbrella lists only `samgita` and `samgita_web`; core consumes the protocol as a path dependency. The protocol and driver projects omit umbrella build/dependency/config inheritance; run their commands from their own directories. Protocol consumers can build outside this repository without starting Samgita. Actual Sigma/Synapsis endpoints remain in their existing services; do not create another Sigma server process or require all traffic to pass through Samgita.

Enabled Styx queues are exactly `hub_events`, `hub_schedules`, `hub_maintenance` and `hub_github`, with schedule/coordination/GitHub-read Cron wakeups. Legacy workers/queues stay excluded; old hooks enter a disabled quarantine queue and enqueue failures propagate. Where a deployment still runs legacy code, fence and drain its producers and external effects before cutover. Preserve historical PRDs, runs, messages, artifacts, snapshots, memory records and references; do not copy dead runtime source into archives.

## Architecture Rules

- PostgreSQL is authoritative for durable state. Channels and PubSub cannot confer work ownership.
- A Task is logical work; an Attempt is one execution. Keep their states separate.
- Attempt success submits a Task to `awaiting_review`; explicit review and acceptance decisions produce `accepted`. Reports, artifacts and capabilities cannot confer acceptance. Unresolved effects leave the Task `blocked` with an execution hold.
- Stable Agent identity, authenticated connection generation and external execution session are separate records. Roles belong to Project membership; capabilities never grant authorization.
- Samgita enforces ownership and legal management transitions; it does not prescribe development phases, choose an Agent's reasoning loop, or automatically decompose PRDs.
- Use pure functions for transitions, capability matching and retry calculations. Create processes only for a runtime need.
- Claims serialize Agent capacity and lock eligible Tasks. Use leases and monotonic fencing tokens, with database uniqueness for active Attempts.
- Follow the authority fence and global lock order in `docs/redesign/design.md` for all competing commands. Legacy and new execution must never be active simultaneously.
- Commit aggregate changes, audit events and protocol receipts atomically. Broadcast only after commit.
- Delivery is at least once. Lost ACKs/handler leases require stable-operation status reconciliation; no reconnect/timeout may launch execution. Explicit recovery keeps event identity/time and records duplicate-effect risk. Transport receipt, durable notification acceptance, processing completion and Task acceptance are separate.
- Use Styx for durable scheduling, delivery and expiry maintenance; PubSub is best-effort notification. A scheduled or external event does not itself authorize execution or a Task transition.
- Keep core commands out of Channel/controller callbacks. Transport delegates to contexts.
- Keep existing Project UUIDs canonical and unchanged. Repository identity and URL aliases belong to separate repository associations; `git_url` is preserved legacy provenance, not Project identity.
- Use additive migrations and resumable, audited mappings. Removing the two Oban migration sources is the only exception to retaining initial migration sources. Do not rekey Projects, merge Projects by URL, or silently replay legacy work.
- Integration gates require an operator journey, a real-WebSocket fake Agent, protocol-package isolation, and migration/rollback rehearsals. No external LLM is needed for those checks.

## Security and Scope

The deployment is single-tenant. Do not add browser accounts, authentication, organizations or RBAC. Browser access is protected by infrastructure; retain REST API key protection and rate limits. Agent transport always requires machine credentials.

Never persist or log plaintext Agent credentials or lease proofs. Operator-supplied credentials return only metadata with `no-store`. Outbound service credentials are external runtime references, separate from inbound machine credentials. Approve exact Agent URLs and pinned destination addresses; use WSS remotely. Credential reference names are immutable/versioned; rotation requires a new reference and reviewed routing/replay. Proof retrieval is explicit, owner-authorized and non-cacheable; proofs never enter receipts/events. Runtime lease keys are external to the database. Protocol/audit logging uses allowlisted metadata. Validate current credentials, connection ownership, membership and execution epoch before replay.

GitHub integration verifies raw-body signatures and approved installation/repository-to-Project mappings before atomic inbox/event/job persistence. Payload Project/Agent IDs cannot select routing. Current external projections and immutable source evidence are separate; Issue/PR/check state never confers Task acceptance. Treat text as untrusted input. Keep GitHub code outside protocol packages. GitHub uses versioned external secret references and approved pinned API destinations; only token authentication may POST remotely, with repository-restricted read-only tokens. Comments, PR creation, merge and workflow execution remain disabled.

Do not provision a real GitHub App, enter real credentials, change remote permissions, create live webhooks, enable GitHub writes, edit sibling services, migrate production, delete historical data or deploy. Real GitHub/Agent-service integration requires explicit security/conformance gates. Embedded providers/execution, memory retrieval, new artifact storage and a browser account system are out of scope.

## Open Gates

- **A11**: raw LiveView telemetry exposes secret parameters, and real HTTP evidence shows credential-bearing server metadata before application Plugs. It remains blocked even when build checks pass; moving a form into a controller or early Plug does not close it. See `docs/codex-app-server/repair-qualification.md` and `docs/codex-app-server/a11-ingress-boundary.md`.
- **Full Codex compatibility** against immutable `rust-v0.163.0` remains an incomplete target (see `docs/codex-app-server/goal.md`). Retain its entire native surface, inventory, strict full compatibility gate and blockers. Ordinary functional delivery (`docs/codex-app-server/ordinary-functional-delivery.md`) does not establish full compatibility or platform readiness. Do not resume rare-branch producer searches without a new concrete prerequisite.
- Real GitHub App (B5), live Sigma/Synapsis/Codex conformance, deployment inventory, legacy-writer exclusion, full memory/backup rehearsal and production cutover remain open.

## Verification Restrictions

Do not run any security or permission-related tests: credential/authentication/authorization/approval tests, audits, and broad suites or automatic hosted workflows that execute them. Run only reviewed functional checks; preserve existing tests and required gates, record prohibited checks as unrun/incomplete, and suppress automatic CI (`[skip ci]`) when pushing under this restriction. This never authorizes weakening access controls or claiming blocked acceptance complete.

The reviewed Codex functional selection is `python3 -B scripts/codex/check_ordinary.py --list`; execute it with `--output <new-evidence-directory>` in the verified Elixir/OTP environment. Its source fingerprint, named tests and expected case counts require review before modification. This subset does not replace the full compatibility or release matrix.

Owned Codex functional qualification launches default to `approval_policy="never"` and `sandbox_mode="danger-full-access"`. Only explicitly owned disposable Codex processes and isolated synthetic fixtures are authorized; no paid or production tasks.

## Release Policy

Every version below 1.0 is an experimental test release. The manual Release workflow may publish the four reusable Hex packages, the application archive and `ghcr.io/gsmlg-dev/samgita` images after its reviewed release-helper functional checks, outside-consumer compilation and all builds pass. All first-party app and artifact versions must match. GitHub marks 0.x releases as prereleases; package READMEs document experimental status. Release notes must disclose the open gates above. Stable versions (1.0+) additionally require successful CI/Tests/Codex conformance, strict inventory and platform release-blocker gates. Do not tag a failing build, and never deploy.

## Frontend

Use Phoenix LiveView, DuskmoonBundler (including its integrated Tailwind CSS pipeline), TypeScript and the existing DuskMoon family. Use Mix npm tasks and the root workspace lockfile instead of Bun or standalone Tailwind executables.

- Prefer `phoenix_duskmoon` components and existing `@duskmoon-dev/*` assets.
- Do not introduce DaisyUI or another component library.
- Do not vendor or patch DuskMoon internals.
- Keep views operational, accessible, responsive and consistent.
- Use pagination, preloads, empty/error states and visible form validation.
- Verify UI changes with focused LiveView tests and `mix assets.build`; perform browser proof for the full operator journey.

## Commands and Tests

Run from the repository root. Use `devenv shell --` when the host lacks the required Elixir/OTP environment.

```bash
mix deps.get
mix compile --warnings-as-errors
mix ecto.create
mix ecto.migrate
mix samgita.run            # delegates to phx.server; HTTP on port 4870
mix test apps/samgita/test/samgita/projects_test.exs
mix test apps/samgita_web/test/samgita_web/live/dashboard_live_test.exs
mix assets.build
mix format --check-formatted
mix credo --strict
mix dialyzer
```

Stage-specific tests are defined in the redesign plan and phase records. GitHub checks use deterministic signed fixtures, a loopback fake server and isolated PostgreSQL. Protocol and driver tests run from their own directories with no database/platform/config dependency; `apps/samgita_protocol/scripts/verify_standalone.py` proves an outside consumer. Report unrelated failures without repairing them or weakening gates. Format changed Elixir files, excluding the verbatim pinned migration sources.

The current application has only the main Repo. The legacy system's main and memory migration sets are accounted for by P3's source hash manifest; its history rehearsal does not certify a real pgvector/dual-Repo deployment. Concurrency tests use independent transactions and verify distinct PostgreSQL backend PIDs. WebSocket/restart/migration tests use explicitly isolated databases/endpoints with legacy side effects disabled.

Use explicitly named scratch databases and sanitized legacy fixtures for migration rehearsals. `SAMGITA_TEST_DATABASE` overrides must match `samgita_redesign_*_test` (optional numeric partition). Never run `mix ecto.reset` against an unresolved/shared target. Only isolated local test databases are authorized; no production migration or historical-data deletion.

For each scoped stage, modify only listed files, run scoped tests, and stop when its checklist and tests pass. Remove obsolete tests only when their owning product behavior is removed; do not delete failing tests for retained behavior.

## Delivery and Parallelism

- Use parallel agents for independent work after shared contracts are fixed, with non-overlapping file ownership.
- Keep migrations/shared configuration under one owner.
- Use small bounded stages and logical commits; keep the application bootable at integration checkpoints.
- Resolve tracked-file deletion targets before removing them.
- Preserve user changes, ignored local data and unrelated worktrees.

## Git

Work on the existing branch. Create branches or worktrees only when explicitly requested; place worktrees in `.trees/<branch-name>`.

Use Conventional Commits. Do not include "Generated with Claude Code" or a "Co-Authored-By: Claude" trailer. Stage explicit logical units. Do not push, publish PRs or deploy unless requested.

## Upstream Dependency Issue Routing

For dependency bugs or missing features in GitHub organizations `gsmlgorg`, `gsmlg-dev`, `duskmoon-dev`, `gsmlg-app`, `Gao-OS`, `gsmlg-opt`, `gsmlg-ci`, `gsmlg-games` or `gsmlg-com`:

1. Identify the source repository from the package manifest or lockfile.
2. Create an issue with `gh issue create`, type `Bug` or `Feature`, label `internal request` (create if missing), and title `[internal] <concise description>`.
3. Include requesting repo and branch from Git, the need and reason, reproduction or expected behavior, and severity: `blocker`, `needed` or `nice-to-have`.
4. For blockers, add `# TODO(upstream): org/repo#issue_number` at the callsite and stop that task. Continue only independently unblocked work; resume after the dependency is fixed and updated.
5. For non-blockers, mark a narrow temporary solution with `# WORKAROUND(upstream): org/repo#issue_number`.

Do not silently work around upstream defects.

## Coding Discipline

State assumptions, keep changes scoped, and prefer the smallest implementation satisfying the approved requirements. No speculative abstractions or unrelated refactoring. Format changed Elixir files. Inspect shared consumers before deleting infrastructure or dependencies.

Verification must demonstrate behavior: state transitions, database effects, real protocol responses and UI results. A successful compilation or running process alone does not establish milestone completion.

## Agent Note

Agent Note project: samgita

Use the shared `agent-note` skill for reviewer-first project engineering knowledge. Before substantial design or debugging, recall relevant project notes. At accepted decisions, significant implementation boundaries or reproducible blocker handoffs, evaluate durable findings and create/update notes only when the skill's quality gate passes. For meaningful implementations, maintain a coherent human-reviewable explanation of architecture, design rationale, actual behavior, verification and limits; do not save a separate task-status note after each fix. This authorizes scoped capture, not whole-project curation or deletion. No note is required for an ordinary completed task. Contributors return candidates; the coordinating agent writes shared notes. Apply recalled guidance only after checking its sources and target-version scope. If the skill or MCP is unavailable, report the limitation without claiming a write.
