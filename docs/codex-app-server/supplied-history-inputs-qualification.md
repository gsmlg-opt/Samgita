# Genuine supplied-history inputs and native timestamps

This unit qualifies eighteen exact physical owners against immutable Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`.
The app-server executable generates the original frames and persisted records.
The unchanged local Responses fixture supplies prescribed content. All native
launches use fixed yolo; no platform database or external service is needed.

## Genuine media input

The only raw `ResponseItem` input route in this pin is experimental
`thread/resume.history`. Upstream explicitly labels it **“[UNSTABLE] FOR CODEX
CLOUD - DO NOT USE”** in `app-server-protocol/src/protocol/v2/thread.rs:354–362`.
It takes nonempty history through `InitialHistory::Forked` and creates a new
thread identity. It does not resume the supplied source identity. The official
`thread_resume_supports_history_and_overrides` test exercises this route at
`app-server/tests/suite/v2/thread_resume.rs:6175–6234`.

`native_supplied_history_inputs_test.exs` first completes one genuine native
turn with literal text, a tiny valid inline PNG, an image file reference and a
tiny WAV. It closes and reaps the source process before reading bounded native
JSONL, selects the complete user/assistant payloads by independent literal
markers, and forwards those maps unchanged to a cold native process. It never
constructs raw history records or edits rollout/SQLite data.

The imported thread has a new identity and retains each complete original
payload exactly once. Import issues no inference. One followup consumes the
prescribed original media/text and assistant answer, carries
`history_initialization:"supplied_history"`, and produces exactly the second
provider request overall. Source rollout bytes, configuration, model catalog
and provider fixture remain unchanged. Reads/events are bounded and both native
processes must exit.

Owners107–113 and115–120 cover selected canonical `ClientRequest.json`
`ContentItem` image/audio branches, URL/file ID, auto/low details and literal
type tags. This is input acceptance and retained semantics through the unstable
route. It proves neither stable public API support, real upload/file resolution,
external media interpretation nor all server-output variants. Explicit-null
detail owner114 stays missing; omission does not exercise null.

## Message metadata

Owners223,374,375 cover original non-null message metadata and its `turn_id`
field. Both genuine payloads retain the source turn ID across import into the
new thread. The user metadata has exact content classifications and a creation
timestamp independently bounded by host turn times. Assistant metadata has an
exact `unknown` content classification and explicitly lacks a creation timestamp.

The first focused run failed on an incorrect assistant timestamp expectation.
Pinned `protocol/src/models.rs:1455–1484` stamps message creation time only for
user/developer roles; `context-fragments/src/annotated_content.rs:47–95`
establishes the assistant classification. The corrected role-specific oracle
retains all exact original-payload assertions and the user timestamp bound.
The failed log remains `/tmp/samgita-v302-history-initial-501432.log`.
The final owning file passes **1/0 twice**, seeds501432/987654, with SHA256
`573541ead480be8916768c6fe8abcee56339cbd09b91726894c954f3c12a5cb4`.

`core/src/client.rs:1000–1028` strips internal metadata from non-OpenAI
provider request copies. Consequently the provider journal checks literal
semantic contents and supplied-history initialization; metadata retention is
checked in the native imported rollout. Whole-payload provider echo would be
an incorrect oracle. Explicit-null metadata/phase owners376/379 stay missing.

## Terminal timeline time

Owner6440 is the optional `started_at` field in canonical
`v2/ThreadTimelineListResponse.json`'s `turnCompleted` branch. Existing pinned
`source/output-semantics.json` records its actual native wire name `startedAt`.
The timeline profile now extracts authentic `task_complete.started_at`, requires
positive integer Unix seconds equal to the original `task_started.started_at`,
then compares terminal values through full/page/cold/continuation results.
Completed, failed and recovered turns preserve all prior ordinals, errors,
content, UUID checks, cursors, original bytes, inference budgets and cleanup.

Pinned `core/src/session/mod.rs:2421–2433` obtains native start seconds;
`app-server-protocol/src/protocol/thread_history_projection.rs:23–53` records
the event metadata;
`thread-store/src/local/thread_history.rs:326–354` persists it and
`thread_history/realtime.rs:125–130` emits the literal `startedAt` key.
The owning timeline file passes **2/0 twice**, without a repair round; SHA256
`f3bda54947d14677837898d6ce6fc1379ed24cc3f11c8afe5b8e3aaa52f7144a`.
Logs are `/tmp/samgita-v302-timeline-{501432,987654}.log`. Null/absent and
realtime alternatives do not inherit evidence.

## Notification emission time

Owner3147 is canonical `ServerNotification.json#/properties/emittedAtMs`.
The unchanged reviewed command-output test requires exact notification keys,
integer Unix milliseconds within host times around real `command/exec`, literal
stdout/stderr bytes, generation/order bounds and native/child cleanup.
Its SHA256 remains
`9f896be57d3663ba2da0a4c4fea8f2fcc9d5866d75756d925830562f4c6585cf`.

