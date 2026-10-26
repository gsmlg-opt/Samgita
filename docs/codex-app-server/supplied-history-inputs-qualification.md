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
an incorrect oracle. Explicit-null metadata/phase owners376/379 were left open
here and are qualified separately in the client-input differential unit below.

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
those fields or manufacture them. Explicit-null owners483/506 were left open
here and are qualified separately in the client-input differential unit below.
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
owners390/497 are handled separately below; server-side search, absent/null call IDs and encryption variants
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
provider IDs remain literal in durable history. Explicit-null owners519/530 are
handled separately below; encrypted content, namespace/status alternatives and
stable import remain open.

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

## Explicit-null client inputs

Eight new differentials exercise **modified client input**, using the original
four real-native histories above. Each clones the captured payload list and
sets exactly one selected field on one record to explicit null. This does not
claim native-null emission or unchanged-map import. The source assistant phase
is originally absent: its differential deliberately adds null, while the other
seven selections replace actual captured non-null metadata objects.

| Owner | Selected physical client field |
| --- | --- |
|376|Message internal metadata, null alternative|
|379|Message phase, null alternative|
|483|FunctionCall internal metadata, null alternative|
|506|FunctionCallOutput internal metadata, null alternative|
|497|ToolSearchCall internal metadata, null alternative|
|390|ToolSearchOutput internal metadata, null alternative|
|519|CustomToolCall internal metadata, null alternative|
|530|CustomToolCallOutput internal metadata, null alternative|

Each physical node is `{ "type": "null" }`, SHA256
`b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb`.
Only those exact `ClientRequest.json` locations can be promoted. No shared-hash,
parent branch, other nullable field or server-output promotion follows.

One additional cold owned native per original case accepts two serial imports.
Each yields a distinct new idle thread ID/path, preserves every other field,
original ID and ordering exactly, and durably omits only the selected key.
The helper asserts complete selected maps, distinct IDs, exact count and field
absence. Submitted null remains distinct from expected omitted-key output.
The source rollout bytes, configuration/scripts and effect files remain
unchanged through explicit close/reap. No added turn-start, inference, client
callback, fileChange, pending interaction or uncertain operation occurs.

The original four unchanged-history import/followup journeys still run after
these differentials with the same inference budgets and assertions. Removing
only the four added helper call blocks and their formatter whitespace restores
each original case body byte-identically. New file snapshots compare
bytes/inode/size and **second-resolution** mtime/ctime; they do not establish
nanosecond or continuous monitoring. The retained custom provider independently
compares its existing nanosecond snapshots across the broader import/followup
interval.

Nine complete producer files match the official immutable source archive:
`protocol/src/models.rs:1024–1228` derives deserialization and declares the
selected optional fields with skip-on-None serialization;
`app-server-protocol/src/protocol/common.rs:274–288` decodes the actual request;
`v2/thread.rs:354–362` exposes the unstable history input;
`app-server/src/request_processors/thread_processor.rs:4791–4803` clones decoded
records into `InitialHistory::Forked`; `core/src/session/mod.rs:1729–1770` assigns
only missing IDs and persists the original records. Replay reconstruction at
`session/mod.rs:1831–1835` is separate. `thread-store/src/live_thread.rs:220–266`,
`rollout/src/policy.rs:22–29,80–99`,
`thread-store/src/local/live_writer.rs:340–350` and
`rollout/src/recorder.rs:2107–2111` retain and serialize those records. Thus
explicit null becomes serde `None` and is omitted, without metadata restamping.

The initial owning file passes **4/0**, seed501432, in **10.1 seconds**. The first
integrated run stops at strict Credo's unused `Enum.reduce` return warning,
before native matrix execution. The correction consumes the two-import result
and asserts exactly two IDs/paths; it removes no assertion or bound. Failure
artifacts remain `/tmp/samgita-v308-functional-checks/functional/`. Final
commands/environment/results use `/tmp/samgita-v308-run.py` and
`/tmp/samgita-v308-functional-checks/final-functional/`.

