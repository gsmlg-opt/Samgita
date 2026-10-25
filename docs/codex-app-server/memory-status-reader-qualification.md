# Native memory status reader with synthetic saved inputs

This unit exercises the real status reader of immutable Codex `rust-v0.163.0`,
source `83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Its persisted count and summary are explicitly synthetic reader inputs.
**It does not demonstrate actual memory generation or consolidation.**
No Samgita platform, Repo or running database service is required.

## Controlled input and genuine output

The first public memory/status request creates and migrates the native V2
SQLite store and returns its original zero/false state. Only after that owned
native process has stopped does the input helper open the existing migrated
database. It cannot create a replacement database or schema. Each of its three
fixed transactions changes the singleton count through **0→2→19→20**, requiring
the exact previous count and one affected row. A distinct read-only connection
observes every committed input. A literal synthetic summary is prepared while
the server is stopped; its exact bytes/hash are subsequently preserved.

All thirteen status responses come from six distinct hash-checked native
processes. The helper emits input observations, never protocol frames or
expected responses. The model-provider journal remains empty and byte-identical;
no turn, loaded thread, production consolidation job or inference is created.

| Independently prepared input | Request | Expected native count/readiness |
| --- | --- | --- |
| Original migrated store; summary absent | Omitted threshold | 0 / false |
| Count 2; summary absent | Threshold 2 | 2 / false |
| Count 2; literal valid summary | Threshold 1 or 2 | 2 / true |
| Same count and summary | Threshold 3, 4096, omitted or null | 2 / false |
| Same count/summary after checked cold restart | Threshold 2 | 2 / true |
| Count 19; same summary | Omitted and null | 19 / false |
| Count 20; same summary | Omitted and null | 20 / true |

The 19/20 boundary independently distinguishes the actual default 20 from
other possible defaults; count 2 alone would not. This refinement was made
before execution. Fixed requests retain absent versus explicit null on the
encoded wire, unique IDs and matching real response IDs. Capture is bounded
to 16 frames/4096 bytes. Request, initialization and input-helper deadlines
remain 5s; helper output is bounded to 4096 bytes. Captured-connection cleanup
and checked native PID disappearance preserve the earlier shutdown repairs.
Yolo launch is fixed owned setup, without policy assertions.

## Immutable source and ownership

The pinned
[status processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/memory_status.rs#L13)
defaults the optional threshold to 20, reads the actual V2 progress count and
requires both a sufficient count and a valid summary. The
[summary validator](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/memories/write/src/workspace.rs#L118)
defines its literal format. The immutable upstream memory-status test also
uses prepared store inputs and a literal summary. Twelve production files and
that test match the source archive; two exports match pinned provenance and
all three exact owner-node hashes match inventory. Evidence and drafts are in
`/tmp/samgita-v236-next-functional-candidate/` and
`/tmp/samgita-v240-memory-status-implementation/`.

The public protocol has no synchronous consolidation-success operation.
Actual stage1 extraction, phase2 Agent/artifact completion, the production
progress transaction and later memory-context selection require separate
production-path qualification. Seeding a reader checkpoint proves none of them.
Only physical fields **4411**, MemoryStatusParams.minConsolidatedThreads,
**4412**, MemoryStatusResponse.v2ConsolidatedThreads, and **4413**,
MemoryStatusResponse.v2Ready, are candidates for scoped implemented evidence.
No reset, generation, writer, context, alias or whole subsystem inherits it.

## Checks and limits

The independent source review catches an omitted required helper launch
environment before execution. Supplying the owned HOME/CODEX_HOME/TMPDIR and
workspace fixes the draft launch; no runtime control or test gate changes.
The corrected focused real-native run passes **1/0**, seed 501432, in **4.1**
test seconds; log `/tmp/samgita-v240-memory-first.log`. Review evidence is in
`/tmp/samgita-v243-memory-status-review/`.

The final block is the twenty-three reviewed files in
[timeline qualification](timeline-position-values-qualification.md#qualification-boundary)
plus `test/native_memory_status_values_test.exs`. All **39 tests pass at both
seeds 501432 and 987654**, with warnings treated as errors, in
**73.617/72.643** command seconds. Scoped format, warning-free compile, strict
Credo on **476 files**, outside-umbrella actual-binary consumer **1/0**, three
Python fixture AST checks and the **250-file** unchanged-source guard pass.
All eight commands complete without a runtime failure or changed deadline.
Runtime libraries, shared helpers and earlier shutdown repairs are unchanged.

Exact commands/logs/source: `/tmp/samgita-v244-functional-checks/functional/`.
Results/source SHA256:
`dc41d1b8627da1c6ac1ed54402fbcebfe90ccaf944b7bb1ed77587f56cb0a573` /
`d8942f21974e74a516b08d2ecf731c306263f2c6ed240a0bc39319b765e0bfc6`.
The adjacent `manifest-binding-memory.json` binds the three original/current
records to test SHA256
`2dadec2ba749a3bc657abefcf2754110bf77d32484343ef751945e21fda0c8df`
and input-fixture SHA256
`1e249e2d277849077224d93549238cd63433894fb6af9819d4335589878460a9`.

Only fields **4411/4412/4413** receive scoped implemented evidence with the
explicit `synthetic_persisted_input_reader_only` limitation. Inventory `--check`
passes. All requirement records and schema identities/hashes are unchanged.
Contracts become **4,706 implemented / 1,856 missing / 59 blocked**;
requirements stay **462 implemented / 12 missing / 11 blocked**, zero verified
in both. No response or synthetic checkpoint is counted as production writer
success or complete compatibility.

Invalid-summary forms, out-of-range thresholds, generation/consolidation/writer
success, context use, other memory modes, OS/transports/backends and external
platform success remain unqualified. Security/permission tests, related audits
and broad/hosted workflows remain unrun under the user's restriction. A11,
source-unreachable legacy paths, complete compatibility and release remain
incomplete. No publication, production migration or deployment occurs.
