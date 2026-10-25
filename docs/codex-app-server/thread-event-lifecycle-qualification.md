# Native thread and event lifecycle qualification

## Context-window catalog qualification

Exact canonical owner **2746**, ServerNotification ThreadTokenUsage.
modelContextWindow, gains selected actual-native evidence from three ordinary
cases in native_token_context_window_test.exs. Each case owns a fresh model
catalog, process and paginated thread under fixed yolo setup:

| Prescribed catalog | Expected native notification value |
| --- | --- |
| context_window 100003, max_context_window 200009, effective percent 73 | 73002 |
| context window omitted, maximum 200009, percent 73 | 146006 |
| both windows omitted, percent 73 | explicitly present null |

These literal expectations distinguish context precedence, maximum fallback
and integer truncation. The unchanged provider-only thread_event_fixture.py
supplies SSE with input 7, cached input 3, output 11 and reasoning output 2.
The real pinned app-server must emit every thread/tokenUsage/updated notice,
with the actual requested thread/turn, exact last/total breakdown including
total 18, and the expected window using Map.fetch! so omission fails. Complete
turn/history text, actual provider input, exactly one provider call, unchanged
configuration/empty workspace, bounded 256-event/1 MiB collection, ready/empty
uncertainty and checked owned native PID disappearance reinforce the result.

