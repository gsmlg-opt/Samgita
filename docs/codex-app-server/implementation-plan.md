# Full compatibility implementation ledger

Accepted scope: [goal](goal.md) and the full user-supplied implementation contract.
The complete goal remains active. No phase below is a substitute for completion.

| Phase | Owned changes | Exit evidence | State |
| --- | --- | --- | --- |
| 0 Inventory and harness | Pin/generation scripts; complete upstream schema/provenance; compatibility manifest; isolated real-binary harness; these documents | Reproducible inventory, exact hashes, real handshake and representative round trip | Implemented checkpoint; complete source/test audit remains |
| 1 Native wire | Codex schema/codec/types and generated fixtures/tests; preserve convenience API | Complete accessible native surface; variant/malformed/lossless tests | Native layer implemented; per-entry behavior qualification remains |
| 2 Driver lifecycle | Independent driver package; stdio/WebSocket/UDS; supervised sessions and bounded state | Real-binary and fault tests for correlation, deadlines, shutdown, overflow and uncertain outcomes | Scoped lifecycle plus nine raw-transport initialization and eight scripted handshake cases implemented; full deployment matrix remains |
| 3 Method families | Version-pinned operation APIs and scenarios for every manifest family | Full enabled/disabled/error behavior, field preservation and association | Two method-family suites implement 28 real-binary scenarios; three native turn suites add 23, followed by 15 output/settings/MCP and eight image/Unicode scenarios; remaining methods and variants pending |
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
6,621 field/variant contracts. Four legacy approval method entries and the
advertised MCP item-progress notification are `blocked` by source-proven absent
production emitters. Selected native method/notification entries now total
236 `implemented`, with 245 exact field/variant schema contracts
implemented; 244 requirements and 6,376 contracts remain `missing`. None is fully verified.
Required entry-specific
behavior evidence and qualification are still needed. Generic transport and
synthetic schema examples cannot advance entries to verified.

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

Next concrete work (repair follow-up, 2026-10-24):

1. The production shutdown fix stays intact. The new test cleanup barrier is
   `5964db9`, followed by its strict-Credo syntax correction `20277f1`.
   The full independent driver suite passed 169 tests, seed `513498`; its three
   deterministic shutdown regressions also passed after the syntax correction.
2. Plug.Crypto repair `b674b8c` updates both retained locks and the standalone
   consumer floor to 2.2.1. All four retained package audits pass. WebSocket test
   synchronization `04fb7f4` preserves production bounds and passes 42 package
   cases at the recorded failure seed and two additional seeds. Recovery repair
   `db896d3` preserves the activation guard and historical records, explicitly
   journals cessation of only its own simulated effect, and passes fresh plus
   consecutive populated-database repeats. Original unresolved databases stay
   blocked. Exact causes, RED/GREEN evidence, commands and limits are in
   [repair qualification](repair-qualification.md).
3. A11 is still blocked. Real retained Bandit HTTP/1 tests establish raw
   credential/header exposure before any application Plug and retained exposure
   in exception metadata. An early HTTP/controller entry alone cannot solve it.
   No dependency offers a supported pre-emission redaction hook in this stack;
   source-level controls or a separately reviewed encrypted ingress contract are
   required. Continue independent compatibility work; never call exposure tests
   passing confidentiality acceptance.
4. Native Session notifications and fenced platform intents are implemented in
   `89c7488`, including an independent consumer and explicitly selected actual
   platform test. Active steering adds seven real cases; compaction adds seven
   local/remote/retention/failure cases; approval decisions add eight real cases.
   The full independent driver passed **208 tests twice**, and the populated
   root/recovery/static/security/assets/assembly matrix passed. The full run also
   exposed and repaired attestation prewarm test ownership in `e8a6f4a` without
   extending the native deadline. Exact outcomes are in qualification.
