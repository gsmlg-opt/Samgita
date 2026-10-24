# Native automatic goal continuation and computed budget stop

One user-origin goal with budget20 causes stock Codex to start two goal turns,
execute its built-in get_goal, count noncached tokens and persist budgetLimited21.
There is no client turn/start, client tool response, interrupt, budgetLimited
mutation or synthetic app-server frame. Target `rust-v0.163.0` remains source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Samgita gains no internal reasoning or continuation engine from this test.

The private loopback-only Responses peer prescribes exactly three dependency
responses and counts every HTTP attempt before dispatch. A fourth request,
wrong method/path/model/thread/phase or unexpected tool traffic fails and stops
only its owned native/controller. It cannot supply endless answers. Provider
retries, shell execution, plugins, hooks, remote discovery and analytics are
disabled; credentials are absent. Raw request/reply bytes, digests and actual
native thread/turn/goal-trigger metadata are retained and independently checked.

| Native activity | Fixed model dependency | Independently expected accounting |
| --- | --- | --- |
| First automatically started turn | Known assistant ID/text; input7, cached3, output5 | Net9, active, original objective/budget retained |
| Second automatically started turn | Stock no-argument get_goal, zero usage | Actual native result has active9, remaining11, completionBudgetReport null |
| Same second turn continuation | Second known assistant ID/text; input11, cached2, output3 | Adds12; native computes budgetLimited21 at budget20 |

Wire total26 minus cache5 gives21. The first real provider reply waits a measured
1.25seconds within its existing bound, giving native monotonic whole-second
accounting a positive duration. Every goal map has an exact key set, typed
integers, known identity/objective/status/budget/usage and creation/update/elapsed
bounds. Actual update notifications independently satisfy those oracles and
correlate initial null turnId, then the two native turn IDs. Exact supplied
assistant IDs/text and complete completed-turn history remain asserted.

After budget stop and both completed turns, a bounded quiet observation keeps
the fail-on-fourth guard armed. Owned cold restart must retain the whole goal
and full history before loading. Explicit resume must retain the stopped state
and cause no further inference or turns. All owned processes are reaped and the
physical workspace remains empty. This proves stopped-state retention, not a
crash while active or exactly-once accounting through an ambiguous failure.

## Source review and retained first failure

Pinned `ext/goal/src/runtime.rs:225–244,436–502` admits active idle goal work;
`ext/goal/src/extension.rs:315–375,449–478` accounts cumulative native usage;
`ext/goal/src/accounting.rs:550–576,635–674` subtracts cached input and measures
elapsed whole seconds. `state/src/runtime/goals.rs:499–605` atomically computes
the durable budget stop. `ext/goal/src/tool.rs:447–501` defines the full
camelCase result and Unix-second goal timestamps.

Source review corrected three unexecuted-draft assumptions: captured execution
must reject interactions/errors as well as later quiet drains; elapsed time
starts before provider arrival; and `core/src/client.rs:1092–1100,1857` removes
unprefixed message IDs from subsequent provider input. The test still checks
exact public/history IDs; provider replay separately requires the sole known
assistant role/content, absent ID and prescribed ordering. No fallback value,
extra inference, widened deadline or weakened count/history oracle is added.

The first executed runner
`/tmp/samgita-native-goal-budget-v1-20261024/` stops at strict Credo before native
runtime: new assert_goal complexity10 exceeds9. Extracting the unchanged typed
clock assertions into assert_goal_clock fixes that static issue. The retained
failure is not native success evidence.

## Executed evidence and owner limits

`devenv shell --no-tui -- python3 -B
/tmp/samgita-native-goal-budget-v2-20261024.py` passes Python AST, warning-free
compile, format, root strict Credo and **1/0** at each seed501432/987654, with a
matching executable-source guard. Roots:
`/tmp/samgita-gb-XCitWZoiNa6Q`, `/tmp/samgita-gb-GPbSqy-D9AJn`.
`results.json` SHA256:
`9343473b5fe36d27cfa6035c86ee4a2dc6ea440e319187a785cf74823f358b9b`;
source snapshot SHA256:
`e15c7bf7164a0d5e07c1ddc7e19a64ac8a015869aa51e7355961d500527e32ea`.
CI explicitly runs the new owning profile; final-source hosted/aggregate checks
remain separate gates.

Exactly15 independently rehashed physical owners become scoped implemented:
ClientRequest active status literal; ServerNotification ThreadGoal.updatedAt;
ThreadGoalGetParams.threadId; GetResponse.goal and both branches;
SetParams objective/status/nonnull status/threadId/tokenBudget;
SetResponse.goal; and UpdatedNotification goal/threadId/turnId. The manifest
contains each exact owner pointer/hash. Existing seven goal fields gain stronger
nonzero/computed coverage without new state promotion. No sibling aliases,
origin branches, usageLimited, native create/update/complete tool success,
non-null completion report, active crash/replay, quota service, other OS or
transport is inferred. This accepts no Samgita Task. A11, legacy emitters,
external profiles and complete compatibility remain incomplete; no fully
verified promotion, release, publication or deployment.
