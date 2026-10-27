# Ordinary compaction and root SessionEnd hooks

V493/V494 qualify three selected HookEventName values against official
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, binary
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
Linux x86_64 musl/stdio. Stock Codex executes every hook and emits every
app-server frame. Finite loopback providers supply model Responses SSE only;
they never write native history or fabricate protocol notifications.

## Manual remote-v2 compaction

`native_compact_hook_test.exs` completes one seed turn, explicitly requests one
successful manual remote-v2 compaction, then completes one continuation. Two
predeclared synchronous commands receive genuine native stdin, write separate
exclusive process records, return `{}` and exit0. Their one-second limit and
fixed positive activation are fixture setup; no trust or permission variant is
tested. The original native compaction sequence must be exactly:

```text
turn/started
hook/started(preCompact) -> hook/completed(preCompact)
item/started(contextCompaction) -> item/completed(contextCompaction)
hook/started(postCompact) -> hook/completed(postCompact)
turn/completed
```

Complete independent hook maps require exact event/run IDs, native thread/turn,
source/config path, discovery order0/1, command/sync/turn scope, fixed Unicode
status message, running/completed states, empty entries and bounded native
timestamps/duration. Both context-item envelopes retain their required original
startedAtMs/completedAtMs. Original JSON capture must equal each delivered
envelope and validate against the pinned notification schema. RPCs retain exact
outgoing/incoming bytes and correlation. A prior source review corrected an
omission of the required item timestamps before integration; no runtime failure
or weaker assertion is substituted.

The provider independently requires PreCompact's process record before request2
and no PostCompact record yet. Request3 must contain both records with the same
native compaction IDs, the retained seed/followup inputs and the exact supplied
checkpoint. This proves installed history is consumed. Exactly three requests,
four hook notices and two distinct exited hook PIDs remain after the completed
continuation plus native query/drain barrier; elapsed silence is not the oracle.

Production ownership: `core/src/tasks/compact.rs:43–74` selects manual remote-v2;
`compact_remote_v2.rs:196–247` awaits pre, item start, installation and post in
order. `compact_remote_v2_installation.rs:204–280` commits history and emits item
completion before post. `compact_remote_v2_attempt.rs:66–155` and
`compact_remote_v2.rs:480–575` preserve native history/checkpoint semantics.
`core/src/hook_runtime.rs:544–607,875–925`, `hooks/src/events/compact.rs:57–340`
and hook dispatcher/discovery own actual command inputs, outcomes, IDs/order and
timing. App-server event mapping preserves their original notifications.

## Root replacement SessionEnd

`native_session_end_hook_test.exs` completes two ordinary turns, confirms stored
item/turn IDs, then performs one `thread/revert` before the second turn. A full
SessionEnd started/completed pair must lie between that original request and
its correlated response. The actual independent command record requires native
session/cwd, reason `other`, actual exited PID and a fixed Unicode marker.
Native SessionEnd stdin has no turn_id; the public notification has an internal
`auto-compact-N` turnId distinct from all user turns. These are checked
separately rather than inventing an ordinary execution turn.

The first history row/items retain their IDs; the reverted second row is absent.
A third ordinary turn completes on the replacement. Its actual provider input
contains the first/followup markers and excludes the second marker, with exactly
one recorded SessionEnd invocation. All three requests retain genuine native
thread/turn metadata. Complete hook maps, timestamps, original wire/schema and
the final query/drain are checked, with no additional inference or hook pair.

`app-server/src/request_processors/thread_processor.rs:2150–2229` explicitly
waits for shutdown and drained shutdown events before replacement; its
`thread_lifecycle.rs:324–393` listener forwards hook events before releasing that
waiter. `core/src/session/handlers.rs:291–392` runs root SessionEnd before
ShutdownComplete. `core/src/hook_runtime.rs:471–500` flushes and emits its pair;
`hooks/src/events/session_end.rs:20–143` supplies `other`, no turn_id and the
actual successful command. Revert then preserves identity/subscriptions and
reloads retained history. The history projection intentionally ignores hooks,
so no user turn is fabricated for the internal shutdown ID.

