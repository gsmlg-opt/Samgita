# Native thread snapshots and diagnostic values

This unit extends two existing ordinary functional cases on immutable Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The real app-server produces every protocol response and notification. Owned
synthetic providers supply assistant text only. Neither Samgita nor a database
service is started. The base repository commit is `41097dd`.

## Independent observations

| Physical owner | Actual producer and independent oracle |
| --- | --- |
| 2472/2473, canonical ServerNotification ThreadEnvironment.cwd/environmentId | Each of three genuine thread/started notices is correlated by its actual generated thread ID, then must contain exactly one environment with the owned process workspace and literal local ID. Requests still omit cwd, preserving the ordinary process-cwd fallback. |
| 6151, ThreadSearchResponse Thread.reasoningEffort/anyOf/0 | Both loaded threads must return literal low in each of four searches. The root config prescribes low before startup; the expected value is never copied from another response. This selects only the nonnull effort branch. |
| 5069/5070, ServerDiagnosticsResponse ServerDiagnosticsGauge.name/value | The existing final diagnostics call must contain exactly one core.threads.live gauge with literal value 2. The journey created and retains exactly two native threads, with no child/tool thread or unload. |
| 5072, ServerDiagnosticsResponse ServerDiagnosticsProcess.physicalFootprintBytes | The Linux-initialized native process must return this property explicitly present as null. The immutable Linux producer returns None, and its public serializer does not omit the property. |

The notification processor builds the started thread from its real snapshot,
projects selected environments and sends that same thread in thread/started;
its notification helper clears only turns. See the pinned
[start path](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L1573)
and [environment conversion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/environment.rs#L14).
The concrete notification's reference chain reaches the two selected canonical
children; same-shaped method responses are not their evidence.

Search constructs stored rows, then
[enriches loaded hits](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L2861)
from the actual current configuration snapshot. The
[projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors.rs#L625)
assigns snapshot effort directly. ThreadManager retains both native threads;
each CodexThread registers a lifetime gauge. The
[diagnostic snapshot](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/diagnostics/src/lib.rs#L89)
copies actual names/counts, and its Linux process branch explicitly supplies
no physical-footprint measurement.

All 14 complete inspected production files match the immutable source archive;
all six exact property/variant-node digests and corresponding experimental
exports match inventory/provenance. Evidence is in
`/tmp/samgita-v263-functional-checks/source-evidence.json`, SHA256
`6b5d05278034d1ec797617b650a1a37437ce0361e52d16a37da45810b0f0e0bc`.

## Checks on final source

The final block uses the same twenty-five reviewed functional files as
[the config unit](thread-start-config-values-qualification.md#qualification-boundary).
Both commands use mix test with that explicit file list, warnings as errors,
and seeds 501432 and 987654. Each passes **40 tests / 0 failures**, in
**74.758/73.622** command seconds. Scoped format, warning-free compile, root
strict Credo on 477 files, the outside-umbrella actual-binary consumer **1/0**,
three Python AST checks and the **251-file** unchanged-source guard pass.

Exact commands, environment, logs and final source hashes are in
`/tmp/samgita-v263-functional-checks/functional/`. Results/source SHA256:
`0492a71c59af8d6e6980e31b0c31c0c2b7d9d7aac1c95b0f12c2636932f08c43` /
`b3c47e733c823cfa86e775eca687212394bc237b8cac11e5c0cae918d9caf424`.
Test SHA256 values:

- native_thread_start_config_values_test.exs: `967e185380203b9bf2c6e6088047188b21447991c9a10dc3ad40db8ea2d98c4f`.
- native_search_git_info_values_test.exs: `204601a23fba6a90a1f9fbc664949a2b215406c2978111a6ef2dedf23780dc57`.

The earlier v259/v261 functional blocks also pass 40/0 at both seeds; they
precede the final search diagnostic assertions and are not final-source
substitutes. There is no failing runtime result in this unit. Independent
source review finds no actionable issue. Search now uses fixed never/full-access
CLI setup, matching the requested yolo mode without policy assertions. All
original protocol requests, model calls, metadata/content/history/provider
journal checks, bounds, deadlines and confirmed owned-process cleanup remain.
No runtime library, shared helper, dependency or application configuration changes.

## Evidence limits

Only these six exact rows gain scoped implemented evidence. Inventory --check
passes; all 485 requirement records and schema identities/hashes are preserved.
Contracts become **4,715 implemented / 1,847 missing / 59 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**, with zero
verified in both inventories. The adjacent manifest-binding.json records the
six original/current rows and binds them to the final source and test hashes.

No enclosing object/array, alias, whole method, other notification, effort enum
exhaustiveness, unloaded/remote environment, other gauge/count/lifetime,
nonnull physical footprint, resident-memory accounting or other OS/transport/
backend inherits this evidence. Security/permission tests, related audits and
broad/hosted workflows remain unrun under the user's restriction. Full
compatibility, A11, upstream-unreachable legacy emission, external/platform
acceptance and release remain incomplete. No publication, production migration
or deployment occurs.
