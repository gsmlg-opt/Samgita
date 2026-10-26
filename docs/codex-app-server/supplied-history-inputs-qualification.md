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

## Client tool-search history

The third supplied-history case adds exactly owners388/389/495/496: raw
ToolSearchOutput and ToolSearchCall metadata fields and non-null object branches.
The new Responses-only fixture delegates its first three replies unchanged to
the reviewed deferred-namespace producer. The real pinned native executable
performs local BM25 search, returns the exact namespace/function schema, and
dispatches one genuine `item/tool/call`. Only the client handler appends the
owned effect and returns the independently prescribed result.

After source shutdown, six whole native payloads are selected in order: user,
search call, search output, function call, function output and assistant. Search
IDs use native `tsc_`/`tso_` prefixes. Call metadata is exactly the original
`turn_id`; output metadata adds host-bounded `create_time`. A cold import retains
all six original maps/IDs/order unchanged in a distinct thread/path. It produces
no inference or callback. One explicit followup consumes the completed evidence,
with a strict total inference budget **3 → 3 → 4** and one callback/effect.
Original rollout/config/provider bytes and owned process exits remain asserted.

The raw route carries ResponseItems, without SessionMeta dynamic declarations.
The followup therefore independently asserts that the owned namespace/function
is absent from callable tools. This proves completed-history consumption only;
it does not claim registration restoration or callable continuity. Explicit-null
owners390/497, server-side search, absent/null call IDs and encryption variants
remain unqualified. The two preceding case bodies are byte-identical.

Fourteen complete producer files match the immutable archive. The source chain
includes `core/src/tools/handlers/tool_search.rs:220–282`,
`core/src/tools/context.rs:218–252` and `protocol/src/models.rs:1455–1484`.
`core/src/context_manager/normalize.rs:21–86,170–225` distinguishes the complete
genuine pair from inserted empty results or removed orphan outputs.
`app-server/src/request_processors/thread_processor.rs:4200–4215,4780–4803`,
`core/src/thread_manager.rs:310–321`, `core/src/session/mod.rs:835–838` and
`history/src/lib.rs:448–460` establish the registration limitation.

Both initial focused runs pass **3/0**, seeds501432/987654. The first integrated
attempt then fails strict Credo, exit8: `assert_search_payloads/4` has complexity
12 against limit9. Extracting search-pair and function-pair assertions preserves
every assertion and deadline; no rule, exclusion or timeout changes.
The original failure remains in
`/tmp/samgita-v305-functional-checks/functional/strict-credo.log`.

The final runner uses `/tmp/samgita-v305-run.py` with only its output directory
changed from `functional` to `final-functional`. Exact eight commands and
environment are retained in that script and
`/tmp/samgita-v305-functional-checks/final-functional/results.json`.
The reviewed **41-file matrix passes 78/0 twice**, seeds501432/987654, in
131.996/131.092 seconds. Scoped format, warnings-as-errors compile, strict
Credo on491 sources, outside actual-binary consumer **1/0**, eighteen fixture
AST checks and the **280-source** before/after guard pass. Test SHA256:
`dc7a18d0d785105ba54099d5ce909afc81d88bf62a00791c7aa533959c8b2ba0`;
new provider SHA256:
`80bfd289eef8237184ed86bdd9445b9efc7873fff25f40fdb601c5f5be1a0520`.

| Evidence | SHA256 |
| --- | --- |
| Final results | `9ff81d9b69ff98e58968fdb4cb9183210fc8f294008a3867e245386bb84453d8` |
| Final source guard | `b5ce762264feef5a37f042d44ca43112fb6d37f6f34edfcd65219e300f86d00e` |
| Pinned files and six exact nodes | `cd8a762ea3fe071e4ca92d32d479c2a9316575cdad9d2f0f346ec18436a3a938` |
| Existing case preservation | `448de5ddb355b70ae0e7e6de43090889f2631432035a1c683d872cf23dcf26fa` |
| Resulting manifest | `e2eed96a36242b314cd3df101b28f8e8a900fd3d830a55f95e690a705204eb47` |

Unique whole-record changes and `final-binding.json` prove exactly four
promotions, unchanged null alternatives, previous function metadata and all
requirements. Inventory consistency passes; strict completeness exits **1**.
Contracts become **4,893 implemented / 1,662 missing / 66 blocked**;
requirements stay **462 implemented / 12 missing / 11 blocked**, zero verified.
Prohibited security/permission tests, broad/hosted workflows, A11, unavailable
external/OS profiles, historical/unreachable paths, the full goal and release
gates remain incomplete. No publication or deployment.

## Custom tool history