The final **42-file matrix passes 80/0 twice**, seeds501432/987654, in
**138.338/137.779 seconds**. Scoped format, warnings-as-errors compile, strict
Credo on492 sources, outside actual-binary consumer **1/0**, twenty fixture AST
checks and the **283-source** unchanged-byte guard pass. Final source review
finds no functional defect within these limits; it does not replace execution.

| Evidence | SHA256 |
| --- | --- |
| Owning test | `76ec53bb37b7ffd12e3ca408ea6bb4409136b57cbc00c90fd5e396a5e9647347` |
| Results | `25461d45f883f15d8ee62a04f8f24f58cb533fd3174f2601b2428fb34cb9b91b` |
| Source guard | `4e0faa3b01f05c6315035e7134d13f3300d4bb6c5caccec54503b404b2717abb` |
| Pinned producers and eight nodes | `456ad3e7364abf6d7d344736f544d3bfb86f240c055fd552aa11cb34a6af36f4` |
| Original case preservation | `1a3cd54912486e1978ada41a32c135eb92737125d5e89d743620e26f921d77a7` |
| Resulting manifest | `0b840627652de4bb5b9c219569be114fd45da41a238a90fbe98f9c30d2972f07` |

An initial manifest patch emitted unique hunks out of file order and was
rejected without changing the manifest; sorted unique hunks apply successfully.
Final binding proves exactly eight promotions, unchanged schema identities,
planned tests and requirements, preserved four case bodies, and matching final
source hashes. Inventory consistency passes; strict completeness exits **1**.
Contracts become **4,905 implemented / 1,650 missing / 66 blocked**;
requirements stay **462 implemented / 12 missing / 11 blocked**, zero verified.
These inputs do not qualify native-null production, followup inference from
modified histories, arbitrary nullable values, stable import, other providers/
transports/OS, full-goal, A11 or historical/external profiles. Prohibited
security/permission/approval tests and broad/hosted workflows stay unrun.
No release, publication, production migration or deployment occurs.

## Reasoning history

The fifth supplied-history case captures genuine native user/Reasoning/assistant
records and qualifies seven exact client-input owners. The Responses provider
extension runs only for `reasoning_history`; its original `response_events`
function/registration and default behavior remain intact. The real immutable
binary creates every app-server event and rollout record. The literal provider
reasoning is synthetic fixture text, not external model-private reasoning.

| Owners | Physical input contract |
| --- | --- |
|350–353|Reasoning summary_text object, text, type and literal tag|
|458/459|Reasoning internal metadata property and non-null object|
|460|Reasoning internal metadata explicit-null input|

One source turn produces two summary objects and three mixed content objects:
`reasoning_text`, empty `text` and nonempty `text`, with independent literal
values. Ordered native start/completion events retain exact item arrays and
host-bounded millisecond timestamps. After source close/reap, bounded native
JSONL yields three complete records. The Reasoning retains its provider ID,
the complete summary/content object arrays and exactly `{turn_id: source_turn}`
metadata, without create_time. The user/assistant whole maps and distinct IDs
have separate literal and host-time oracles.

The existing two-import helper performs separate modified client-null inputs
for Reasoning metadata and already-covered user metadata. Only owner460 is new;
the user is not counted twice. Null normalizes to omitted metadata while every
other field/ID/order remains exact and inference remains one. These are client
mutations, not native-null metadata production. The helper is unchanged.

A third sequential owned native imports the original three maps **unchanged**
into a distinct idle thread/path. Import causes no inference, turn-start, tool
work or newly generated reasoning. One explicit followup consumes the original
summary/content and conversation, returning only a new assistant answer.
Inference is **1 → 1 → 2** overall. The provider independently asserts the
complete Reasoning request copy and literal prior messages. Non-OpenAI request
copies omit internal metadata and IDs lacking underscore prefixes; the original
durable maps retain both. Every original imported map remains exact after the
followup. Source rollout, configuration/catalog/scripts and empty workspace stay
unchanged through close/reap, with the existing deadlines and bounds.

