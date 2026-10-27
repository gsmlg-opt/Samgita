# Outer collaboration-mode null preserves applied state

This ordinary functional unit starts from
`cc055939f0296b117385e297e75e0c47473289ed` on the existing `main`. One new
positive-only driver test uses the unchanged local assistant provider. Production
code, shared fixtures, protocol schemas, configuration and locks remain unchanged.
Fixed YOLO is launch setup; no security or permission behavior is tested.

Target: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Final test SHA256:
`c12e422c8933cdbc4fb008dd190dfe122d34f52ae9cc858f1ce20ba03a76d7c8`.

## Exact owner and native behavior

Only physical owner 6513 is selected:
`schema:v2/TurnStartParams.json#/properties/collaborationMode/anyOf/1`, the
explicit outer null branch. Its independently bound canonical-node SHA256 is
`b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb`.
Nested `settings.developer_instructions:null` and equal-hash nulls in another
request do not qualify this owner.

The [typed request:278–285][request] accepts an optional mode; actual
[turn processing:635–671][turn] preserves its optionality separately from
top-level effort. [StepSettings.apply:260–266][apply] retains the existing mode
when no complete mode object is supplied and applies independent model/effort
edits. [CollaborationMode.with_updates:727–752][updates] preserves both selected
mode and custom instructions. Native [context construction:26–78][context]
uses that retained state for actual model input. Thirty-nine complete upstream
files, including the typed graph, settings/context path and history constructor,
match their unique immutable archive members.

One real persistent thread completes four ordinary assistant turns:

| Turn | Original request fields | Applied mode/instructions | Effective effort |
| --- | --- | --- | --- |
| 1 | Complete custom Plan object | Plan and `OWNED_PLAN_NULL_KEEP λ` | medium |
| 2 | Present `collaborationMode:null`, top-level `effort:low` | Same Plan and exact custom instructions | low |
| 3 | Both fields omitted | Same Plan and exact custom instructions | low |
| 4 | Complete custom Default object | Default and `OWNED_DEFAULT_NULL_CONTROL λ` | medium |

Every request retains its original map, bytes and unique correlation ID under
normal validation. Turn 2 explicitly contains null; turn 3 lacks the field.
Actual start/completed items and completed turns retain their real native
thread/turn IDs and eight distinct live item IDs. Each corresponding provider
request independently requires its prescribed user text, model, effort and
native thread/turn metadata. The latest collaboration-marker-bearing developer
fragment contains the selected instructions. Old Plan text may remain in
history after turn 4; it is not confused with the current selection.

After each completed turn, a **summary-only** settings update alternates concise
and detailed. Only the resulting matching native `thread/settings/updated`
event supplies the snapshot barrier. The complete mode/settings map, effort,
model and provider must match the table. That update contains no target mode,
effort or instruction field, preserves exact provider-journal bytes and causes
no inference. An ACK or old instruction text alone cannot pass the oracle.

The provider synthesizes only four ordinary Responses assistant messages.
Stock Codex creates all app-server responses/events, state, IDs and history.
No app-server mock, seeded history, command, question or external service is
used. Exactly four model requests remain after repeated complete history reads.

## Preserved failed oracles and scoped corrections

The first run fails **1/1** after all four target settings/provider checks. It
incorrectly equates live item IDs with legacy full-history IDs. Pinned
[ThreadHistoryBuilder:267,514–535,1537–1540][history] starts at 1 and assigns a
fresh monotonic `item-N` identity to each reconstructed user/assistant item.
The correction requires the complete original item maps with precisely those
eight source-derived legacy IDs, explicitly distinguishes them from live IDs,
and retains live start/completion correlation, eight-ID uniqueness, all native
turn IDs, exact content/order and repeated full-history equality. Nothing is
removed from the native payload or rewritten by the driver. Corrected focused
execution passes **1/0**.

The first matrix then stops at three strict-Credo nesting/complexity findings
in the new capture helper, before its test block. Extracting frame selection,
bounded append and event reduction preserves native-object selection, atomic
capacity accounting, send-before-capture, event order and first-error halting.
Every setup/test/history/cleanup byte after `setup tags` stays identical to the
corrected version. The source review records the non-protocol scalar fallback
distinction; downstream native envelope validation remains intact. No behavior
assertion, capture bound, deadline or gate is weakened.

## Final qualification and limits

The five-file reviewed ordinary block passes **22/0 at both 501432 and 987654**.
It includes this new case, ordinary input-wait search, shared reasoning values,
personality and deprecated multi-agent values. Scoped formatting, driver compile,
strict Credo (552 files) and inventory consistency pass. All six commands finish
successfully; all 387 guarded source bytes remain stable, with all 386 prior
sources unchanged. The earlier **87 schema /154 ordinary driver twice** matrix
and outside consumer **1/0** retain their exact original source evidence;
neither is falsely reported as a new 155-case or aggregate run.

Capture requires exactly 14 correlated RPC exchanges, with 32 frames per
direction, 4KiB outgoing/65KiB incoming limits and 1MiB total. Event collection
is 256 events/1MiB, files 1MiB, requests/settings barriers 5s, turns 20s and the
case 60s. Config/catalog/helper/journal/rollout bytes remain exact, the workspace
stays empty, pending/uncertain/gap/buffer counts clear, and native close requires
owner completion, closed Port and absent owned PID. No new work is retried.

Only 6513 gains scoped implemented evidence. Requirements stay **462 implemented
/12 missing /11 blocked**; contracts become **5,077 implemented /1,478 missing
/66 blocked**, with zero verified in both. Runner and final command arrays,
logs and guard are `/tmp/samgita-v386-run.py` and
`/tmp/samgita-v386-functional-checks/final2/`. Initial red/green native sources
and logs remain under `/tmp/samgita-v386-native-*`, the failed lint matrix under
`final/`, immutable-source proof in `archive-evidence-final.json`, and the
source review at `/tmp/samgita-v386-source-review.md`.

Cold resume, other mode/field combinations, real providers and other deployment
profiles remain unqualified. Prohibited checks, audits, mixed broad suites and
hosted workflows remain unrun. A11, unavailable upstream producers, external/
backend/OS/platform success, full compatibility and release gates remain
incomplete. No package is published or service deployed. Rollback removes only
this test and exact evidence; historical records and production state remain.

[request]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/turn.rs#L278-L285
[turn]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/turn_processor.rs#L635-L671
[apply]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/step_settings.rs#L260-L266
[updates]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/config_types.rs#L727-L752
[context]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/context/world_state/collaboration_mode.rs#L26-L78
[history]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/thread_history.rs#L514-L535