`app-server/src/outgoing_message.rs:747–824,894–908` timestamps ordinary
notifications before fanout without a feature or policy gate.
`app-server-protocol/src/protocol/common.rs:2078–2094` and
`export.rs:1412–1429` retain optional decoding/schema compatibility.
`command_exec.rs:553–554,609–622` awaits both output workers and their targeted
writes before replying, supplying the independent upper bound. No extra profile
or artificial delay is added. Older-server omission, all notification families,
fanout timing equivalence and other transports remain separate qualifications.

## Integrated evidence and limits

`/tmp/samgita-v302-run.py` records exact serialized commands in
`/tmp/samgita-v302-functional-checks/functional/results.json`. The reviewed
41-file matrix passes **76/0 twice**, seeds501432/987654, in
134.249/129.704 seconds. Scoped format, compile with warnings as errors,
strict Credo on 491 sources, outside actual-binary consumer **1/0**, seventeen
fixture AST checks and the **279-source** before/after guard pass.

| Evidence | SHA256 |
| --- | --- |
| Results | `7ff2ad830619f9f9287b15710b52e3858cb391d440641fde96f818f578377193` |
| Source guard | `7398be92c62a815720155207ce9cb6f13bc936e630c6f4ae030c889b41938f12` |
| Pinned-source evidence | `247de1ec77cf647ab7c14e9c2cf2c63d25aa1f7fc818b3d9c6b543a151026031` |
| Resulting manifest | `9233a5749753903d8a732b210a6c730aaa28e4ed23832abf9c00ec2228845c4d` |

Seventeen complete producer files match the immutable archive; twenty-one exact
nodes include unchanged null alternatives. Unique complete-record patches and
original/current owner bindings are in `source-evidence.json`,
`manifest-binding.json` and `final-binding.json`. The source-evidence script's
initial incorrect materialization-file path was corrected to
`thread-store/src/local/thread_history_materialization.rs` after locating it;
the original script/failure remain under `/tmp/samgita-v302-source-initial*`.
No repository implementation changed for that artifact correction.

Inventory consistency passes; strict completeness honestly exits **1**.
Contracts become **4,874 implemented / 1,688 missing / 59 blocked**;
requirements stay **462 implemented / 12 missing / 11 blocked**, zero verified.
Prohibited security/permission checks, broad/hosted workflows, A11, unresolved
legacy emitters, unavailable external/OS profiles, full-goal verification and
release gates remain incomplete. No publication, deployment or production
migration occurs.

## Dynamic tool history

The later tool continuation adds owners481/482/504/505: raw FunctionCall and
FunctionCallOutput metadata properties and their non-null branches. A second
case in the same owning file uses the unchanged normal provider's ordinary
`dynamic_tool` scenario. It receives one genuine native `item/tool/call`, checks
literal arguments, appends one owned effect record, and returns a prescribed
result through the normal Session response API.

The source turn consumes exactly two provider requests. After closing/reaping
the source, the test captures four complete native-created payloads in order:
user, function call, function output and assistant. It checks literal name,
arguments, call ID and output. Call metadata is exactly the original `turn_id`;
output metadata adds independently host-bounded `create_time`. A cold native
imports those maps unchanged into a distinct thread, without inference,
another tool request or another effect. One followup consumes the original
arguments/result with supplied-history initialization. The inference budget is
strictly **2 → 2 → 3**, and effect/dispatch counts remain one through shutdown.

