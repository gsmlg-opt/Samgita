# Selected native envelope owners

This is an evidence-indexing change for unchanged actual-native assertions.
It adds no transport or runtime behavior. The exact frozen `5cd40c9` driver
suite passed **621/0** at seeds `501432` and `987654`; commands and source guards
are in `/tmp/samgita-repair-final-packages-v10-20261024/`.

Eighteen physical ClientRequest contracts index method, its exact enum value
and the selected params wrapper for fs/createDirectory, fs/getMetadata,
fs/readDirectory, fs/watch, fs/unwatch and synthetic API-key account/login/start.
Each test supplies the complete native request directly through Session and
checks independent effects: known files/types/tree contents, selected watch
delivery/release, or exact auth-file mode/content and cold account state.
Whole-request alternatives remain withheld.

Twenty-six physical ServerNotification contracts index selected method/enum/
params wrappers for fs/changed, process/outputDelta, process/exited,
thread/status/changed, turn/started, turn/completed, item/started and
item/completed, plus stdout/stderr literals. Owned writes/exit codes, prescribed
Unicode fragments and explicit lifecycle ordering supply independent oracles.
Session retains the full native wire; the model fixture supplies content, not
notification envelopes.

Only fs/changed has full top-level-key and exact params equality. The other
wrappers assert selected fields/order and independent effects; they do not
qualify their entire payload or referenced union. Chunk interleaving, arbitrary
clocks, all item/state alternatives, absent/null/default branches and whole
notification alternatives remain withheld.

Exact physical schema pointers/node hashes and unchanged test-file hashes were
rechecked before indexing; the manifest retains per-owner assertion ranges and
limits. Related evidence is in [filesystem](filesystem-qualification.md),
[process](process-qualification.md), [account](account-qualification.md) and
[thread lifecycle](thread-event-lifecycle-qualification.md). Matching a primitive
hash is never sufficient to promote a sibling owner. No requirement becomes
verified, and this audit cannot establish external account, OS, A11 or full
compatibility acceptance.

## Thirty selected request owners at 96f7130

A later source-only index adds thirty physical `ClientRequest.json` owners from
unchanged actual-native tests. Both complete local default-driver runs pass
**665/0**, seeds501432 and987654, in
`/tmp/samgita-repair-final-packages-v16-20261024/`; the same source's
[hosted checkpoint](repair-qualification.md#hosted-checkpoint-at-96f7130) passes
**366/0 + 299/0**. No new test, transport or runtime behavior is introduced by
this index. Neither passing default suites nor indexing wrappers qualifies all
referenced fields or changes a complete requirement to verified.

For the first seven rows, each `/oneOf/N` gains its selected envelope plus
`properties/method`, `properties/method/enum/0` and `properties/params` owners.
The final two rows gain only their selected envelope; their method/params
owners already have evidence. Request-ID owners remain withheld.

| Wire operation and N | Independent native oracle in unchanged tests |
| --- | --- |
| `thread/goal/set`,17 | `native_goal_test.exs`: prescribed normalized paused objective/budget, invalid-mutation retention and user-only provenance in captured model input |
| `thread/goal/get`,18 | Same tests: absent, persisted edited and cold unread-thread goal state; no automatic execution |
| `mcpServer/resource/read`,133 | `mcp_direct_test.exs`: exact synthetic URI, content, peer input and native thread association |
| `mcpServer/tool/call`,136 | Same tests: prescribed Unicode arguments/results, overwritten untrusted thread metadata and independent peer invocation count |
| `thread/fork`,9 | `native_thread_fork_settings_test.exs`: distinct child identity, prescribed settings and empty history, unchanged parent and zero inference |
| `thread/increment_elicitation`,13 | `native_thread_control_queries_test.exs`: exact in-progress/waiting state while a separately controlled real turn is gated |
| `thread/decrement_elicitation`,14 | Same tests: preserved live turn and removal of waiting state after balanced counter changes |
| `thread/start`,7 | `native_thread_event_lifecycle_test.exs`: named, persisted, independently identified thread, event association and no turn |
| `thread/resume`,8 | `native_thread_resume_settings_test.exs`: exact cold thread, explicit effective settings and no new inference |

The physical schema and inventory hashes, all test/fixture hashes, exact JSON
pointers and canonical subtree hashes were rechecked against the proposal
`/tmp/samgita-clientrequest-existing-native-owner-proposal-20261024.json`, SHA256
`e3a9efe5487bf37313a14cbff91b7fcbc63cae7c563fa8dbb3531a7dae150af4`.
The manifest stores per-owner test anchors and limits. Canonical standalone
definitions are not duplicate bundle owners; no row is manufactured for them.
The original hosted manifest has3141 implemented contracts; this later index
does not retroactively change its counts.

Only the named Linux stdio profiles gain scoped implemented evidence. Direct
MCP uses a synthetic peer, and goal provenance uses a synthetic provider; the
app-server frames come from the immutable executable. Shared ID variants,
hosted resource targets, all goal origins/status combinations, other settings,
nonempty fork history, all response aliases and full-method behavior remain
unqualified by these wrapper assertions. No legacy emitter, external account,
other OS, A11, publication or full compatibility acceptance is established.
