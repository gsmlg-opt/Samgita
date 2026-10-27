# Native V1 child null path in search

This ordinary functional qualification starts from
`e0e55373a08783987dc19fb77b72fec68c12d211` on `main`. It extends the existing
`native_collaboration_lifecycle_values_test.exs` with one real-native search
case; its original lifecycle case remains intact. Production code and the
local model fixture are unchanged.

Target: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The unchanged collaboration fixture hashes to
`3b0631a4b79df452b7e228a07d2a9c1ef56b7160dc52bc43665933f04c67bdef`;
the final test file hashes to
`3a70914e9314f02424d648efe3c211f8224f0aab397a285249e25fbd560e64bd`.

## Actual producer and physical owner

Only owner6116 is selected:
`schema:v2/ThreadSearchResponse.json#/definitions/SubAgentSource/oneOf/1/properties/thread_spawn/properties/agent_path/anyOf/1`.
Its canonical null-node SHA256 is
`b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb`.
No enclosing source, nonnull path, status, alias or pagination owner follows
automatically from this evidence.

The [stock V1 spawn handler](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents/spawn.rs#L125)
passes `task_name:None`. The
[shared source constructor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents_common.rs#L141)
leaves its path None, and native control preserves it. The
[canonical nested enum](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/protocol.rs#L3027)
serializes that optional path without omitting null. Actual public search
retains the nested source. This differs from the existing V2 producer, which
always constructs a path from its task name.

The unchanged loopback Responses fixture supplies only model outputs. Stock
Codex creates a root and child, completes the child, waits, closes it and
reports a subsequent closed wait. Six model requests are required: five root
and one child. The child ID comes from the real spawn result, independently
of search, and differs from the root. Prescribed input/answer, completed turns
and all four terminal lifecycle items are checked through actual native APIs.

Warm and first-cold source-filtered `thread/search` calls return only that
child, its prescribed snippet/preview, original path, exact full source and
notLoaded status. Both calls independently require a present `agent_path:null`
with the known parent ID and depth1; copying a source object alone cannot pass.
The actual canonical SessionMeta has the same present null leaf. No history,
preview, native frame, database row or ID is fabricated, and no archival or
resume operation is used to make the child discoverable.

## Preserved failures and source corrections

The first red module run is **2 tests/1 failure**: the canonical metadata oracle
used public casing. The
[core enum](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/protocol.rs#L2944)
uses lowercase `subagent`; the
[v2 enum](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs#L27)
uses camelCase `subAgent`. The correction asserts both exact keys explicitly,
retaining the shared strict parent/depth/present-null assertion.

The next red module run is **2 tests/1 failure**: an unrelated nil reverse-cursor
oracle was incorrect. The actual search already contained the expected child
and null path. Native search
[derives a first-row cursor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L2851),
then default descending created sort subtracts1ms at5902–5927. Local conversion
first rounds created_at to seconds (`rollout/src/recorder.rs:2170` and
`local/helpers.rs:138`). The corrected exact cursor oracle uses the separate
prior full-history createdAt observation, multiplied by1000 minus1ms. Both
warm/cold comparisons remain exact; reverse pagination success is not claimed.
Corrected native execution passes **2/0** without changing deadlines or retries.

## Bounds, recovery and verification

The new case has exactly ten captured frames: one start, one turn, one selective
item read, five loaded-list queries and two searches. Original search bytes,
complete maps and correlated unique IDs are checked; capture stays32frames/
4KiB and responses65KiB. The original case keeps twelve frames and its exact
test body (single-terminal-newline SHA256
`bf54c63a0aa264aa24a44bd99b562fb2cfeb09d32175acd604c2e736e6f7a6fb`).
All original assertions remain.

The warm/cold provider journal stays exactly six requests. Complete histories,
sources, paths, rollout/config/catalog/fixture bytes and empty workspace remain
equal. Cold queries/read leave loaded IDs empty and add no inference. Snapshot/
event buffers stay1MiB, turn events256, final drain128, calls5s, turns20s and
case60s. Both owned native processes require completion, closed Port and absent
PID; original failure cleanup remains. Fixed YOLO is launch setup only.

The first metadata binding rejected a body digest because its excerpt included
one extra trailing blank line. Exact old/new byte equality already passed.
The corrected binder checks both the complete equal excerpt digest and the
reviewer's single-terminal-newline digest. No executable source or test changes.

The final reviewed matrix passes **87schema and153ordinary driver tests at
both501432 and987654**, with outside-umbrella native consumer **1/0**. Both
packages compile and pass scoped formatting; strict Credo550, fixture syntax
and inventory consistency pass. All eleven commands finish successfully.
The384-source guard remains equal before/after, with all383 other previous
sources unchanged. Eighteen complete upstream sources match their immutable
archive members; official exports770 and input descriptors15 remain exact.
Source-only review is separate from native runtime evidence. Earlier platform,
root/static/assembly evidence is retained without fresh-run claims; the broad
matrix and hosted workflows remain unrun under the user's restriction.

Only6116 becomes scoped implemented; the request/response rows receive
supplemental evidence. Requirements remain **462 implemented /12 missing /11
blocked**; contracts become **5,068 implemented /1,487 missing /66 blocked**,
zero verified. Inventory consistency passes; strict completeness still exits1.
The ordinary user-input wait flag6169 and excluded approval flag6168 remain
incomplete. A green selected matrix does not complete the full goal.

Runner and logs: `/tmp/samgita-v383-run.py` and
`/tmp/samgita-v383-functional-checks/final/`; source closure is
`archive-evidence.json` in its parent. Both original red logs/sources and the
corrected native log remain under `/tmp/samgita-v383-native-*`; the final source
review is `/tmp/samgita-v383-source-review.md`. No protected/broad/hosted test or
audit runs. A11, missing legacy/native producers, other transport/backend/OS
and external profiles, required prohibited verification and full compatibility
remain incomplete. Nothing is published or deployed. Rollback restores only
the pre-unit test version and exact evidence, preserving runtime and history.
