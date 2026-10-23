# Full compatibility implementation ledger

Accepted scope: [goal](goal.md) and the full user-supplied implementation contract.
The complete goal remains active. No phase below is a substitute for completion.

| Phase | Owned changes | Exit evidence | State |
| --- | --- | --- | --- |
| 0 Inventory and harness | Pin/generation scripts; complete upstream schema/provenance; compatibility manifest; isolated real-binary harness; these documents | Reproducible inventory, exact hashes, real handshake and representative round trip | Implemented checkpoint; complete source/test audit remains |
| 1 Native wire | Codex schema/codec/types and generated fixtures/tests; preserve convenience API | Complete accessible native surface; variant/malformed/lossless tests | Native layer implemented; per-entry behavior qualification remains |
| 2 Driver lifecycle | Independent driver package; stdio/WebSocket/UDS; supervised sessions and bounded state | Real-binary and fault tests for correlation, deadlines, shutdown, overflow and uncertain outcomes | Scoped lifecycle implemented; full deployment matrix remains |
| 3 Method families | Version-pinned operation APIs and scenarios for every manifest family | Full enabled/disabled/error behavior, field preservation and association | Partial real text/image/thread journeys; remaining families pending |
| 4 Server interactions/events | Explicit response APIs for all server requests; full event delivery | Real approval/tool/input paths, decisions, denial, stale replies and cancellation | Native interface and selected journeys implemented; full interaction matrix pending |
| 5 Platform/consumers | Ordinary Agent/task/native APIs, durable authorized interactions, examples | Fencing/review preserved; platform and outside-umbrella consumer proof | Independent consumer implemented; platform integration pending |
| 6 Conformance | Schema variants, faults, real binary, differential/platform/external profiles | Every required entry/variant evidenced or visibly blocked | Pending |
| 7 Final qualification | Aggregate/hosted checks, final evidence, docs, commits/push and gated publication | Final-source checks and remote convergence; all required entries verified | Pending |

Shared contracts are serialized by the coordinating owner. Inventory tooling and
source/behavior audits run independently. Implementation owners receive disjoint
files. Root manifests/configuration/migrations and final integration remain under
one owner. Existing reliability fixes and historical records are preserved.

## Current checkpoint

2026-10-23: inspected live `main` at
`4fe354f2ce916aa32517c361a171b8878bf6ca84`. Only the user goal/plan inputs were
untracked before this work; preserve them. Read both inputs in full, AGENTS.md,
the current adapter/transport and redesign contracts. Scoped Agent Note search
and recent-note list returned no `project=samgita` notes. This is not evidence of
Codex conformance.

The official Linux musl executable and source archive are hash-pinned. Stable and
experimental generation produced 318 and 452 JSON artifacts. The reproducible
manifest inventories 477 message/result/envelope/lifecycle requirements plus
6,549 field/variant contracts. These entries remain `missing` until required
entry-specific behavior evidence is attached; generic transport and synthetic
schema examples cannot advance them to verified.

Implemented native `Wire`, `Schema`, source-semantic gates and redacted `Error`,
with an independent `Session` and stdio/WebSocket/WebSocket-over-UDS transports.
Requests retain complete native envelopes, typed IDs and uncertainty; interactions
require explicit generation-bound replies. Deterministic model fixtures exercise
the actual executable. A portable consumer copies only reusable packages outside
the umbrella. Exact final-source commands and outcomes belong in
[qualification](qualification.md), including failed experiments and remaining gates.

Reviewable code checkpoints: `e0e4d6b` (immutable schemas, native validation and
inventory) and `9566fda6` (independent driver, actual-binary journeys and outside
consumer). Their passing checks are recorded in qualification; neither is a
full-compatibility or release milestone.

The following repair extracts bounded helpers to satisfy strict Credo without
changing checks. The newly introduced, unpublished native exception is named
`SamgitaProtocolCodex.Error`; callers of the earlier checkpoint's `Failure` name
must update that reference. Fifteen additional actual-binary tests cover selected
file, process, configuration, skill, discovery and persistent thread behaviors.
The manifest remains incomplete; this evidence does not verify every method or
parameter variant.

Next concrete work: attach narrowly scoped behavior evidence to manifest entries,
expand real-binary family and interaction scenarios (including enabled/disabled
and differential profiles), then add durable ordinary-Agent native bindings and
fenced programmatic interaction APIs. Do not transform project-event delivery into
automatic turn execution. Complete independent implementation before requiring
external/backend acceptance, and retain A11 as an independent platform blocker.

## Known boundaries

- Full compatibility is unproven; existing 13 adapter tests exercise a subset.
- A11 raw LiveView credential telemetry remains a platform confidentiality blocker.
- No real-service/account credential acceptance has run. Do not manufacture access
  or count unavailable profiles as enabled success.
- Publication workflow and platform release gates require current verification.
- No branches/worktrees, sibling edits, production migrations, live credentials,
  live projects or deployments are authorized.
