# Pinned native projection boundaries

These three physical schema owners remain **missing**. Source evidence explains
why the pinned local producer cannot supply the proposed observations; it is
not a native success test or completion of the compatibility goal.

Target: official Codex `rust-v0.163.0`, immutable source commit
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Owner numbers identify the existing inventory entries, not new acceptance.

| Owner | Exact schema ID after `schema:` | Missing observation |
| --- | --- | --- |
| 5352 | `v2/ThreadItemsReadResponse.json#/definitions/DynamicToolCallStatus/enum/0` | Selective persisted dynamic-tool `inProgress` |
| 6164 | `v2/ThreadSearchResponse.json#/definitions/Thread/properties/threadSource/anyOf/0` | Nonnull search attribution |
| 6133 | `v2/ThreadSearchResponse.json#/definitions/Thread/properties/extra/anyOf/0` | Nonnull search extension |

## Selective history reads settled items

[`thread_items_read_response_inner`:3622–3669][selective] calls only
`thread_store.list_items`; `stored_thread_item_to_entry`:6173–6186 deserializes
stored JSON. The [local implementation:163–204][local-read] resolves lineage
and queries its history database, without overlaying a live pending callback.
[Materialization:238–244][materialize] applies the canonical rollout projector.

The [projector:78–102][projection] creates item changes only from
`EventMsg::ItemCompleted`. Other events produce no item change. A persisted
TurnStarted can mark a **turn** in progress without creating an item row.
[Persistence policy:212–225][persistence] excludes ItemStarted entirely.

The [actual dynamic producer:219–271][dynamic] emits `InProgress` through
`emit_turn_item_started`, then awaits the callback. Its completed event carries
only Completed or Failed; cancellation also produces Failed. Holding that
callback and querying selective history therefore cannot produce owner 5352.
Flushing history cannot persist a start event excluded by policy. A live
notification, hand-written rollout, mocked response or enum conversion is not
evidence for this selective-response owner.

[Settled tool-item qualification](persisted-tool-items-qualification.md) and
[live notification qualification](failed-dynamic-tool-notification-qualification.md)
cover their own contracts. This dynamic producer analysis does **not** qualify
or prove global unreachability for related selective status owners 5307
(collaboration), 5336 (command) or 5406 (MCP). Each requires its own producer
chain and evidence; their state is unchanged.

## Local search discards the two nonnull fields

The [search endpoint:2800–2884][search] calls the configured store, converts
every returned thread with `thread_from_stored_thread`, then enriches loaded
threads. The [local search:168–180][local-search] converts each matching rollout
through `stored_thread_from_rollout_item`. That [converter:181–184][stored]
unconditionally sets `thread_source: None`, including when the canonical
SessionMeta retained nonnull attribution. Public [conversion:6398–6441][convert]
sets `extra: None` and copies the stored thread_source.

The complete [loaded enrichment:38–90][enrichment] changes status, current
settings and subagent direct-input metadata; [current settings:620–633][settings]
changes model, effort and environments. Neither restores thread_source nor
extra. Thus changing the actual creation source or loading a matching local
thread cannot supply these two nonnull search branches at this pin. This is a
closed local producer chain, not a claim about every possible external store.

[Native search creator/roots qualification](search-creator-roots-qualification.md)
establishes separate owners 6145 and 6172. Its native null controls do not
qualify 6164 or 6133, and recorded creation attribution does not transfer to
the search projection. No feature workaround or upstream bug claim follows
from this documented behavior.

## Source identity and verification limits

Fresh whole-file hashes below match the sources used for this review. Paths
are relative to the immutable commit's `codex-rs/` directory.

| Source | SHA256 |
| --- | --- |
| `app-server/src/request_processors/thread_processor.rs` | `f98fdad7df37ad720e63b75488ffab99ae88f7de4578b280ab957a09f0a98153` |
| `app-server-protocol/src/protocol/thread_history_projection.rs` | `164f88345aebc0922b30243f6df26414bc1a8c19da8663d609332ef2ba8dc756` |
| `rollout/src/policy.rs` | `44243ebf3ea74fd96a9f00adf84c36c7b5f36d3d102c32fcc8c540a49203df3f` |
| `core/src/tools/handlers/dynamic.rs` | `c4c2be4c0ce8902697a6c8be6b0d027a1155d9108d3ef738ce9d9ca731f7b28a` |
| `thread-store/src/local/search_threads.rs` | `d09554c4837d84bb402778badf286c9fc11978db38ac67ebda37753082dde945` |
| `thread-store/src/local/helpers.rs` | `74592931f837777ba80c576de0606261608305baaecf45f691ea95516ddccf66` |
| `app-server/src/request_processors/thread_enrichment.rs` | `481208ff5cbbba257d01a8055c92850c3a217cec4cfded6ae378075d1b803569` |
| `app-server/src/request_processors.rs` | `c5d2caa930bc5a745d7806066ac6b8989ce77d4a7346587a9ea9d10fc642e4ed` |

This documentation adds no runtime verification, mock acceptance, protected
checks, implementation, inventory promotion or aggregate-count change. No
security or permission-related test was run. The three named owners remain
missing, and full compatibility, external integration, A11, publication and
deployment are not established by source analysis.

[selective]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L3622-L3669
[local-read]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/thread_history/read.rs#L163-L204
[materialize]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/thread_history_materialization.rs#L238-L244
[projection]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/thread_history_projection.rs#L78-L102
[persistence]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/rollout/src/policy.rs#L212-L225
[dynamic]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/dynamic.rs#L219-L271
[search]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L2800-L2884
[local-search]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/search_threads.rs#L168-L180
[stored]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/helpers.rs#L181-L184
[convert]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L6398-L6441
[enrichment]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_enrichment.rs#L38-L90
[settings]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors.rs#L620-L633