Fifteen full producer files match the official immutable archive. The new chain
uses `codex-api/src/sse/responses.rs:354–359` to decode ordinary Responses items;
`core/src/tools/router.rs:295–308` and
`core/src/stream_events_utils.rs:93–105,360–399` finalize non-tool records.
`core/src/session/mod.rs:3481–3484,3520–3551` preserves supplied IDs and stamps
turn metadata; `protocol/src/models.rs:1455–1484` excludes Reasoning creation
time. Its summary objects are declared at `models.rs:2093–2101`. Content
serialization at `:1734–1740` retains the mixed content array because it contains
one reasoning_text element. The previous unit's decode/fork/persistence chain
applies unchanged to the actual submitted records. `core/src/client.rs:1007–1009,
1092–1095` strips metadata/non-prefixed IDs only from provider request copies;
`core/src/client_common.rs:60–68,91–93` retains their summary/content.

The ordinary nullable `encrypted_content: null` in the native Reasoning map is
only a serialization observation. No non-null encrypted-content, encryption,
credential or other security behavior is exercised or inferred.

The owning file passes **5/0**, seed501432, in **12.4 seconds**, log
`/tmp/samgita-v309-history-501432.log`. There is no native semantic failure or
oracle correction. The initial draft patch's numeric hunk headers were rejected
before repository mutation; plain headers apply the identical code. Final
environment/commands and artifacts use `/tmp/samgita-v309-run.py` and
`/tmp/samgita-v309-functional-checks/`. Original four case bodies, existing null
helpers and the provider's original function/registration remain byte-identical.

The final **42-file matrix passes 81/0 twice**, seeds501432/987654, in
**147.110/140.949 seconds**. Scoped format, warnings-as-errors compile, strict
Credo on492 sources, outside actual-binary consumer **1/0**, twenty fixture ASTs
and the **283-source** unchanged-byte guard pass. Read-only review finds no
functional defect in the added profile; the real native runs establish the
stated behavior.

| Evidence | SHA256 |
| --- | --- |
| Results | `7561a958e4e8ca7578c7984d94199bd74d3a93cea083876f5fe19b0ddd0723a9` |
| Source guard | `e459f9a46988b208c75874d3342fe546964591466a7177380a6d1ca156464e03` |
| Pinned producers and seven nodes | `a1b0743fef93430399ea77d81b899d47f7fb1d1ebdc5fcea4e7f096fd1a2a267` |
| Prior cases/helpers/provider preservation | `2e920ed21ada0817978c67c45df5adef759cbdbaa95031b5c9dbb7060b7e36c6` |
| Resulting manifest | `73be5827b0ae0e918807f8cb61c3272a49f695faa4f262d06b407ad4267d6ff3` |

Unique whole-record patching and final binding prove exactly seven promotions,
unchanged schema identities/planned tests/requirements and preserved earlier
sources. Inventory consistency passes; strict completeness exits **1**.
Contracts become **4,912 implemented / 1,643 missing / 66 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**, zero verified.
Only the selected unstable input, local fixture and Linux/stdio profile are
qualified. Other branches/providers/OS/transports, full-goal, A11, historical/
external and release gates remain incomplete; prohibited security/permission/
approval tests and broad/hosted workflows remain unrun. No publication,
deployment or production migration occurs.

## Completed web-search history

The sixth history case uses the existing streamed provider's primary
added/done pair behind the new `web_search_history` scenario. Codex itself
produces the exact placeholder/final UI items and raw user/search/assistant
records. The default sixteen-item producer function/registration and five
previous case bodies remain byte-identical. The local fixture supplies inert
completed evidence; it performs no search/browsing request or native-row write.

Four exact `ClientRequest.json` owners are added:401/402 for the actual
WebSearchCall metadata property/object and398/403 for separately modified
client-null action/metadata inputs. The original raw search map has its literal
provider ID, completed status, search action with independently prescribed
primary query and differing query list, and exactly `{turn_id: source_turn}`
metadata. It contains no invented create_time or extra fields. Complete native
user/assistant maps have independent content, source-turn, timestamp and ID
oracles; the UI placeholder/final camelCase maps are asserted separately.