5. All seven Codex-native `project/*` methods now have selected persisted
   create/read/import/update/list/move/delete, presence, membership, idempotency,
   negotiation, backend and cold-restart evidence in **12 actual-binary cases**.
   Their 16 request/response/notification entries are `implemented`, with all
   field contracts still pending full qualification. See
   [native Projects](native-project-qualification.md). These native Projects are
   distinct from Samgita Projects. Controlled compaction adds two interruption/
   retry cases; safe image limits add four cases including the queued sparse-file
   metadata guard. Subsequent bounded units add explicit installed-plugin skill
   selection, filesystem lifecycle, environment/permission discovery, native
   process controls/streams, history/search/timeline, local configuration,
   inactive goals/user provenance, local account state and two-version direct
   MCP. See their qualification records. The timeline unit repairs a demonstrated
   JSON-export/native-serializer naming discrepancy through a separately derived
   contract; original exports and native values remain unchanged.
   Further units qualify native diagnostics/memory status and persisted Git,
   Project and Daybreak metadata. An isolated namespace profile exercises actual
   native browser/device authentication against an owned synthetic issuer;
   another runs both the official app-server and authenticated exec-server to
   qualify environment registration, metadata and reconnect. See
   [diagnostics/memory](diagnostics-memory-qualification.md),
   [metadata](thread-metadata-qualification.md),
   [authentication](isolated-auth.md), [executor environments](isolated-environment.md)
   and [Apps metadata](isolated-apps.md). The Apps profile adds seven real native
   cases for enabled batch/cache/ordering, gates, limits and backend 500/429 errors
   without starting a turn or MCP connection.
   The realtime output correction in `184842f` is pinned-source contract evidence;
   no enabled realtime backend success is claimed. Ordinary native history
   regressions pass again with that contract at both recorded seeds.
   Deferred MCP routing now adds eight real native discovery, namespaced-call,
   structured-result/error, tool-gating and interruption cases at both recorded
   seeds; see [deferred MCP](deferred-mcp-qualification.md). These use owned
   synthetic dependencies, not real hosted Apps or external MCP acceptance.
   Eight native Apps catalog/installed cases and nine native fuzzy-search/session
   cases pass at both seeds, including the coordinator's integrated repeat;
   [Apps catalog](isolated-app-catalog.md) documents anonymous loopback discovery
   and credential withholding, while [file search](fuzzy-search-qualification.md)
   distinguishes removal/cessation from unproven in-flight cancellation. Their
   15 native entries are scoped `implemented`, not fully verified.
   Ten isolated native account-metadata cases now exercise rate limits, profile
   and thread usage, workspace messages, authentication, nullable projections,
   HTTP errors and fresh reads. Six method/response entries and ten exact
   workspace-message field/variant contracts are scoped `implemented`; see
   [account metadata](account-metadata-qualification.md). They do not qualify
   live billing/accounts or any notification behavior.
   Eight additional actual-binary queue cases now qualify persisted unloaded
   management, native automatic FIFO dispatch, interruption/cold resume, explicit
   selected/head starts, client/turn/provider metadata, capability and error
   boundaries. The six methods, their responses and thread-only change notice
   are scoped `implemented`; no queue CAS or client-ID deduplication is invented.
   See [queue lifecycle](queue-lifecycle-qualification.md) for exact checks and
   the still-unqualified capacity, attachments and external-writer profiles.
   Eight private-network native command cases qualify buffered, binary streamed
   and PTY execution, independent stream caps, explicit controls, native timeout,
   abandonment uncertainty and connection ownership/reconnect. The required
   explicit CI profile retains Linux namespace prerequisites; UDS success does
   not qualify sandbox enforcement or every transport. See
   [command lifecycle](command-lifecycle-qualification.md).
   Six offline native model-discovery cases now cover rich/null metadata,
   filtered pagination, malformed parameters, startup snapshots and invalid
   configuration fallback, plus fresh provider-capability reads. Four entries
   and 26 directly asserted fields are `implemented`; this is metadata evidence,
   not inference or live-provider acceptance. See
   [model discovery](model-discovery-qualification.md).
   Eight native organization/read-state cases now qualify stable section
   CRUD/move and experimental read-state updates, including persisted order,
   archived cleanup, earliest-unread attention, actual revision conflicts and
   unsubscribe/resume barriers. No section CAS, immediate unsubscribe unload or
   cross-process read-state guarantee is inferred. See
   [organization lifecycle](organization-lifecycle-qualification.md).
   Eight private-network user-shell cases distinguish immediate submission ACK,
   item/turn outcomes, native timeout, auxiliary active-turn execution, contextual
   history and borrowed-client reconnect from standalone command execution. The
   commands are fixed synthetic effects inside a proven namespace because this
   native API bypasses thread sandboxing. See
   [user-shell lifecycle](user-shell-qualification.md).
   Eight native skills cases now qualify ordered local discovery with per-skill
   errors, durable path/name settings, concurrent independent writes, process-only
   root replacement, installed local plugin refresh and environment filesystem
   boundaries. Their seven entries and 22 directly asserted fields/variants are
   scoped `implemented`; see [skills lifecycle](skills-lifecycle-qualification.md).
   Eight native user-input/dynamic-tool cases reproduce and repair an unanswered
   dynamic handle remaining replyable after interruption. Exact thread/turn/call
   terminal evidence now retires that handle without acknowledging sent replies.
   Five deterministic cases cover mismatches, generation and outcome isolation.
   Eleven message/lifecycle entries and 35 directly asserted fields/variants gain
   scoped `implemented` evidence; see
   [tool interactions](tool-interactions-qualification.md).
   The corresponding PostgreSQL journal now retires only proved-unsent matching
   dynamic requests and preserves that terminal evidence across reconnect.
   Prepared replies are cancelled; dispatched and ambiguous replies remain held.
   Ten context regressions, including 129 encrypted candidates across the
   bounded query batch, pass with existing authority/Attempt suites at both seeds;
   see [platform retirement](platform-tool-retirement-qualification.md).
   Eight native attachment cases now qualify durable arbitrary JSON and stable
   identity, unloaded reads, pagination/archive filters, cursor binding,
   removal/recreation, byte/count limits and concurrent duplicates, plus stable,
   unsupported-backend and malformed request behavior. Nine entries and 37
   asserted field/variant contracts are scoped `implemented`; see
   [native attachments](attachment-lifecycle-qualification.md).
   Eight explicit actual-native realtime V2 cases now qualify backend WebSocket
   setup, distinct submission ACK/asynchronous outcomes, audio/text/speech,
   typed durable transcript history, stop/replacement, peer faults and negotiation.
   Twenty-two entries and 95 directly asserted fields/variants gain scoped
   `implemented` evidence, including voice catalogue listing rather than all
   voice/backend success. Eleven rejection-only fields retain `missing` success
   paths. See [realtime lifecycle](realtime-lifecycle-qualification.md).
   Continue remaining image-byte limits, account backend variants,
   environment/permission/turn variants and real-service authentication profiles.
   Preserve entry-specific evidence and
   external/legacy blockers; generic forwarding and scripted peers cannot
   establish real acceptance.
6. Verify hosted checks against the delivered checkpoint, and rerun affected and
   final aggregate checks for subsequent executable changes. Keep the strict
   completeness gate red while required evidence is missing. Publish only after
   applicable gates and an existing normal publication workflow succeed; no
   deployment is authorized.
7. Track the unexplained immediate Fake Agent listener rebind failure separately
   from the repaired synchronous shutdown and database safeguards. The original
   aggregate `:eaddrinuse` remains unresolved despite passing recorded repeats;
   failure-time socket ownership diagnostics preserve every shutdown/rebind
   assertion. See [listener investigation](fake-listener-recovery.md). Neither
   successful repetition nor an injected port collision establishes a repair.

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
