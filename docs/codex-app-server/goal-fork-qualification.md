# Deferred goal inheritance and cold recovery

One actual-native journey adds scoped evidence for
`thread/fork.deferGoalContinuation` at immutable `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The real app-server owns state, events and goal scheduling. Only three bounded
Responses answers are synthetic; this is not live model/service acceptance.

## Native semantics and setup

Omitted/false does **not inherit** the source goal through this path. True is an
active experimental value and, with persistent history and goals enabled, copies
the goal and defers continuation until an explicit turn. Null is invalid; true
cannot combine with ephemeral. Immutable source anchors are
`app-server-protocol/src/protocol/v2/thread.rs:629-635`,
`app-server/src/request_processors/thread_processor.rs:5196-5201,5548-5574`,
`thread_fork_goal.rs:5-28` in the same directory, and
`state/src/runtime/goals.rs:64-121`. The official positive reference is
[thread_fork.rs:910-1155](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/tests/suite/v2/thread_fork.rs#L910-L1155).
It is source evidence; this repository does not claim to have run that test.

The profile materializes a source with one explicit fixed assistant turn, then
stops/reaps/restarts its owned native process. Public `thread/goal/set` creates
a user-origin active goal on that cold source, budget20/usage0, without loading
or another provider request. No database rows are seeded. The authorized API
appends user intent; complete source-history/rollout-byte baselines are captured
**after** that mutation. `thread_goal_processor.rs:184-242,323-393` and
`thread_goal_user_context.rs:10-52` explain the cold mutation/flush;
`ext/goal/src/api.rs:76-86` applies effects only to a registered runtime.

## Executed journey

Absent/false-negotiated clients test omitted and explicit-false forks: new
identity/path, source ancestry, exact copied history and no goal/inference.
Exact outbound maps preserve missing/false. True rejects locally without send
and natively with the exact gate. Null has separate local schema and native
deserialization errors. Enabled true+ephemeral rejects with the exact incompatible
error and no child, work or source mutation.

Enabled persistent true copies the exact source goal, changing only its thread
ID. Full source history, goal and every rollout byte stay unchanged. Confirmed
native restart, cold reads and explicit resume preserve the deferred child
without inference. An explicit child turn consumes net9; a distinct automatic
goal turn consumes net12, ending budgetLimited21/20. The third HTTP response is
held at an observable provider barrier until native explicit completion and the
active9 notification/read are checked. Release permits only that HTTP response,
never a fabricated app-server event.

The automatic request contains the exact objective, continuation heading,
used9/budget20/remaining11 and ordered source/explicit history. Raw request/SSE
bytes and hashes, native thread/turn/trigger metadata, message IDs/text, native
completion/goal notifications, cached-token accounting and exactly three attempts
are asserted. Final cold restart/resume preserves budgetLimited and all three
turns without more inference. No tool/approval/command, realtime traffic or auth
is authorized. The private namespace has loopback only, no default route and no
external credentials. Retained fixture ownership/reaping and immutable config/
catalog guards remain; cleanup waits for every owned PID before its journal check.

Deferral/accounting anchors are `ext/goal/src/runtime.rs:438-456,485-508`,
`extension.rs:178-202,234-270`, `accounting.rs:570-575` in that directory, and
`ext/goal/templates/goals/continuation.md:1-17`.

## Qualification and limits

In verified Devenv, `MIX_ENV=test`, from the independent driver directory:

```sh
mix compile --warnings-as-errors
mix test test/native_goal_fork_profile.exs test/native_goal_budget_profile.exs test/native_goal_tool_profile.exs test/native_goal_origin_test.exs test/native_goal_test.exs --warnings-as-errors --seed 501432
mix test test/native_goal_fork_profile.exs test/native_goal_budget_profile.exs test/native_goal_tool_profile.exs test/native_goal_origin_test.exs test/native_goal_test.exs --warnings-as-errors --seed 987654
```

The complete owning block passes **10/0 twice**, 40.5/40.4 seconds. Python AST,
formatting, warning-free compile/tests, root strict Credo (430 files) and matching
before/after executable-source snapshots pass. Exact commands/logs remain under
`/tmp/samgita-native-goal-fork-v2-20261025/`; results SHA256
`2d141d270030beb24cd9d57beb99ec92e54918361333f6532a682a42d70cb68a`,
source SHA256 `c2ed7337eab303baf7f581e93eeb802120d827d212c22fdbff860538c1fa10c7`.

v1 passed both native blocks, then strict Credo failed on cleanup nesting.
Extraction of the identical per-PID await preserves the PID list, deadline and
close/reap/journal order; no suppression or assertion change occurs. v1
results/source hashes are
`c6113750eac7f52efd3a8590d6bea1a663f071ccaee20e6671bb5b988734b0c0` /
`82faf32bf016a10a4271590cb398184890176b5a0420dbfc7261eecd8c822cb3`.
That runner stopped before its final source guard; only v2 claims guard success.

One physical property gains scoped implemented evidence, zero verified. This
enabled success is the 46th explicitly required hosted native profile. Positive
source elapsed time, other goal states, disabled goals/no-goal sources,
concurrent active-source flush and other transport/OS/service profiles remain
unqualified. No Samgita decision engine, Task acceptance,
exactly-once guarantee, full compatibility, A11 closure, publication or deployment
follows. Complete final-source local/hosted checks remain required.

## Current goal snapshot with historical prefixes

The real budgetLimited child at21/20 now supplies three additional true forks:
`lastTurnId` selects two turns, `beforeTurnId` selects one, and cutting before
the original source turn selects zero. Each child copies the exact **current**
goal snapshot, changing only thread ID, even when its selected history predates
that usage. Original goal, full history and every rollout byte remain unchanged.
No fourth provider request is permitted.

The existing final owned restart cold-reads all three goals/histories/identities
without loading a runtime, then explicitly resumes the zero-turn stopped child.
Its budgetLimited goal remains exact and it does not execute. Original target
resume, no-work observations, source invariants and all cleanup checks remain.
Pinned `thread_fork_goal.rs:5-28` copies the current snapshot independently of
history cutoffs; `thread_processor.rs:5548-5574` controls persistence/deferral.
This is nonzero **token** inheritance and prefix/cold-empty-child evidence;
there is no positive elapsed-time claim or direct state-store seeding.

The full 15-file owning block passes **91/0** at each fixed seed, with compile,
format, root strict Credo and a matching executable-source guard. Exact commands
and logs are `/tmp/samgita-native-repair-continuation-v2-20261025/`. The existing
physical deferral owner gains stronger evidence and no inventory-count change.
Remaining status/default/config/active-flush/deployment profiles and complete
final-source local/hosted qualification remain open.

## Source absence, per-fork config and stopped goal states

Two further differentials use the same native process restarts and exactly
three provider requests. Before public goal setup, true-forking the materialized
source preserves exact source/child history, distinct identity/path and nil goal.
The existing first restart confirms the child stays nil and cold. After the
source's active goal exists, the exact per-fork override
`config:{"features.goals":false}` produces a persistent child with copied
history and no goal; the adjacent unmodified true fork is the positive control
that still inherits the source goal. Existing second restart cold-reads both.
Global server goals stay enabled; this is not a global-disabled API claim.

`thread_processor.rs:5275-5295,5394-5402,5548-5574` passes dotted request config
and checks effective goals before copying. `thread_fork_goal.rs:5-28` returns
false when no source goal exists. Public goal reads are cold store reads
(`thread_goal_processor.rs:254-272`) and do not load/execute the thread.

After all original prefix/cold/empty-child/target checks, the first still-cold
prefix child is changed only through public user-origin status commands:
complete, paused, blocked, usageLimited. Every returned snapshot retains21
tokens/budget20, original goal identity/times/objective except status/update
time, and is captured after the authorized history append. Four true forks
copy those exact current snapshots and canonical histories; the cold source's
goal, history and rollout bytes then remain unchanged. Original source and
target remain unchanged, with exactly three provider requests and the original
final no-work observation/cleanup. This is public stopped-state setup, not proof
of a naturally occurring backend quota event. New stopped children are not
cold-restarted in this extension.

The initial complete is necessary: `state/src/runtime/goals.rs:290-360` keeps
paused/blocked requests sticky when the previous status is budgetLimited.
`ext/goal/src/api.rs:215-288` preserves usage on status-only edits;
`thread_goal_user_context.rs:10-60` persists legitimate user intent before the
post-command history snapshot. No SQLite rows, runtime state or events are
seeded. The existing source/target baseline is never redefined to hide changes.

The full sixteen-file native owning block passes **92/0 twice**, fixed seeds
501432/987654, with compile, format, strict Credo and unchanged executable-source
guard. Commands/logs are `/tmp/samgita-native-repair-continuation-v3-20261025/`.
This strengthens the existing deferral owner without a count or verified-state
promotion. Positive elapsed-time control, active-source concurrent flush, newly
stopped-child cold recovery and other deployment profiles remain unqualified.