The fourth case adds exactly owners517/518/528/529: non-null raw CustomToolCall
and CustomToolCallOutput metadata input. A new Responses-only fixture asks the
real native freeform `apply_patch` tool to update an owned disposable file from
literal before bytes to literal Unicode after bytes. The fixture reads that
file; only Codex applies the patch. Exact started/completed fileChange counts,
literal raw call/output contents and one completed source answer are required.

The source is closed and reaped before capturing its four complete native
user/call/output/assistant payloads. A distinct cold native imports those maps
unchanged, preserving original IDs, turn IDs and host-bounded creation times.
One followup consumes completed evidence only. Inference remains **2 → 2 → 3**;
import/followup emit no fileChange or server request. File content/inode and
provider-observed nanosecond mtime/ctime/hash snapshots remain identical, as do
original source rollout bytes, configuration and provider sources.

Native output has exact success framing and trailing newline, with only its
numeric wall duration bounded independently by host turn elapsed time plus
the formatter's rounding precision. No arbitrary substring/output echo replaces
that oracle. Generated user/output IDs have UUIDv7 `msg_`/`ctco_` forms; original
provider IDs remain literal in durable history. Explicit-null owners519/530,
encrypted content, namespace/status alternatives and stable import remain open.

Fifteen complete producer files match the immutable archive. Genuine execution
is rooted in `core/src/tools/router.rs:295–305`,
`core/src/tools/handlers/apply_patch.rs:319–364` and
`core/src/tools/context.rs:317–333,579–598`. Formatting is in
`core/src/tools/mod.rs:89–113` and `apply-patch/src/lib.rs:826–840`;
`core/src/session/mod.rs:3472–3484,3520–3552` supplies metadata/IDs.

The initial full owning run fails **4/1**: the patch really executes and the
provider records its second request, but its oracle wrongly requires the
original non-prefixed call ID in the model request copy. Two diagnostic owning
runs retain the failure; a single-case diagnostic is **1/1, 3 excluded**, not
acceptance. The captured pure provider validator reproduces the exact assertion.
`core/src/client.rs:1092–1095` clears non-prefixed IDs in request copies, using
`protocol/src/response_item_id.rs:36–39`; it does not modify durable records.
Non-OpenAI metadata is independently cleared at `client.rs:1007–1009`.
The corrected provider oracle requires exact ID omission for the call and source
assistant while durable-map assertions still require both original IDs.
The corrected owning run passes **4/0**, seed501432. Temporary diagnostics are
removed; no runtime, timeout, assertion gate or cleanup behavior is weakened.
Original failure/diagnostic logs remain `/tmp/samgita-v306-history*-501432.log`;
the synthetic snapshot has SHA256
`01062d3b82a3bcc55b5826629ad44edb1cec5e06d2036e6e051e7b3a9de2af32`.

`/tmp/samgita-v306-run.py` retains exact environment/commands. Its final
**41-file matrix passes 79/0 twice**, seeds501432/987654, in
133.370/135.225 seconds. Scoped format, warnings-as-errors compile, strict
Credo on491 sources, outside actual-binary consumer **1/0**, nineteen fixture
ASTs and the **281-source** guard pass. The preceding three case bodies remain
byte-identical. Final test SHA256:
`be269285b2bc6f559fdd844755a6147fb1b0dc74669fd371a23caa9d42e857ff`;
provider SHA256:
`d0fb130fb2e16df6d0055cab9b3b897131e760979e837b5d75a12b77f6d8b402`.

| Evidence | SHA256 |
| --- | --- |
| Results | `6e6e2009991d8653d70a2ed11a0beb047ad29369829554e1ef0f8f9f43d31891` |
| Source guard | `0ffda8e2f810ba4e434481f754fc16e80ca9cc878532ead21c71c5c17df0eacb` |
| Pinned files and six exact nodes | `471a1a738e59caa6a6b6519fdb95423abb061c714021c17bdcfd84efd833b75c` |
| Existing case preservation | `bc16bbd8c4a6f78f52b23b100a6549ff480331eca20b984e5a9459a322074dd0` |
| Resulting manifest | `095ebea92009356225ef23f742e4385573d6fda8db504639d7b5e16983ec6eef` |

Unique whole-record patches and final binding prove exactly four promotions;
null alternatives, prior owners, schema identities and requirements stay intact.
Inventory consistency passes; strict completeness exits **1**. Contracts become
**4,897 implemented / 1,658 missing / 66 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified. Prohibited
security/permission tests, broad/hosted workflows, full-goal, A11,
historical/unreachable and external/OS profiles and release gates remain
incomplete. No publication, deployment or production migration occurs.
