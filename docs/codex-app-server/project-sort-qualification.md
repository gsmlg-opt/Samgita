# Native project sort semantics

Two functional cases exercise real `project/list` behavior against the immutable
`rust-v0.163.0` [pin](design.md), source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
No production driver defect was established: this closes a behavior-evidence gap
in the retained project tests, whose other scenarios remain unchanged and unrun.

## Contract and independent oracles

The pinned [processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/projects.rs#L69-L112)
defaults to position ascending, or recency descending when that key is selected.
An explicit direction requires a key. The
[store ordering and cursor code](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/state/src/runtime/projects.rs#L434-L569)
orders UUID ties in the selected direction, keeps absent recency last for both
directions, and binds cursor key/direction. Position ascending retains its legacy
two-part cursor; other modes encode `v1|key|direction|value|id`.

The first case creates four native projects and moves the last before the first.
Every omitted/null/default/explicit position combination must produce that known
order or its reverse. Independent `project/read` snapshots prescribe exact full
objects and position cursors. Full lists and every one-item page must match.
Direction without a key has the exact structured native error; cursors reused
under a different key or direction reject explicitly.

The second case interleaves two empty projects and two with genuine native
completed member turns. An owned loopback Responses dependency supplies only
model output. Completed notices and exact stored history are observed; a read
is not claimed to flush history. A read-only/query-only connection to the owned
Codex fixture SQLite supplies its millisecond timestamps, never writes them.
A bounded clock observation precedes the second turn; the native timestamps
must be strictly increasing. Those independently observed times and UUIDs
prescribe both recency orders, null-last ties and exact cursor values. Both
orders must differ from position order. The provider receives exactly two calls.

Both cases repeat their complete sort/page/error matrix after closing the owned
native process, confirming its PID disappears, and observing a different native
PID. Projects, timestamps, history and provider count survive. Bounded capture
checks actual outgoing maps, including omission/null; the retained call helper
checks response correlation. No helper, production source, deadline or old
assertion changes. No security or permission-related test runs.

## Integrated evidence and limits

From `apps/samgita_codex_driver`, the final three-file functional block is:

```sh
mix test test/native_turn_personality_test.exs test/native_turn_plugin_list_test.exs test/native_project_sort_matrix_test.exs --warnings-as-errors --seed 501432
mix test test/native_turn_personality_test.exs test/native_turn_plugin_list_test.exs test/native_project_sort_matrix_test.exs --warnings-as-errors --seed 987654
```

Both runs pass **9/0**, in 16.044/15.989 command seconds, with warning-free compile,
format checks, root strict Credo and a matching 226-file source guard. Evidence:
`/tmp/samgita-v153-project-sort-checks/functional/`; results/source SHA256
`f92daad71f2bafc162eb13a5fb662dec5f3fd5e822ec7ad0c6c9d95c39509f1a` /
`7f53f5a31d590f08639f476612591b291f2c4f187d2d1c5f030f15c629957c19`.
The source-map in v150 binds four upstream files to the pinned archive;
the v152 independent source-only review finds no blocking issue and records
the corrected history-read description. No runtime failure occurred in this unit.

Exactly nine direct `ProjectListParams` owners become implemented: indices
4961–4964, 4967–4969 and 4971–4972. They cover the two key enums, both direction
enums, nullable direction property/branches and the key branches. No response,
alias, previously implemented cursor owner or requirement inherits evidence.
Contracts become **4,550 implemented / 2,012 missing / 59 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.

This qualifies selected Linux/stdio native behavior with owned local storage
and synthetic dependencies. Broader lifecycle, other stores/transports/platforms,
real external services, A11, full compatibility, publication and deployed
behavior remain incomplete. Current user restrictions leave broad suites and
hosted workflows containing security/permission tests unrun.