Pinned `core/src/tools/handlers/dynamic.rs:125–169` performs the real client
dispatch; `core/src/tools/context.rs:579–603` turns the single text response
into raw function output. `protocol/src/models.rs:1455–1484` stamps output
creation time. Ordinary executed-tool metadata capture defaults off in
`features/src/lib.rs:1148–1152`. Explicitly enabled host-only fields deliberately
skip deserialization (`models.rs:989–1008`); this test does not claim to retain
those fields or manufacture them. Explicit-null owners483/506 stay missing.
The upstream unstable-import/new-identity limits still apply.

The media test body is byte-identical to the preceding commit, independently
checked by `/tmp/samgita-v303-functional-checks/media-preservation.json`.
Its preserved fragment SHA256 is
`7fcda2dc4029b8cddd85f67ad0adba15f0750ba6155e32e3102a0f745c895038`.
The combined owning file passes **2/0 twice**, seeds501432/987654, with no native
semantic failure or repair round. Logs are
`/tmp/samgita-v303-history-{501432,987654}.log`; final file SHA256:
`77d8a5b64107c505f2b7d988084b13b2fa0245feca86225950eb95a6ee368e83`.

## Canonical tool values

Eleven shared definition owners gain direct existing native evidence:

| Owners | Exact observed values and limits |
| --- | --- |
|2080/2081/2085/2088 | Stable collaboration state message string/null and status completed/notFound. |
|2090–2093 | Actual completed item tools sendInput, resumeAgent, wait and closeAgent. |
|2100 | Closed-child wait completes with failed status. |
|2118/2119 | Exact dynamic started inProgress and successful completed maps; completed survives warm/full/selective and first-cold selective history. |

The existing collaboration profile prescribes literal child messages/states,
checks exact completed maps and warm selective history, and independently
checks actual provider results. It does not replace the native process or
assert timing-dependent spawn/send/resume state snapshots. The dynamic profile
checks full maps and one real handler execution; its inProgress value is
live-only. Started collaboration status2098, interrupted2101, failed dynamic2120
and other tool/status values remain unqualified.

Direct conversions are in
`app-server-protocol/src/protocol/v2/item.rs:948–983,1198–1203,1237–1259,1305–1335`.
Dynamic lifecycle production is in `tools/handlers/dynamic.rs:218–270`.
`core/src/tools/handlers/multi_agents/{wait,close_agent,send_input,resume_agent}.rs`
supplies the exact terminal state/tool identities. These are direct literal
observations, not evidence inferred from identical hashes or references.
The unchanged collaboration/dynamic test SHA256 values are respectively
`a196c56d901a47cd682de62b79bf999dcec947b989f83ed4686e7b41544df9d0` and
`f803912fa5fcfabb09f62affb7fc8418ebae26937749c2127163cacd23444d84`.

## Tool continuation evidence

`/tmp/samgita-v303-run.py` records all eight serialized commands in
`/tmp/samgita-v303-functional-checks/functional/results.json`. The final
41-file matrix passes **77/0 twice**, seeds501432/987654, in
136.624/130.713 seconds. Compile with warnings as errors, scoped format,
strict Credo on 491 sources, outside actual-binary consumer **1/0**, seventeen
fixture ASTs and the **279-source** before/after guard pass.

| Evidence | SHA256 |
| --- | --- |
| Results | `294e115f93055bdef73a6d5b153e5648b24aebefff80fa226c783ce74b5cad77` |
| Source guard | `0f635f0ed68d709fc190cd3900894d8551aeb115d93b646a205eb52cda694e1d` |
| Pinned-source evidence | `31b3566f0abb770311a35bc06de3e6e6ac8020cd5e8bb57c15eb9ce5454380c5` |
| Resulting manifest | `52963c9f039319b8610115398073961995e44cfb7418b9f67e1f530e305ad504` |

Nineteen complete source files match the immutable archive. Twenty exact nodes
include the five unchanged null/status counterexamples; unique complete-record
patches, original/current rows and tested bytes are bound in
`source-evidence.json`, `manifest-binding.json` and `final-binding.json`.
Inventory consistency passes; strict completeness exits **1**.

Contracts become **4,889 implemented / 1,673 missing / 59 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**, zero
verified. Prohibited security/permission checks, broad/hosted workflows, A11,
unresolved legacy emitters, unavailable external/OS profiles, full-goal
verification and release gates remain incomplete. No publication or deployment.
