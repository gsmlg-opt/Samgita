# Native selected local-memory migration

The ordinary `native_local_memory_migration_test.exs` drives two owned stock
Codex processes with isolated home/config/workspace roots. Two external source
projects contain inert Markdown and independent JSONL cwd evidence. Native
detection must return both project keys; the actual detected item is narrowed
only to project A in `details.memory`. Exact original request/response frames,
native progress/completion and public/durable import history are required.

Only A's `MEMORY.md`, nested topic and exact compact `scope.json` appear under
`memories/extensions/external_agent_import/resources/project-a`. The extension
instructions must match the pinned 3,163-byte literal digest. B stays at its
source and remains detectable. Explicitly reimporting A creates a distinct import
ID/history and advances the existing single pending consolidation row; it is
not a deduplicated no-op. A distinct cold native process preserves both histories,
the exact queue snapshot/files and B's remaining detection. Source/config bytes
and the workspace remain unchanged throughout.

This enables only `external_agent_memory_import`; `memories` stays false and
both generation/use settings stay false. No thread/turn is created. The pinned
startup guard returns before spawning the memory pipeline when `MemoryTool` is
disabled; the import only copies resources and enqueues SQL. The selected job
remains pending, with no worker/start/finish/lease. This qualifies ingestion and
queue persistence, not consolidation, memory retrieval or model execution.

Target: `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
Linux executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Twenty-one complete source files match the official archive. Producers:

| Pinned source under `codex-rs/` | Behavior |
| --- | --- |
| `external-agent-migration/src/detect/memory.rs:13-35` | Enabled MEMORY discovery |
| `external-agent-migration/src/memory.rs:88-128` | Reliable project cwd from source JSONL |
| `external-agent-migration/src/memory_import.rs:64-94` | Selected resource copy and consolidation enqueue |
| `external-agent-migration/src/memory_import.rs:93-170,240-280,361-364` | Byte/path/scope comparison, exact copy and scope serialization |
| `external-agent-migration/src/service.rs:394-432` | Public import result source/target |
| `state/src/sqlite.rs:36-38` and `state/src/runtime.rs:148-183` | Separate memory/general state stores |
| `state/src/runtime/memories.rs:1489-1538` | One pending global job and monotonic input watermark |
| `state/src/runtime/external_agent_config_imports.rs:49-126` | Snake-case persisted results and ordered histories |
| `memories/write/src/start.rs:33-38` | Disabled feature prevents pipeline spawn |
| `git-utils/src/baseline.rs:94-174` | Local memory Git baseline; no remote source |
| `app-server/tests/suite/v2/external_agent_config.rs:969-1198` | Matching upstream successful memory import |

Only two exact `ClientRequest.json` owners gain scoped implemented evidence:
`ExternalAgentConfigMigrationItemType/enum/8` and
`MigrationDetails/properties/memory`. Existing disabled-profile evidence remains
attached; it is not substituted for this positive native journey. Both subtree
hashes match the generated/vendored experimental export. Source/node binding
`/tmp/samgita-v467-final-binding/source.json`, SHA256
`0ecd7c1c41d19fbd0706deb37de7632dedcc3ca580f09a90204e58faed5ee2b4`.

The first focused run was **1/1**: the test queried `jobs` in `state_5.sqlite`,
while this pin stores memory jobs in `memories_1.sqlite`. Resource, scope,
instructions and preceding native-frame/progress assertions had passed; repeat,
queue and cold assertions had not yet run. The corrected reader uses separate
read-only connections to the two prescribed stores. It preserves every column,
row/output bound, expected pending state, history and watermark assertion.
No deadline, assertion or production behavior changes. The repaired focused run
passes **1/0**; independent source review confirms the reader delta and finds no
additional concrete functional defect.

The focused command, from the driver package, is:

```sh
mix test test/native_local_memory_migration_test.exs --warnings-as-errors --seed 501432
```

| Artifact | SHA256 |
| --- | --- |
| Final test | `c5483441c8a0a4d11bd4cd1bbf280de21982e73a2ee9d5a3de92b01c575c2033` |
| Initial `/tmp/samgita-v467-owning-501432.log` | `48f6f367a7cec5db197bf5cf8256719f6502e969e2c5f6c26f5f4a15a1071bd1` |
| Repaired `/tmp/samgita-v467-owning-repair1-501432.log` | `9fc974a5a05b536ee61cd93e6c00d7a6e868f1b55653a8d769aa61f21b4b8dd1` |
| Final `/tmp/samgita-v467-owning-final-501432.log` | `36d5a289b3ddb6292c1fdd45c2d197ef97990439ef14993814da29c13f6887ec` |

The first combined-source run passed **64/0 twice**, all selected WebSocket
cases, outside consumer and preceding checks, then stopped at strict Credo:
the test's anonymous capture reducer nested one level too deeply. No final
Dialyzer/assets steps ran in that attempt. The repaired capture uses explicit
`record_received`/`record_event` functions with identical event order, original
bytes, first-error propagation and bounds. Independent delta review found no
concrete defect; final focused **1/0** and strict Credo pass. No lint rule,
assertion, production source or deadline was weakened.

The failed combined attempt remains at `/tmp/samgita-ordinary-v467/`:
results SHA256
`0c63b4b2d20f6b91234dc3444f5721272af6b7d8555b0f819c6b2abbbc423f24`,
source guard
`a48d7f653d6b698d6bb751cfdc40acb987495924a865fa60a180a2a4c07a74b4`,
and strict-Credo log
`c1dc226d05060e0ccc0493b795574bdd3b4272cda99993843a04125e617a0606`.

There are exactly 13 native RPCs, capture bounds of 96 frames/64 KiB per frame/
1 MiB total, 32 events/128 KiB, 16 KiB files/SQL output, at most three job rows
and four history rows. Five-second request/observation deadlines and the
60-second case remain fixed. Checked owner completion, closed Port and native
PID disappearance precede the once-only ownership decrement and scratch removal.
Existing process cleanup implementation stays unchanged. The reviewed ordinary
runner now names 42 driver files/64 cases. All **14 final combined-source steps
pass**: **64/0** at seeds 501432/987654; **3/0** selected WebSocket cases at each
of seeds 455834/501432/987654, with 13 other mixed-file cases excluded; outside
consumer **1/0** (seed 126371); inventory consistency; and retained
compile/format/Credo/Dialyzer/assets checks. All **1,660** guarded source hashes
remain identical. Assets retains the existing Bun mismatch warning (configured
1.3.13, installed 1.1.42), exits 0, and triggers no dependency refresh.

Final evidence `/tmp/samgita-ordinary-v467-final/`: results SHA256
`1bcabefa77604b2b77980c790d67d96e64d7bb9676e41d869ba22019700a8842`;
source guard
`c47ae6817010a360a0b50bd06f82b6d15c3ffae5f68168946c8b78c680abe411`;
command-plan digest
`397059937b2478d45198aea0f367467dbd89004caa98f8041ca6c9fcf969af1b`.

Counts: **5,301 implemented / 1,212 missing / 108 blocked** contracts;
**462 implemented / 12 missing / 11 blocked** requirements, zero verified.
Fixed YOLO is owned-launch setup only. Prohibited security/permission tests and
audits, broad/hosted workflows, A11, unavailable native producers and real
external/backend/OS profiles remain incomplete. No publication or deployment.
Continue the source-only skills omission and selective tool-item projection
boundaries. Raw existing item payloads are distinct from native completion
producers; manufactured data cannot close positive emission acceptance.
