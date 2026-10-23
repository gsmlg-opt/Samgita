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
6,621 field/variant contracts. Four legacy approval method entries, the
advertised MCP item-progress notification and the explicitly deprecated
file-change output notification are `blocked` by source-proven absent production
emitters. Selected native method/notification entries now total
394 `implemented`, with 961 exact field/variant schema contracts
implemented; 85 requirements and 5,660 contracts remain `missing`. None is fully verified.
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
   Eight additional private-network cases now qualify local installed/suggested
   plugins, durable installation/uninstall, discovery scopes and local/Git
   marketplace lifecycle. Reconcile is only an unauthenticated empty pass;
   remote skill contents/materialization success remains pending. Fourteen
   entries and 36 fields gain scoped evidence. See
   [plugin lifecycle](plugin-lifecycle-qualification.md).
   Eight native import/hooks/catalog cases now qualify actual local file effects,
   source/target preservation, mixed failures, correlated progress/completion and
   cold history, plus listed hook metadata and builtin collaboration gates.
   Fourteen entries and 70 directly asserted positive fields gain scoped evidence;
   record-only sessions and empty connector catalogs do not qualify import success.
   See [import lifecycle](import-lifecycle-qualification.md).
   The [core thread/turn evidence audit](core-thread-turn-qualification.md) now
   indexes already passing native assertions for twelve operations and selected
   lifecycle/history fields. It adds 25 implemented entries and 68 fields without
   changing executable behavior or inferring unobserved notification emission.
   Eight [remote-plugin cases](remote-plugin-qualification.md) now qualify
   authenticated skill contents and explicit CA-verified HTTPS reconciliation,
   durable cache/restart, declaration changes, errors and recovery. Two more
   entries and nine more fields gain scoped implementation evidence. Normal
   enabled-at-startup sync, remote sharing/pagination and runtime effects remain
   incomplete; capability declarations do not establish activation or authority.
   Eight [thread-event cases](thread-event-lifecycle-qualification.md) directly
   assert previously missing native notices and exact Unicode deltas, identity,
   ordering, timing/usage, configured idle eviction, cold non-replay and sequential
   connection opt-out. Nine entries and 61 fields gain implementation evidence;
   empty/null-only fields and concurrent service fan-out remain incomplete.
   The [interaction audit](interaction-evidence-qualification.md) indexes
   existing compaction/review/settings/history and v2 approval/MCP/current-time
   assertions, adding 24 implemented entries and 148 positive fields. Active
   turn-setting updates, complete approval variants and unasserted notices stay
   missing. This is an evidence index, not new native execution or full acceptance.
   Eight [thread-control cases](thread-control-qualification.md) now qualify
   loaded pagination/defaults, all unsubscribe statuses, independent runtime
   counters, cold reset and the official experimental echo endpoint. They pass
   at both seeds without a repair, make no model requests and add six entries
   and twelve directly asserted fields. No runtime pause-duration, eviction
   timing or unrelated history field is inferred.
   Source inspection also identifies `item/fileChange/outputDelta` as expressly
   non-emitting in this pin. Its [retained contract](retained-output-qualification.md)
   now has two executed synthetic codec/handler cases; its native requirement
   is blocked, and no field is promoted from synthetic evidence. The other
   seven audited output notices have production routes. Four new
   [output-notice cases](output-notice-qualification.md) directly assert all
   seven over a native Unix socket using provider-only SSE. Exact reasoning
   indices/fragments, proposed plan/checklist, streamed patch, repeated complete
   diffs and actual owned-file effects pass both seeds. The single repair
   preserves all content/effect checks and deadlines while following pinned
   repeated-snapshot semantics. Seven entries and 45 new positive fields gain
   evidence; null move targets and other variants remain incomplete.
   Eight [plugin-sharing cases](plugin-share-qualification.md) now directly
   exercise all five share methods against isolated authenticated metadata and
   CA-verified HTTPS objects, including actual archive bytes, ETag origin,
   targets, checkout/cold reuse, deletion, gates and errors. Both seeds passed
   without repairs. Ten entries and 112 new positive fields gain scoped evidence;
   explicit null/empty observations and shared canonical definitions do not
   qualify unasserted values or other methods. CI explicitly selects this
   thirteenth profile. Real publication/auth, startup-enabled behavior,
   pagination, hostile inputs, concurrency and atomicity remain incomplete.
   Eight [local-history cases](local-history-controls-qualification.md) now
   qualify real memory metadata, explicit physical compression/cold resume,
   retained summaries and owned cached Git diffs. One source-derived repair
   preserves all exact maps, byte checks and deadlines; both seeds pass and
   every case makes zero model requests. Eight entries and twenty positive
   fields gain evidence; empty preview/null gitInfo and unexercised locks,
   concurrency, disk faults and remote freshness remain incomplete.
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
   At `5c4ea77`, the independent driver passed **359 tests twice**, all twelve
   explicit native profiles passed **90 cases twice**, audit and the fresh
   outside consumer passed. Foundation **40025226024** is terminal success.
   Conformance **40025258588** passed all twelve profiles and independent
   driver/consumer steps, but the platform job again failed before tests while
   fetching `mdex_native` with `header_too_long`; the completeness job remains
   failed. Preserve those distinct outcomes. Thread-control, plugin-sharing
   and local-history controls plus seven active output notices now have focused
   evidence. The [auth/envelope/lifecycle audit](auth-envelope-lifecycle-qualification.md)
   now indexes sixteen selected entries and 34 positive contracts without any
   `verified` promotion. Seven [deadline/quota cases](capacity-deadline-qualification.md)
   now pass both seeds with unchanged production bounds; the two lifecycle
   entries gain selected `implemented` evidence only. Seven
   [active-turn settings cases](active-turn-settings-qualification.md) now pass
   both seeds with actual next-step capture, sparse/null semantics, custom
   effort and unchanged future settings. Two entries and fifteen direct
   contracts gain scoped evidence; reviewer/policy/race variants stay incomplete.
   Eight [MCP control/OAuth/event cases](mcp-control-qualification.md) now pass
   both seeds, including native PKCE/token/callback/cold reuse and real HTTP
   event-stream teardown/reconnect. Twelve entries and 62 positive contracts gain
   scoped evidence; null/empty/omitted observations, other shared-schema methods,
   real accounts/Apps authorization and remaining variants stay incomplete.
   Coordinating-owner MCP/background integration passed 13 cases at both seeds.
   Five [background-terminal cases](background-terminal-qualification.md) now
   exercise actual core unified-exec sessions, numeric pagination, targeted/clean
   termination, cross-turn stdin interaction and exact approval cancellation.
   Both unit seeds and the coordinating-owner combined repeat pass. Seven new
   entries and 24 new positive contracts gain selected implementation evidence;
   nine existing approval fields gain stronger evidence, while three resource
   fields retain null-only limitations without promotion. CI explicitly selects
   this fourteenth isolated profile. Completed-empty-poll suppression, terminal
   restart/reconnect and all remaining approval/OS profiles stay incomplete.
   Five [configuration-notice cases](configuration-notice-qualification.md) now
   pass both seeds for native ignored-key/rule warnings, actual persisted-history
   deprecation and the unsupported tier warning's thread association. Three
   entries and eight positive field/variant contracts gain scoped evidence;
   explicit null deprecation details and unexercised warning causes stay missing.
   At `e82f32f`, foundation 40034189629 passes. Conformance 40034198690 passes
   fourteen isolated profiles, the driver (403/0), native wire (42/0), outside
   consumer (1/0) and the bundled native sandbox write/deny probe. Its platform
   step again fails before tests fetching `mdex_native` (`header_too_long`),
   while the completeness gate correctly fails missing evidence. Keep these
   terminal outcomes separate; do not infer a release or full acceptance.
   Eleven [account-control cases](account-control-qualification.md) now pass
   both seeds for actual-native credit-consumption/nudge handling against owned
   synthetic HTTP peers, exact routing/payloads, no-dispatch gates, errors and
   ambiguous POST uncertainty without replay. Four entries and seventeen
   positive contracts gain scoped evidence; CI explicitly selects the fifteenth
   profile. Synthetic `sent`/`reset` results establish no real email or credit
   effect. Full timeout/disconnect, service idempotency, gateway OAuth, OS
   keyrings and user verification remain incomplete.
   The [prediction boundary](prediction-boundary-qualification.md) now has
   exact immutable source proof of an unimplemented dispatcher and absent
   notification producer, three actual-native negative cases and two synthetic
   codec cases (5/0 at both seeds). The combined notice/account/prediction repeat
   passes 21/0. Three entries are explicitly blocked; twelve fields retain
   missing success evidence. Do not manufacture a producer or silently exclude
   the advertised surface from the completion contract.
   Four [provider-metadata cases](response-metadata-qualification.md) now pass
   both seeds for native raw response/assistant item, usage metadata, synthetic
   model mismatch, verification, moderation and safety notifications. One
   source-derived repair enables the actual per-thread raw-events opt-in while
   retaining stable absence checks and all deadlines. Six entries and thirty
   positive contracts gain scoped evidence; two null-only variants stay missing.
   Other raw items, UI-false, Bedrock auth-recovery and real service/OS profiles
   remain incomplete.
   At `085c4cc8`, foundation
   passed; conformance's thirteen isolated profiles passed, but all four default
   output-notice tests failed during namespace startup on Ubuntu 24.04. The
   required namespace preflight at `fe5222d` diagnoses the actual prerequisite
   before repair; no hosted success or timeout change is inferred.
   Final aggregate/hosted checks must include
   all subsequent executable changes, with serialized validation and direct
   positive schema evidence only.
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
- Hosted platform qualification at `dd6ec5b` failed twice before tests while
  downloading `mdex_native` (HTTP header limit); independent driver/consumer
  and explicit native profiles passed. Keep that infrastructure result separate
  from completeness and local platform evidence; see qualification.
- The same dependency-fetch failure recurred at `5c4ea77`; its foundation and
  twelve native profiles passed, but hosted platform tests did not run.
- No branches/worktrees, sibling edits, production migrations, live credentials,
  live projects or deployments are authorized.
