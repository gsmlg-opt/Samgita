# Pinned notification error producer limitations

Seven canonical notification owners remain unaccepted because the selected
ordinary local app-server has no demonstrated production path for emitting
them. They change from missing to **blocked**, with no implemented/verified
promotion, new transport evidence or removed acceptance requirement. This is
source evidence for immutable `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`; it is not a fake-Agent test or a
claim about every possible external/historical input.

## Retained rollback error

Owner2053 is `ServerNotification.json#/definitions/CodexErrorInfo/anyOf/0/enum/12`,
the literal `threadRollbackFailed`.
[Upstream protocol.rs:1999](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/protocol.rs#L1999)
explicitly states: **“Retained to deserialize errors recorded in legacy rollouts.”**
The complete archive symbol inventory finds declarations, conversions, matches
and test constructors, with no current production constructor.

`affects_turn_status()` returns false for this variant at line 2008. Ordinary
app-server error notification delivery and legacy history projection filter
non-turn-affecting errors. Genuine historical records remain a separate
unverified profile; constructing a legacy record in a test would not establish
a current native producer.

## Dormant stream connection error

Owners2067–2069 are the `responseStreamConnectionFailed` object and its
`httpStatusCode` field. The mapping in
[protocol/error.rs:511](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/error.rs#L511)
requires `CodexErrorDetails::ResponseStreamFailed`. The complete pinned source
contains only one actual `CodexErr::ResponseStreamFailed` construction:
`protocol/src/error_tests.rs:282`. The runtime error types do not derive
Deserialize, so an arbitrary API response cannot instantiate this dormant
construction path.

Real API stream errors map to `CodexErr::Stream`
(`codex-api/src/api_bridge.rs:59–63`); transport failures map to
`ConnectionFailed` at267–269. Intermediate retry notifications explicitly use
`ResponseStreamDisconnected` (`core/src/session/mod.rs:5287–5295`). Disconnecting
a local Responses fixture therefore does not establish the selected variant.
No scripted app-server or fabricated SSE error is counted as native acceptance.

## RPC-only steering error

Owners2076–2078 describe `activeTurnNotSteerable` and its `turnKind` reference.
Actual Compact/Review steering is rejected in
`core/src/session/turn_input.rs:832–844`. The
[turn/steer processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/turn_processor.rs#L1121)
returns typed **JSON-RPC error.data**, through1183. It does not send an
ErrorNotification. `turn/start` instead returns a generic internal error with
the Debug reason at lines 693–700.

A controlled real compaction profile could qualify that RPC data path, with
code `-32600`, message `cannot steer a compact turn` and the prescribed compact
kind. That profile was not run here and cannot qualify this physical canonical
notification owner. `ActiveTurnNotSteerable` also returns false from
`affects_turn_status()`, so the normal notification path filters it.

## Complete path and historical-input boundary

The archive contains two app-server production
`ServerNotification::Error(ErrorNotification { ... })` send sites, both in
`app-server/src/bespoke_event_handling.rs`:

- At line 1068, `EventMsg::StreamError` uses the ordinary retry producer's
  distinct disconnected variant.
- At line 1633, terminal errors pass through the caller at1049, which filters
  non-turn-affecting errors at1039–1040. The caller at1823 supplies
  `codex_error_info:None` after path-localization failure.

Other symbol matches include consumers and client/test adapters; they do not
establish an app-server production sender. Historical deserialization also
does not supply ordinary behavior evidence: `thread/resume.history` accepts
`ResponseItem`, not ErrorEvent/RolloutItem; legacy history projection filters
both non-turn-affecting variants at
`app-server-protocol/src/protocol/thread_history.rs:1235–1238`; and
`thread_summary.rs:220–222` explicitly clears turns for thread-start
notifications. No rollout or database was edited to manufacture a path.

Accepting these owners still requires a real producer/profile with independent
evidence for the selected wire location. Authentic externally supplied
historical data, if available, needs separate provenance and native-path
qualification. A future upstream fix or different version requires a reviewed
pin update. These conditions do not remove the owners from the full goal.

## Evidence and unchanged verification

`/tmp/samgita-v304-functional-checks/source-evidence.json` verifies fifteen
complete archive-matching source files and seven exact physical schema nodes.
`producer-symbols.json` searches **5,259 Rust files directly from the immutable
archive**, retaining all matches for the four relevant symbol queries.
Declarations, pattern matches and test constructors are interpreted separately
from runtime construction/send sites. No test was executed by this source review.

| Evidence | SHA256 |
| --- | --- |
| Pinned files/nodes | `9f9138b3d9ae0331a3b8b6333833496fee48af5affcfce209e08d91821d2732e` |
| Complete archive symbol inventory | `22ff1e15b958ba11240a392a8c562d2f1cf116aeccffeade8c927f1d89ce2aa6` |
| Resulting manifest | `2bc189a4c603242c10333cef7acf738f3befa21ca57df52e3ec1bb92a15be9b9` |

Unique complete-record changes and final bindings verify only seven blocked
classifications. Schema hashes, planned tests, empty verified-test/transport
lists and all unrelated rows stay unchanged. All 279 guarded source hashes also
match the committed passing **41-file, 77/0 twice** v303 matrix, static checks,
outside consumer 1/0 and seventeen AST checks. That unchanged-code matrix is
reused; it is not rerun or claimed to exercise these dormant variants.

Inventory consistency passes. Strict completeness remains exit **1**:
**4,889 implemented / 1,666 missing / 66 blocked** contracts, unchanged
**462 implemented / 12 missing / 11 blocked** requirements, zero verified.
Prohibited security/permission checks, broad/hosted workflows, A11, unavailable
external/OS profiles, full-goal and release gates remain incomplete. No
publication, deployment or upstream modification occurs.
