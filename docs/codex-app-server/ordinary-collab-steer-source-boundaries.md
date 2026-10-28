# Collaboration and steering notification boundaries

This source-only continuation follows `0791257` on `main` against official
Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`.
Eight physical notification owners remain **missing**. It adds causal source
evidence, with no runtime, field implementation, transport or verified credit.
Existing codec support and acceptance requirements remain intact.

## Private collaboration records do not establish public delivery

Owners2094–2097 and2101 require public `collabAgentToolCall` notifications with
sendMessage/followupTask/interruptAgent/listAgents or interrupted. The earlier
[projection](native-projection-boundaries.md#private-collaborator-analytics-is-not-a-public-tool-item)
and [producer](prediction-and-collaboration-source-boundaries.md#private-collaboration-analytics-is-different-from-public-item-emission)
records already distinguish private analytics from public items. This review
binds the exact remaining notification leaves to that distinction:

- `core/src/tools/handlers/multi_agents_v2/{send_message,followup_task,interrupt_agent,list_agents}.rs:18–32`
  construct ToolCallAnalytics with the selected tools. The helper at
  `multi_agents_v2/analytics.rs:10–61` explicitly avoids another public item.
  Its initial Interrupted becomes Completed/Failed on normal finish; Drop
  calls only `track_collab_tool_call`.
- `analytics/src/client.rs:431–458` constructs notification-shaped values but
  sends them to `track_notification` at820–864, recording private AnalyticsFact
  values. An enum with the public wire type is insufficient evidence of an
  outgoing app-server frame.
- `protocol/src/legacy_events.rs:270–278,328–337` supplies no legacy fallback
  for those four tools. The public converter at
  `app-server-protocol/src/protocol/v2/item.rs:965–985,1237–1259` can preserve a
  genuine supplied core item. Public dispatch at
  `app-server/src/bespoke_event_handling.rs:1077–1137` and
  `app-server-protocol/src/protocol/event_mapping.rs:406–422` requires that item;
  it does not convert the private analytics queue into public output.

This closes the traced stock handler route, rather than proving universal
impossibility. Supplied retained records and generic conversion remain separate
input profiles. Fabricated history or private analytics capture cannot qualify
native operation provenance, public notifications or equal-hash history owners.

## Shutdown requires an established status subscription

Owner2087 is conditionally reachable. `core/src/agent/status.rs:6–30` maps a
real ShutdownComplete to Shutdown. `agent/control/watch.rs:19–64` retains a
subscribed child's last update even after manager removal. A V1 wait whose
subscription is already installed can therefore receive Shutdown and emit its
real completed item at `tools/handlers/multi_agents/wait.rs:221–238`.
`app-server-protocol/src/protocol/v2/item.rs:1305–1338` preserves that child
state through public conversion.

The unresolved prerequisite is an observable public subscription barrier.
`wait.rs:105–142` emits ItemStarted **before** subscribing. A start notification,
in-progress history item, elapsed time or unrelated RPC cannot prove readiness.
Sequential close also fails to establish the desired state: `agent/control/legacy.rs:50–107`
captures status before shutdown, while9–45 removes the runtime after termination;
`close_agent.rs:67–100` uses that earlier snapshot. Later wait can see NotFound.
The [existing history prerequisite](ordinary-command-shutdown-prerequisites.md)
therefore remains valid for its own wire location too. No timing-selected race
or synthesized shutdown item is introduced here.

## Non-steerable kinds belong to the RPC rejection path

Owners2310/2311 require Review/Compact inside the canonical notification
schema. The typed RPC rejection is a different physical location:

1. `core/src/session/turn_input.rs:832–844` rejects these active task kinds with
   NotSubmittedReason::ActiveTurnNotSteerable. The older submission adapter at
   761–770 wraps a non-submission in a generic BadRequest, without typed kind.
2. `app-server/src/request_processors/turn_processor.rs:1121–1183` constructs
   the kind-specific TurnError, serializes it into JSON-RPC error.data and
   returns Err. No ErrorNotification is sent by this branch.
3. `protocol/src/protocol.rs:2005–2009,2200–2205` makes this error non-turn-affecting.
   The normal Error event path at
   `app-server/src/bespoke_event_handling.rs:1034–1057` filters it before public
   notification. History projection applies the same guard at
   `app-server-protocol/src/protocol/thread_history.rs:1235–1238`.
4. The conversion at `app-server-protocol/src/protocol/v2/shared.rs:182–196`
   preserves a supplied kind; it cannot create a production event. The
   complete pinned symbol census distinguishes this converter, declarations,
   client matches and test constructors from the sole app-server RPC constructor.

The earlier [notification producer record](native-error-producer-limitations.md#rpc-only-steering-error)
already leaves the owning ActiveTurnNotSteerable object blocked. Its child
enum owners receive this source evidence without transferring that state or
the [genuine Compact RPC result](compact-steering-error-qualification.md).
Neither a controlled model error nor a scripted app-server frame establishes
the missing notification producer. Review RPC behavior is also unqualified.

## Exact physical owners and verification boundary

All eight owners are from stable `ServerNotification.json`. Canonical node
JSON has sorted keys, two-space indentation, UTF-8 and a final newline.

| Owner | Pointer under `/definitions` | SHA256 |
| --- | --- | --- |
|2087|`/CollabAgentStatus/enum/5`|`77ac1ea0dad495e5d50a989e7ccf7d19c1c2945cc2c8dfc2fbae0d9a9a482990`|
|2094|`/CollabAgentTool/enum/5`|`9916bb0f7351bc425eca697f58a5805904e02d0ccaede970b92353eeb45014a3`|
|2095|`/CollabAgentTool/enum/6`|`1e7854479794151729aed2edaa22329fa60cad17e1b6e870ed7e732530422dbd`|
|2096|`/CollabAgentTool/enum/7`|`5c34ea5f6bb1b26be913639fda2d25ebdc21104839ccdd940b71a28cb1f4a5fc`|
|2097|`/CollabAgentTool/enum/8`|`8e52c26d20fb4bb19f9241da1e8e5a9326650895b7e725ac2f83eaa4c862b516`|
|2101|`/CollabAgentToolCallStatus/enum/3`|`f855378058a19fb7ebeb43188cc3fb801b899123d893631a2f807044e2c7e437`|
|2310|`/NonSteerableTurnKind/enum/0`|`049325e91469f33f035f3153f87a3a89d93e41f292dd00fc5df091496a7ad2c2`|
|2311|`/NonSteerableTurnKind/enum/1`|`714be13672ef0c561905c6074384a9278cfe11bbef038a6fd631e8eb1a38c4a4`|

The collaboration report is
`/tmp/samgita-collab-notification-leaves-20261029-report.md`, SHA256
`dc00aa29b9ca023b228e11e31e992f05527dab58fa36b3399549bef91fb45410`.
Its sixteen complete causal source files match their exact archive members.
The integrated source binding covers24 complete causal files and a census of
all5,259 archived Rust files, retaining25 steering-symbol references. Source archive SHA256 remains
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

The metadata-only binding permits append-only evidence/limitations on exactly
these eight rows. States, tests, transport coverage, all485 requirements and
every other contract remain unchanged. The reviewed runner changes only its
fingerprint literal; prior17-step results, commands,166/21 counts, deadlines
and original logs are rebound with all1,761 other guarded hashes unchanged.
No native launch or fresh runtime check is credited to this review.

`python3 -B /tmp/samgita-collab-steer-binding-20261029.py` passes, including a
fresh `scripts/codex/inventory.py --check`. Binding
`/tmp/samgita-collab-steer-binding-20261029/binding.json` has SHA256
`806a32ea9c1842c45738519159bf39970045968ec6a3ad56b15c7f6285536477`.
The symbol census SHA256 is
`1c47501fdba52ca8e6ee6c1e612704222923fd40e1bedbc41cd18c178b5dc943`;
inventory log SHA256 is
`0d98cdb3e17fb613b9e32450810e8b60557a2d449b6818a3d240a0663cb0aa19`.
Reviewed fingerprint is
`067878b7f26d96e7006a554532493960ff3555bfee2226fff6c4c0f6b9b3a09e`.
Prior functional results/source hashes remain
`dc0fe4f442ecd2031b452adebe506489cf1fe684eb41bc3a50db2fcd2d0e03c3`/
`d6c49b729b57dca19be1cd914ec9f590efe62de9a0beb7d1b7c00478e429b9fa`.

Counts remain **5,756 implemented /729 missing /136 blocked contracts**,
462 implemented/12 missing/11 blocked requirements and zero globally verified.
Next ordinary work is source-supported timestamp pagination; the subscription
and notification-producer prerequisites stay unresolved. No security,
credential, authentication, authorization, approval, sandbox or permission test
or audit is run. A11, prohibited/broad/hosted checks, external/OS success,
full compatibility and release remain incomplete. No publication, migration or
deployment occurs. Rollback removes these eight metadata supplements and
restores the corresponding fingerprint; runtime/data are unchanged.
