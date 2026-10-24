# Native goal provenance, quota stop and stock tools

Three additive cases use the unchanged stock `rust-v0.163.0` executable, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Codex owns its goal runtime. These tests introduce no Samgita reasoning loop,
Task acceptance, provider account or paid inference.

## Provenance and actual populated clears

`native_goal_origin_test.exs` creates and edits a populated paused goal for each
origin: omitted, explicit null, automatic and user. Each has distinct prescribed
objectives. An explicit-null status edit changes the objective while preserving
status, budget, creation identity and accounting. Every successful clear returns
exactly `cleared:true` and its exact target notification; repetition returns
exactly false without a mutation notice. A second thread's full sentinel goal
remains unchanged throughout, including cold reads before runtime loading.

Cold resume has its own exact absent-goal snapshot. Only one later explicit
assistant-only turn requests inference from a local synthetic dependency. Its
native-built input contains the two user objectives once each, in order, and
exactly two user-clear instructions. Other origins and sentinel text add no user
provenance. Repeated explicit user clear appends another instruction even when
the state result is false; notification idempotency does not erase that fact.
The test constructs and checks outgoing parameter presence but retains no
independent raw capture of those goal RPC requests.

Exactly nine previously missing physical owners gain scoped implemented
evidence: ClearParams origin and both branches, ClearParams.threadId,
ClearedNotification.threadId, SetParams origin and both branches, and the
SetParams.status null branch. Each exact pointer/hash is in the manifest; the
origin enum owners were already implemented. No alias, entire union, invalid
origin, concurrent mutation or authorization grant is inferred.

## Actual HTTP quota failure and stopped recovery

The additional `native_goal_budget_profile.exs` case supplies one actual HTTP429
`insufficient_quota` response from an owned loopback Responses peer. A second
HTTP attempt fails the fixture. Sole trigger: a user active-goal mutation with
budget20. There is no client turn/start, status rewrite or tool reply.

Stock Codex emits one failed turn and the exact `usageLimitExceeded` error with
`willRetry:false`, computes `usageLimited` with zero tokens, and persists the
failed empty-item history. All goal maps, turn associations, ordering, monotonic
accounting and raw dependency bytes/digests have independent assertions. Warm
runtime status remains `systemError`; after cold resume it is idle. The complete
goal/history stay unchanged through both states, with no additional inference.
Bounded quiet checks retain the fail-on-second guard. This proves the local
synthetic quota path, not a real account's quota or remote retry guarantees.

One additional physical owner, ServerNotification's TurnStatus `failed` literal,
gains scoped implemented evidence from the exact turn/completed assertion.
Three systemError notification owners are withheld: this case checks runtime
status through thread/read, which cannot qualify a different physical producer.
The canonical usageLimited and complete goal literals were already implemented.

## Real create, rejection, completion and replacement tools

`native_goal_tool_profile.exs` gives one explicit user turn seven fixed model
responses. Stock built-in tools create A100, reject replacement while unfinished,
complete A, create B200, reject replacement while unfinished, then complete B.
The seventh response is a prescribed final assistant. There are no client goal
mutations, synthetic app-server frames or client tool responses.

Only the two rejected replacement responses carry nonzero usage. Independent
input/cached/output tuples7/3/5 and11/2/3 imply net9 for A and12 for B.
Creation responses carry zero usage, avoiding an eager tool-execution/accounting
race. Every replayed tool call/result, ordering, identity, budget, timestamp
window, remaining91/188 and nonnull exact completion report is asserted. B starts
from zero accounting. Native notifications and complete paginated history must
agree; confirmed cold restart/resume retains final complete12 and causes no
extra turn or eighth model request. Tool output structures are not new
app-server schema owners.

## Source and retained failures

Immutable source anchors relative to `codex-rs/`:

- `app-server/src/request_processors/thread_goal_processor.rs:179-207,280-324`:
  null status and origin handling, actual clear and explicit user provenance.
- `app-server/src/request_processors/thread_lifecycle.rs:972-1001`: a resume
  snapshot emits cleared for an absent goal; this is distinct from repeated
  mutation silence.
- `ext/goal/src/runtime.rs:412-434`: absent/paused/stopped runtime restoration.
- `ext/goal/src/tool.rs:212-257,447-553`: create/update rules, native structured
  results, remaining tokens and completion report.
- `app-server/src/bespoke_event_handling.rs:1034` and
  `app-server/src/thread_status.rs:174-181,448-468`: quota errors retain warm
  system-error status; history/goal stopping does not imply warm idle.

The first combined runner `goal-plugin-v1` failed three oracles: omitted the
legitimate resume-cleared snapshot, required nonreused namespace inode numbers,
and expected warm idle after quota failure. Pinned source and direct artifacts
support the corrected exact snapshots/status. The plugin oracle still requires
distinct native PID, disappearance and independently proven parent isolation;
Linux may reuse a namespace inode after its last owner exits. The v2 goal/plugin
block passed10/0 twice, then strict Credo failed goal-tool cleanup nesting.
Extracting unchanged exit checks repaired that static issue. No sleep, widened
deadline, skipped assertion, retry-until-green or native implementation change
was introduced.

## Executed qualification

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-goal-plugin-v5-20261024.py
```

The complete eight-file goal/plugin/approval owning block passes **25/0** at
seeds501432 and987654, in56.4/57.1s. Python AST, warning-free driver compile,
format, root strict Credo and executable-source guard pass. Logs, exact commands
and hashes remain under `/tmp/samgita-native-goal-plugin-v5-20261024/`:
`results.json` SHA256
`9181651eea0b92c86ca699104dfa7579a68f96c497997827b50344264ba61b91`;
source snapshot SHA256
`16ee18aff425c0bb4ccc262d280a3bce5ce90910477cd784bbe6e8222a5d7693`.

The origin test joins default discovery; goal quota uses the existing required
budget profile; the stock-tool profile gains a required explicit CI step.
Final-source aggregate and hosted checks remain separate. Active crash/accounting
reconciliation, remaining fields/transports/OS/backends, A11, unavailable legacy
emitters and complete compatibility remain incomplete. No fully verified
promotion, publication, production migration or deployment follows.