The immutable
[model calculation](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/openai_models.rs#L518)
uses context_window.or(max_context_window) and integer multiplication/division.
TurnContext exposes that usable window; real sampling usage records it through
session state/history into TokenUsageInfo. The
[handler](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/bespoke_event_handling.rs#L1594)
converts the stored info into the identified notice, and the
[public conversion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread.rs#L1982)
copies the window directly. All eight complete inspected files match the
immutable archive; the exact canonical node, notification branch and export
match inventory/provenance. Independent review finds no actionable issue.
No scripted app-server frame or fixture-seeded history is used.

Base commit: `f68119c`. Focused v281 passes **3/0**, seed 501432, 3.053 command
seconds. The final twenty-eight reviewed functional files add this file to
the [origin matrix](config-override-metadata-qualification.md#origin-version-continuation).
Both explicit-list mix test commands with warnings as errors and seeds
501432/987654 pass **50 tests / 0 failures**, in **83.109/83.093** command
seconds. Scoped format, warning-free compile, strict Credo on 479 files,
outside actual-binary consumer **1/0**, four Python fixture AST checks and
the **254-source** guard pass. The unchanged SSE wrapper is now included in
both AST/hash checks. All eight commands complete; no check fails in this unit.

Final commands/environment/logs/hashes:
`/tmp/samgita-v282-functional-checks/functional/`. Results/source SHA256:
`8c21f7af32c666c447473f85e56e03a59e5f8b096818ece3f9d2641ede532ba3` /
`351d83cd12ef7e51e5d13df3021d348a8505ba4dea3047e88e8017eddbe6284d`.
Owning test SHA256:
`f657695928eeb6202390dd7b5d4f230bd2456505224d244c1d67841fd66b5764`.
The adjacent source-evidence.json SHA256 is
`c6b6eb63acb967e7996d483e8d2187961f41ee4713a99a0747081141bf0009a3`;
manifest-binding.json records the one original/current owner and final binding.
Inventory --check passes; contracts become **4,733 implemented / 1,829 missing /
59 blocked**, unchanged **462 implemented / 12 missing / 11 blocked**
requirements and zero verified. Strict completeness still exits **1**; all
schema identities/planned tests and requirement records remain intact.

Only this selected field value/null behavior is qualified. Saturation/extreme
percentages, step-model changes, accumulated/restored/spending-only usage,
other notifications/aliases, backends/OS/transports and the entire lifecycle
remain unqualified. Runtime/shared-helper/dependency/platform configuration is
unchanged. Security/permission tests, audits and broad/hosted workflows remain
unrun; the earlier lifecycle block below retains its original source/scope.
Full compatibility, A11, source-unreachable alternatives, external/platform
profiles and release remain incomplete. No publication or deployment occurs.

## Previous lifecycle checkpoint

SELECTED NATIVE BEHAVIOR VALIDATED. The eight owned cases passed against the
actual pinned app-server at both seeds below. This establishes the selected
Linux stdio lifecycle behavior, not full client/driver compatibility.

The target is immutable Codex rust-v0.163.0, source
83086188ae0614bd882818ff1aa23f3194962012. The existing-source audit began at
bc437ca91d52b19bc98e8f74f179d9e3edee296f. Installation and native validation
began with baseline e636b07858c40e7eb8d1b56d0b548e6128af2a3e; parent
integration advanced HEAD to d7bfa3965ab7276a4975c6e414e03a960cd21d50
before the final evidence review. This unit changes only the three paths below.
Binary SHA256: 399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215.

## Ownership

- apps/samgita_codex_driver/test/native_thread_event_lifecycle_test.exs
- scripts/codex/thread_event_fixture.py
- docs/codex-app-server/thread-event-lifecycle-qualification.md

The installed repository files are authoritative; earlier /tmp drafts predate
formatting and the narrow repairs below. The existing-source audit
is /tmp/samgita-core-thread-turn-evidence-audit.json: 28 exact entry candidates,
68 scoped schema candidates and nine directly unasserted core notices. That
audit neither changes the ledger nor establishes full method qualification.

## Existing evidence and reason for this unit

Existing actual-native tests already prove archive/list visibility, unarchive,
delete/read rejection, loaded membership, name readback and cold persistence.
Those behaviors should not be reimplemented as new CRUD-only scenarios. The
earlier test sources did not directly assert thread/started, thread/status/changed,
thread/name/updated, thread/closed, thread/archived, thread/unarchived,
thread/deleted, thread/tokenUsage/updated or item/agentMessage/delta.

The ordinary ModelFixture sends response.created, response.output_item.done and
response.completed. Its complete agent text cannot establish streamed deltas.
The new small provider wrapper imports that fixture unchanged and supplies
response.output_item.added plus five ordered Unicode output-text deltas, the
matching completed item and distinct synthetic usage counters. It emits only
provider SSE. The actual pinned app-server must emit every tested JSON-RPC
notification.

## Pinned contracts

All Rust paths below are relative to codex-rs.

- core/tests/common/responses.rs:821–832,847–865 defines completed assistant
  messages, added message items and minimal output-text deltas. The wrapper
  uses those shapes, including an empty starting content string and a full
  completed string.
- codex-api/src/sse/responses.rs:118–156,348–366 converts provider usage and
  maps output_item.done/output_text.delta. The cached-input field defaults
  cache-write tokens to zero. core/src/session/turn.rs:3120–3150 routes text
  deltas through the active assistant item; app-server-protocol/src/protocol/
  event_mapping.rs:363–373 preserves thread/turn/item/delta identity.
- app-server/src/request_processors/thread_processor.rs:1580–1664 resolves
  the idle start summary, replies, then sends thread/started.
  thread_summary.rs:220–223 clears turns only for that notification.
- app-server/src/thread_status.rs:150–160,333–350,423–468 defines active, idle
  and notLoaded transitions and emits only changed statuses.
  bespoke_event_handling.rs:155–204 emits active status before turn/started,
  then idle status before ordinary completed turn handling.
- bespoke_event_handling.rs:1315–1352 describes the terminal summary: the final
  agent item is included with itemsView=summary; absent final items use
  notLoaded. The ordinary started snapshot clears items with
  itemsView=notLoaded. Turn timing and generic item notification timing are
  separate fields and are asserted directly.
- app-server-protocol/src/protocol/v2/thread.rs:1974–2023 defines total/last
  usage and the complete TokenUsageBreakdown, including cacheWriteInputTokens.
  bespoke_event_handling.rs:1587–1610 emits usage only when info is present.
- thread_processor.rs:671–693,1861–1895 normalizes nonempty names, replies,
  then sends the identified name notice. Empty names fail before mutation.
- thread_processor.rs:626–648,762–779 emits archive/unarchive notices after
  responses. thread_delete.rs:7–27,31–73 deletes before response/identified
  deleted notices; loaded nonpersisted threads reject deletion.
- thread_processor.rs:1034–1060 returns unsubscribe status. It does not directly
  send closed. The default unload delay is 1800 seconds
  (core/src/config/mod.rs:4031–4032). Only one test explicitly sets
  thread_unload_delay_secs=0 in its owned synthetic config and waits for actual
  idle eviction. thread_lifecycle.rs:430–473 emits notLoaded and closed after
  successful eviction of the current unsubscribed runtime.
- thread_processor.rs:4402–4461 sends a cold-resume response and restored usage,
  without emitting thread/started. Cold resume does not replay old turn/item
  lifecycle. The other thread/started emission at line 5710 belongs to fork;
  it is not evidence of resume emission.
- initialize_processor.rs:82–93,137 stores notification opt-out names for the
  initialized connection. app-server/src/transport.rs:108–125 matches the exact
  method string, not a prefix. The test qualifies sequential owned
  stdio initialization profiles; concurrent connections to one service remain
  outside that proof.

## Eight validated cases

1. Start emits exactly the correlated idle summary. Selected thread metadata
   and configured cwd/provider/model are directly asserted with zero inference.
2. Real streamed Unicode: thread status, turn/item start, five exact deltas,
   item/turn completion, identity/order, direct timing fields, terminal summary
   and nonzero usage breakdown. No event is manufactured by the test transport.
3. Two owned threads start turns and retain independent delta, item, terminal
   and status associations, distinguishable provider text and persisted history.
4. Normalized name notice/readback survives cold process restart. Rejected blank
   names and missing-thread metadata commands cannot emit successful notices.
   A later successful name notice is an explicit observation barrier.
5. Archive/unarchive/delete emit their exact identities following the distinct
   commands. The single original inference remains the only provider request.
   No closed event is inferred from archive/delete acknowledgements.
6. Configured zero-delay idle eviction yields an actual closed notice after
   unsubscribe ACK, with notLoaded state and loaded-list absence. A subsequent
   request returns notLoaded. notSubscribed remains unqualified.
7. Explicit cold resume restores identical history and usage without
   thread/started, historical turn/item/delta replay or another provider request.
   A later successful named event bounds the observation.
8. Exact opt-out suppresses deltas while keeping turn/item completion. A second
   initialized process with only a prefix name receives actual deltas, proving
   exact-name handling and absence of persisted suppression. This does not
   prove concurrent connection fan-out.

## Isolation and validation evidence

All HOME, CODEX_HOME, workspaces, history, config and listeners belong to
TurnFixture's scratch root; no sibling repository, paid provider or live task
is accessed. The fixture script path is supplied only during TurnFixture.setup
and restored immediately in try/after; the test module is async:false.
Stdio cleanup is registered immediately after every native start.

Validation ran sequentially under the exclusive Mix/Devenv/native slot, using
`devenv shell --no-tui --` and the installed
`tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl` binary:

- Independent driver `MIX_ENV=test mix compile --warnings-as-errors`: passed.
- Independent driver `MIX_ENV=test CODEX_BINARY=<pinned binary> mix test
  test/native_thread_event_lifecycle_test.exs --include real_codex --seed 501432`:
  8 tests, 0 failures, 7.0 seconds.
- The same command at seed 987654: 8 tests, 0 failures, 7.1 seconds.
- Changed-file `mix format --check-formatted`: passed.
- Root `MIX_ENV=test mix compile --warnings-as-errors`: passed.
- Root `MIX_ENV=test mix credo --strict --files-included
  apps/samgita_codex_driver/test/native_thread_event_lifecycle_test.exs`:
  no issues, exit 0.
- That option did not restrict file selection; the successful root Credo run
  analyzed all 319 source files. It is aggregate lint evidence.
- Python `ast.parse` of the installed provider fixture: passed without import or
  server startup. All three owned paths passed whitespace checks.
- Validation session 81968 exited 0. A subsequent /proc scan found no process
  with an owned turn-fixture scratch cwd or owned thread-event fixture command.

Final log: `/tmp/samgita-native-thread-event-repair-2.log`.
The original Credo check found cyclomatic complexity 10 (maximum 9) in
`assert_stream`. Sol repair 1 extracted event scoping/order assertions into
`assert_stream_order`, retaining the assertions and deadlines. Its native run
then reported 8 tests, 1 failure: `BadBooleanError` because the concurrent-turn
wait used a nullable terminal result as the left operand of `and`. Sol repair 2
requires both exact thread/turn terminal results to be non-nil. It preserves
the two required matches and all deadlines. That repair produced the passing
two-seed evidence above. The failed native log is
`/tmp/samgita-native-thread-event-repair-1.log`.
Sol repair rounds: two, one unsuccessful; Astra rounds: zero.

Exact positive schema/entry mapping is recorded separately in
`/tmp/samgita-thread-event-direct-schema-pointers.json`, with installed test
anchors and separate negative, empty-only and null-only evidence. This unit
does not modify the shared manifest or promote unasserted fields.
Unexercised Thread/Turn fields, null branches, other statuses/handlers,
concurrent connections, non-Linux/non-stdio transports, external success
profiles and A11 remain incomplete. No publication or production readiness
claim follows from this selected qualification or its existing-source audit.
