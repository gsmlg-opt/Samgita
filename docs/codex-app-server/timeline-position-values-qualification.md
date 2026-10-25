# Ordinary timeline canonical positions

This unit targets three exact position fields on immutable Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
It uses an owned home and the actual app-server with an assistant-only Responses
fixture. That fixture supplies model text, not app-server timeline responses.
No Samgita platform or database is required.

## Independent position oracle

The retained timeline test checks monotonic positions, ordinary item/turn
identity, pagination and cold readback. Monotonicity cannot establish that a
position is the canonical durable ordinal: renumbered rows could also pass.

The focused case completes two prescribed ordinary turns in one durable
paginated thread. Before its first timeline request it snapshots the genuine
rollout returned by public thread/read, bounded to one MiB and 2048 records.
Its expected eight facts come from explicit native record ordinals, correlated
by the actual turn/item IDs and prescribed user/assistant text. File line
numbers and returned positions are not oracle inputs.

| Physical contract | Expected production meaning |
| --- | --- |
| 6418, item position | The corresponding completed user/assistant item's original durable ordinal |
| 6428, turnStarted position | That turn's durable task_started ordinal |
| 6439, turnCompleted position | That turn's terminal task_complete ordinal |

The source chain starts at the
[timeline handler](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L916).
[Materialization](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/thread_history_materialization.rs#L182)
retains each raw explicit ordinal; the
[history projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/thread_history_projection.rs#L21)
maps real item/turn records, and the
[timeline reader](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/thread_history/realtime.rs#L102)
returns original item/start ordinals and terminal end ordinals. Other persisted
records consume ordinals, so the test does not require contiguous numbering.
Eight complete production files match the immutable archive; the experimental
export provenance and each of the three separate schema-node hashes match.
Source evidence and the bounded plan are in
`/tmp/samgita-v235-next-functional-candidate/`.

Limit-one pages retain native opaque cursors unchanged. Bounded continuation
must return every prescribed fact exactly once, and a saved midstream cursor
must retain its meaning across checked owned-process shutdown and cold startup.
The cold reader neither resumes nor dispatches work. Configuration, model
catalog, whole provider journal and raw rollout bytes remain unchanged.

## Qualification boundary

The focused real-native case passes **1/0**, seed 501432, in **2.0** test
seconds; log `/tmp/samgita-v235-timeline-first.log`. The first combined v237
attempt completes format/compile but stops at strict Credo: the new capture
function has nesting depth three. Its four completed commands and four unrun
commands remain recorded in `/tmp/samgita-v237-functional-checks/functional/`.
Extracting the identical bounded send/capture body into private capture/3 fixes
the lint failure without changing assertions, cleanup, limits or deadlines.
The independent source review in `/tmp/samgita-v238-timeline-review/` finds no
actionable functional defect in the corrected source.

The corrected final block is the twenty-two reviewed functional files in
[fork/resume qualification](fork-resume-effort-values-qualification.md#exact-owners-and-checks)
plus `test/native_timeline_position_values_test.exs`. All **38 tests pass at
both seeds 501432 and 987654**, with warnings treated as errors, in
**68.799/68.381** command seconds. Scoped format, warning-free compile, strict
Credo on **475 files**, the outside-umbrella actual-binary consumer **1/0**,
two Python fixture syntax checks and the **248-file** unchanged-source guard
pass. All eight commands complete. No previous test is removed or weakened;
runtime libraries, shared helpers and prior process cleanup are unchanged.

Exact commands/logs/source: `/tmp/samgita-v239-functional-checks/functional/`.
Results/source SHA256:
`d8cd59405be892aac3f47cfb8653766fc2fdc106216158496baa9908e75d4314` /
`b5d30321df1c419437c13bf687b8266262690882ee7f3cefff745bb9af601e25`.
The adjacent `manifest-binding-timeline.json` binds the three original/current
rows to test SHA256
`c190c2c2046d511d642a34f50081b2df4157673e9d06dbcd4f9a0d802108697d`.
Sixteen unchanged captured turn/timeline request envelopes match genuine
response IDs. Capture is bounded to 32 frames/4096 bytes; turn collection to
256 events/one MiB, with explicit gap failure. Requests/init retain 5s bounds
and turns 20s. Yolo launch is fixed owned setup only, without policy assertions.

Only physical contracts **6418/6428/6439** receive scoped implemented evidence.
Inventory `--check` passes; all requirement records and schema identities/hashes
remain unchanged. Contracts become **4,702 implemented / 1,860 missing /
59 blocked**; requirements stay **462 implemented / 12 missing / 11 blocked**,
zero verified in both. Passing these three position readers is not completion
of the history family or the full compatibility goal.

Only ordinary completed paginated history on the pinned Linux stdio profile is
in scope. Realtime entries, inherited fork lineage, interrupted/failed turns,
other history modes, selective inProgress projections, other OS/transports and
real provider/platform acceptance remain unqualified. No aliases, enclosing
union, whole response or method inherits evidence from these three fields.
Security/permission tests, related audits and broad/hosted workflows remain
unrun under the user's restriction. A11, legacy-unreachable emitters, complete
compatibility and release remain incomplete. No publication or deployment occurs.