After source close/reap, two independent client-null imports clone that genuine
history and change only search metadata or action to explicit null. Native
serde omits exactly that key, preserving every other field/ID/order with no
inference. The existing two-import helper body and invariant stay unchanged;
one additional source-field clause requires a genuine web_search_call with a
populated action. Existing metadata/phase clauses are retained.

A third sequential owned native imports the three original maps **unchanged**
into a distinct idle thread/path without turn-start or new search/tool work.
One explicit followup consumes exactly the completed search evidence and prior
conversation, returning an assistant only. Inference is **1 → 1 → 2**. The full
outgoing search oracle independently omits only the non-OpenAI passthrough and
non-prefixed provider ID; durable originals retain both. Source and imported
original maps remain exact through followup and close/reap, with unchanged
configuration/catalog/provider bytes and empty owned workspace.

Twenty-one full producer files match the immutable source archive. In pinned
`protocol/src/models.rs:1227–1245`, the selected optional fields use skip-on-None
serialization; `:1447–1484,1554,1621` supplies turn metadata without search
creation time. `codex-api/src/sse/responses.rs:354–359` decodes the done item;
`core/src/session/turn.rs:2801+,2934+`, `tools/router.rs:257–308` and
`stream_events_utils.rs:93–105,360–399` produce native non-tool lifecycle and
persist its original map. `event_mapping.rs:228–239` and `web_search.rs:3–29`
define the distinct UI query/action. The retained fork/persistence chain stores
the submitted raw originals without restamping; `session/rollout_reconstruction.rs:
513–518` and `context_manager/history.rs:1033–1053` retain their API history.
`client_common.rs:60–68,91–93` and `client.rs:1007–1018,1092–1095` explain exact
provider-copy normalization. No schema/ref or different wire-location inference
is used.

The owning file passes **6/0**, seed501432, in **15.2 seconds**, log
`/tmp/samgita-v311-history-501432.log`. No native semantic failure or oracle
repair occurs. Existing 60-second cases,20-second lifecycle bounds,256 events/
1 MiB capture and4 MiB file/256 KiB line bounds remain. Exact final environment,
commands/results/source guard use `/tmp/samgita-v311-run.py` and
`/tmp/samgita-v311-functional-checks/`. Read-only review finds no functional
defect within the stated profile and does not replace native execution.

Owner399 stays missing: this producer's omission supplies no input evidence for
that field. Client-null normalization does not establish native-null emission,
search restoration, actual browsing/backend semantics, other actions,
stable import, arbitrary legacy history, external providers/OS/transports,
full-goal, A11 or release. Prohibited security/permission/approval tests and
broad/hosted workflows remain unrun; their gates stay incomplete.

The final **43-file matrix passes 84/0 twice**, seeds501432/987654, in
**160.017/146.886 seconds**. Scoped format, warnings-as-errors compile, strict
Credo on493 sources, outside actual-binary consumer **1/0**, twenty-one fixture
AST checks and the **285-source** unchanged-byte guard pass. Other283 code
sources match the preceding committed checkpoint; the two-import body,
five case bodies and default provider function/registration also match exactly.

| Evidence | SHA256 |
| --- | --- |
| Results | `0a8ee950294a72be3b3cdaebb306ac739243a768b6a34ec3fc0236e6ccc929c4` |
| Source guard | `cb790e0ba82f550fd5fe99aedbee6baf7981415d4c4089734b3bfe9894dd8024` |
| Twenty-one pinned files and five nodes | `5863e9feddab469ae13cb413dc300a526bf5aa61f0d83e56821b6c26623bbf70` |
| Case/helper/default preservation | `67441dd1c5292d0a5043bcba8a82ae081e13713a277bdeb7ecca2cd47ca022e0` |
| Resulting manifest | `a0963d14bdba1df7a8125971d18353c17e7ac803472e3a221464e5cc72a0d7d5` |

Unique-record patching and final binding prove exactly four promotions and
unchanged schema identities/planned tests/requirements and excluded owner399.
Inventory consistency passes; strict completeness exits **1**. Contracts become
**4,923 implemented / 1,632 missing / 66 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified. Full-goal, A11,
historical/external/OS and release gates stay incomplete. No publication,
deployment or production migration occurs.