Final owned-process shutdown may execute SessionEnd again on the replacement.
That separate invocation is retained under its own exclusive ordinal, checked
with the same original session/reason and distinct exited PID. One or two total
records are allowed only at final cleanup; the target revert requires exactly
one. An extra third invocation is preserved and fails the count gate. The
first record must remain byte-for-byte unchanged. Delivery of a final cleanup
pair through closed stdio and whole-process graceful-hook coverage are not
claimed. No handler or record is disabled/deleted to force cardinality.

## Verification and scope

Focused command, in the pinned Devenv Elixir1.18.5/OTP27.3.4.17 environment:

```sh
mix test test/native_compact_hook_test.exs test/native_session_end_hook_test.exs \
  --warnings-as-errors --seed 501432
```

Result **2/0**, 4.4s, log `/tmp/samgita-v493-v494-focused-501432.log`.
SHA256 `3b1d2c3bdae6473f3718e0a4c79460a6f495b057db00e5fd104775d8cf39db0d`.
Python AST checks pass. The first combined selection passes **102 ordinary
native cases at both seeds501432/987654**, all three selected WebSocket cases
at each fixed seed, outside consumer **1/0**, inventory, compile and format.
It then stops at step12/14: strict Credo reports compact-test nested helpers
and arity9. Dialyzer/assets do not run in this attempt. Original record:
`/tmp/samgita-ordinary-v493-v494/results.json`, SHA256
`ce77ee6b6f792d7aa6be44a9c1ac7f6d866562fa64dafe3272003bcc7fe9deba`;
`source.json` SHA256
`84477b14301bdef6aca5ed4da11e18f62904b2844b6b2be74674d6e9bbd3a117`;
Credo log SHA256
`44defdb2bac5d2555faee6bc7e244726f91c16142f032e9681acbf9bf69bd5f3`.

The correction extracts target-turn lookup and hook-PID checks into explicit
helpers and groups the existing name/order arguments as a tuple. Every
assertion, expected value, timing/size/count limit and cleanup operation stays
the same. Corrected focus **2/0** and full strict Credo pass:
`/tmp/samgita-v493-v494-refactor.log`, SHA256
`5be8f8895b75e46dfce90325935a1557b8e7aad6a3679158259ac7a3a27daf9e`.
The corrected second seed987654 also passes **2/0**,4.1s:
`/tmp/samgita-v493-v494-refactor-987654.log`, SHA256
`32b38bcc3edcd2928df5fba6be8540df4865688cbf2c0aa5317b93627d39dedc`.
The scoped binding checks all **29** selected complete producer sources against
the immutable archive, all three exact canonical nodes and final test/fixture/
helper bytes: `/tmp/samgita-v493-v494-focused-binding/evidence.json`, SHA256
`e4199e74047b5d2fcb99dc47a0c2cce47865652081fe93ed9774e6cacb178cd0`.
The final combined-source matrix remains required and follows with the separate
ordinary child/tool hook unit; these scoped passes do not stand in for it.

Both cases keep 60s case/20s journey/5s observations and existing checked stdio
owner completion/reaping, native/provider executable identity, closed Ports,
vanished owned PIDs and bounded listener/handler shutdown. Limits are128 raw
frames/events,2MiB capture,64KiB inbound frame/hook stdin/journals,8KiB outbound,
1MiB request and4KiB invocation. No sleeps as absence proof, retries, timeout
increases, skipped assertions or production runtime changes are introduced.

Only physical owners **2212/2213/2215** gain scoped implemented evidence; no
aliases or whole method promotion. Counts become **5,454 implemented / 1,051
missing / 116 blocked** contracts; requirements remain **462 implemented /
12 missing / 11 blocked**, zero verified. Remaining hook events, faults,
asynchronous/prompt/agent handlers, OS/transports and external success are
unqualified. Fixed YOLO is setup only. No security, credential, authentication,
authorization, permission or approval tests/audits, broad suites or hosted
workflows run. A11, unreachable upstream emitters and full-goal/release gates
remain incomplete. No publication, deployment or production data changes.
Rollback removes this test/fixture/evidence unit without changing stored data.
