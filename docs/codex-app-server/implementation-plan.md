# Full compatibility implementation ledger

Accepted scope: [goal](goal.md) and the full user-supplied implementation contract.
The complete goal remains active. No phase below is a substitute for completion.

| Phase | Owned changes | Exit evidence | State |
| --- | --- | --- | --- |
| 0 Inventory and harness | Pin/generation scripts; complete upstream schema/provenance; compatibility manifest; isolated real-binary harness; these documents | Reproducible inventory, exact hashes, real handshake and representative round trip | Implemented checkpoint; complete source/test audit remains |
| 1 Native wire | Codex schema/codec/types and generated fixtures/tests; preserve convenience API | Complete accessible native surface; variant/malformed/lossless tests | Native layer implemented; per-entry behavior qualification remains |
| 2 Driver lifecycle | Independent driver package; stdio/WebSocket/UDS; supervised sessions and bounded state | Real-binary and fault tests for correlation, deadlines, shutdown, overflow and uncertain outcomes | Scoped lifecycle implemented; full deployment matrix remains |
| 3 Method families | Version-pinned operation APIs and scenarios for every manifest family | Full enabled/disabled/error behavior, field preservation and association | Two method-family suites implement 28 real-binary scenarios; three native turn suites add 23; remaining methods and variants pending |
| 4 Server interactions/events | Explicit response APIs for all server requests; full event delivery | Real approval/tool/input paths, decisions, denial, stale replies and cancellation | Selected behavior across 9/11 interaction families; legacy approvals and remaining variants pending |
| 5 Platform/consumers | Ordinary Agent/task/native APIs, durable authorized interactions, examples | Fencing/review preserved; platform and outside-umbrella consumer proof | Context, REST API and explicit Driver bridge implemented; selected two-Agent actual-binary journey, outside consumers and populated-database repeats passed; full contract remains incomplete |
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
manifest now inventories 485 message/result/envelope/lifecycle requirements plus
6,621 field/variant contracts. These entries remain `missing` until required
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

The source-completeness repair preserves the original official JSON exports and
adds a separately labeled supplement for three legacy requests and two raw
notifications. The supplement derives structure from the pinned executable's
experimental TypeScript export and omission/untagged semantics from matching Rust
serde declarations. Hashes and origins remain in package provenance. Source
completeness and generated fixtures still do not verify runtime behavior.

Thirteen further actual-binary method-family scenarios cover local search,
review, settings, injected history, sections, queues, attachments, read state,
feature/profile discovery, config import history, local plugins and legacy calls.
Six server-interaction scenarios and three synthetic auth/attestation scenarios
exercise selected decisions and actual local effects. Together with prior driver
tests, nine of eleven server-request families have selected behavior evidence.
Legacy `applyPatchApproval` and `execCommandApproval`, remaining decision/field
variants and external service success profiles remain unqualified. A follow-up
pinned-source audit found no production emission path for either legacy family:
current thread events always emit v2 approval requests, their former client APIs
are absent, and initialization has no legacy selector. Keep these advertised
contracts in scope and record the unmet real-binary success requirement in
[legacy approval qualification](legacy-approval-qualification.md); an older or
modified executable would not qualify the immutable target. Synthetic JWT
refresh and attestation header forwarding are not real authentication or
attestation-service acceptance.

The platform implementation now adds inert runtime registration metadata, four
additive native journal tables, encrypted payload storage, context commands,
project-authorized REST endpoints and an explicit bridge for an already started
driver. See [platform integration](platform-integration.md) for the source-level
contract and current limitations. Context/API tests cover selected validation,
payload protection, replay, authorization, ambiguity, reconnect and Task-state
boundaries. Four concurrency tests use independent PostgreSQL backends and finish
their committed fixtures without deletion; populated-database repeats pass.
Review reproduced and corrected dispatch after an unconfirmed approval reply and
operator approval after authority-epoch change. The qualification record separates
these component checks from subsequent combined-source aggregate results.

Delivery review reproduced two more reconnect defects. Session now checks the
ticket's instance, generation and absolute deadline atomically before native
request/reply dispatch. An additive follow-up migration and journal predicates
include driver generation in source/request identity and response/resolution
correlation. Reused upstream IDs after reconnect cannot settle old uncertain
approvals. Both repairs have red/green regressions; no gate was weakened. Current
combined-source checks passed 89 driver tests, independent consumers, 188 core
tests and 112 executed web tests twice, plus the selected actual-binary/API
journey. Exact remaining aggregate and hosted outcomes belong in qualification.

Next concrete work:

1. The lifecycle repair `49d1c37`, legacy contract evidence `d63dcdd` and documents
   were pushed through `6e19d69`. Hosted pinned conformance run `39958930872`
   passed its selected protocol/driver/consumer/platform job, including all 102
   driver tests and four actual-binary platform journeys. Its independent full
   evidence gate failed as required. Aggregate run `39958837990` passed root
   checks and fresh restart, then failed the retained neutral WebSocket
   overflow/replay test (40 tests, one failure); later aggregate steps were
   skipped. Report this out-of-scope result without changing its test or
   transport in the Codex repair. Repeated local restart on the retained scratch
   database still failed before driver startup with
   `unmapped_or_unresolved_tasks`; fresh hosted success cannot clear that result.
   Retained `plug_crypto 2.2.0` still fails local audit for CVE-2026-105963;
   dependency remediation remains a separate scoped change.
2. The native turn suites are implemented at `73258c5`: 23 actual-binary cases
   cover every UserInput form, selected overrides and persisted UTF-8 spans/client
   IDs. The final local driver suite passed 125 tests after source-grounded
   correction of model metadata and media-processing assumptions, plus stronger
   skill/cleanup/isolation assertions. See [turn qualification](turn-input-qualification.md).
   Next cover successful `toolOutput` continuation, enabled structured MCP
   mention routing, image resizing/size limits and remaining turn overrides,
   then complete differential profiles and manifest-specific evidence. Preserve
   all 485 requirements and 6,621 contracts as missing until their full acceptance
   conditions are established. Selected payload capture does not establish media
   understanding, file resolution, external permissions or every transport.
3. Run final independent-package/consumer, root, restart/recovery, static,
   security, assets, release-assembly and hosted checks on the delivered source.
   Keep unavailable external profiles and A11 visibly incomplete. Publish only
   after applicable gates and the normal workflow pass.

Project-event delivery remains notification delivery; it cannot start a turn.
No new background execution engine, production migration, sibling-service change,
live credential setup or deployment is part of this checkpoint.

## Known boundaries

- Full compatibility is unproven; existing 13 adapter tests exercise a subset.
- A11 raw LiveView credential telemetry remains a platform confidentiality blocker.
- No real-service/account credential acceptance has run. Do not manufacture access
  or count unavailable profiles as enabled success.
- Publication workflow and platform release gates require current verification.
- No branches/worktrees, sibling edits, production migrations, live credentials,
  live projects or deployments are authorized.
