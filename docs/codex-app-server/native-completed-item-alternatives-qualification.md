# Native completed-item alternatives

Four exact physical owners gain implemented-only evidence on base
`4dad602c9633e5a33a4a7cb88f65248ea954697f`. Target: Codex `rust-v0.163.0`,
source `83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The existing citation and compaction tests, fixtures, driver and cleanup are
unchanged. Ordinary owned launches retain fixed yolo configuration.

| Owner | Physical schema | Direct actual output and oracle |
| --- | --- | --- |
| 2564 | `ServerNotification.json`, `ThreadItem.oneOf[18]` | Complete two-field `contextCompaction` item in both started/completed notifications |
| 2574 | `ServerNotification.json`, agent message's `memoryCitation.anyOf[0]` | Both complete nonnull citation objects in started/completed notifications |
| 5523 | `v2/ThreadItemsReadResponse.json`, `ThreadItem.oneOf[18]` | Complete compaction entry in actual selective responses, warm and first cold read |
| 5533 | Same response, agent message's `memoryCitation.anyOf[0]` | Both complete citation objects in actual selective responses, warm and first cold read |

Each owner is bound to its own actual output assertion. Matching hashes across
exports do not establish coverage. Expected items use literal semantic values
and independently observed native IDs/timestamps; no result is copied wholesale
to manufacture a later expected value.

`native_memory_citation_events_test.exs` uses a Responses-only loopback fixture.
Stock Codex parses and strips hidden citation markup. Complete literal maps
require trimmed paths/notes, exact line bounds, first-seen reference deduplication,
modern `rollout_ids` precedence and current-parser `thread_ids` fallback. Both
complete visible messages, phases, IDs, notification order and bounded timestamps
must match. Exactly one provider request contains the independently prescribed
developer/user input. Synthetic paths and reference IDs are inert strings;
memory generation and use remain disabled.

`native_compaction_item_selection_test.exs` first completes a seed turn, then
explicitly submits `thread/compact/start`. Its acknowledgement is separate from
the required native completion. The second provider request must contain the
seed, seed answer and configured compaction prompt under a distinct turn ID.
The actual item must be a UUIDv7 within the observed time window and have exactly
the canonical `id` and `type` fields. Complete started/completed parameters,
ordering, timestamps and completed seed/compaction history are required.

Both tests separately call `thread/items/read` with unique matching native
request IDs. Complete entry equality, duplicate/absent selection controls and
canonical ordering remain required; citation also checks reversed and individual
selections, compaction checks the wrong turn. After confirmed native shutdown,
a distinct unloaded process's **first content operation** is the same selective
read. Original saved history, configuration/catalog/rollout/provider bytes,
provider counts and empty loaded/workspace/uncertainty state must remain exact.
Requests retain 5-second deadlines; collectors retain 20 seconds, 256 events and
1 MiB; test bounds and owned cleanup are unchanged.

The citation producer is `core/src/stream_events_utils.rs` and
`memories/read/src/citations.rs`; the compaction producer is `core/src/compact.rs`.
Canonical session events pass through `bespoke_event_handling.rs`,
`protocol/event_mapping.rs` and `v2/item.rs` to actual notifications. Selective
reads instead traverse `thread_processor.rs`, real stored history/paging and
stored `ThreadItem` deserialization. Twelve complete files match the immutable
archive. The exact exported schema graphs and four canonical node hashes are
independently checked.

The reviewed eight-file functional matrix passes **14 tests / 0 failures** at
both seeds `501432` and `987654`, in 41.346/41.531 seconds. Scoped formatting,
warnings-as-errors compilation, two fixture ASTs and outside-umbrella
actual-binary consumer **1/0** pass. All **311** guarded sources are unchanged
from the base commit. Previous strict Credo evidence still corresponds to these
unchanged sources; no new Credo invocation or broad suite is claimed. No check
fails and no retry, longer timeout or assertion change occurs.

Reproduction: `/tmp/samgita-v348-run.py`, `/tmp/samgita-v348-source.py` and
`/tmp/samgita-v348-bind.py --verify`. Exact command arrays/log hashes and final
manifest binding are under `/tmp/samgita-v348-functional-checks/`.

| Artifact | SHA256 |
| --- | --- |
| `results.json` | `87b132cb0aa1c1d7edf4e75e0395808da72c4013b4e495a3cc62a23562458c69` |
| `source.json` | `238d84915e2b74385e583b665c77030cf62e438e1eaf36b92e5dc1dbd9882d73` |
| `source-evidence.json` | `61be5fa5a86e1f830d7c57b8d759e8d8221d31f861cedd7f9f95d3c92e7e265f` |

Contracts become **5,018 implemented / 1,537 missing / 66 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified. Inventory
consistency passes; strict completeness exits **1**. Local actual-binary evidence
does not establish real-provider or memory-retrieval success, auto/remote/failed
compaction, deprecated `thread/compacted` emission, other OS/transports, power-loss
recovery or full compatibility. Prohibited security/permission tests, audits,
mixed/broad suites and hosted workflows remain unrun; A11, unavailable legacy/
external/platform and full-goal/release gates remain incomplete. No publication,
production migration or deployment occurs.
