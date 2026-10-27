# Pinned native projection boundaries

These five physical schema owners remain **missing**. Source evidence explains
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
| 5092 | `v2/SkillsListResponse.json#/definitions/SkillMetadata/properties/dependencies/anyOf/1` | Explicit null skill dependencies |
| 5097 | `v2/SkillsListResponse.json#/definitions/SkillMetadata/properties/interface/anyOf/1` | Explicit null skill interface |

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

## Skills list omits absent optional metadata

The [typed method binding:894–898][skills-method] selects `SkillsListResponse`.
The [catalog endpoint:515–593][skills-catalog] loads native skills snapshots;
forced reload bypasses their ordinary cache. [Optional metadata loading:77–152][skills-metadata]
produces `None` for absent interface/dependencies. The [catalog converter:23–73][skills-convert]
uses `clone().map(...)` for each, preserving `None` rather than inserting JSON
null. Neither removing metadata nor cold startup changes that representation.

The decisive [wire declarations:465–485][skills-wire] give both Option fields
`#[serde(default, skip_serializing_if = "Option::is_none")]`.
`None` omits the key; `Some` serializes a typed object. [Typed payload
serialization:318–368][skills-serialize] retains those semantics. This selected
ordinary producer cannot emit the explicit-null branches at **5092/5097**.

The nullable schema remains supported by the decoder, but a fixture, app-server
mock, rewritten response or equal-hash sibling cannot provide native success
evidence. Omission is not null. This source boundary adds no runtime test,
transport coverage or state promotion; both exact owners remain missing. It is
not an upstream-defect assertion or exhaustion of other ordinary work.

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
| `app-server-protocol/src/protocol/v2/plugin.rs` | `9e4686a275660635aa8328e54162bdced484ffb3ec059e372f6e272bc7430436` |
| `app-server-protocol/src/protocol/common.rs` | `ee03e7b76763ac658f4af3d36c0c1a26c00dff6ee9256d474dd85fa740143cc3` |
| `app-server/src/request_processors/catalog_processor.rs` | `c6da0f910aeb88616a9aeaf6568bffe50f5cf8ed506eca4a23aa377bd7baa336` |
| `ext/skills/src/host_service.rs` | `0c77829ea20f6af113b55289d73862f06fe7ab511a3681eb81cb67f1b52daee3` |
| `ext/skills/src/loader/metadata.rs` | `0b203b4696b17ccf695bbcf8eb3a4e471e9c8b47477081126a06f98f35f600eb` |
| `ext/skills/src/loader/host.rs` | `361a9aa3dc6d5659c472d2c8ce433b0bd415806144b2e2c0fd4a5b9de902e1f6` |
| `ext/skills/src/loader/discovery.rs` | `c5c2901e47a52a30d6bf4cdea822cdcc0a05bd7f4e702ce27430e4ea06930494` |
| `app-server/src/outgoing_message.rs` | `784e9f538eea4def26e33532206541bcecce0f94bea2c8fd2b7cb30463602617` |

All sixteen complete files match their unique members in the immutable source
archive. Both added physical null nodes independently match their recorded
canonical schema hashes. Source binding is recorded at
`/tmp/samgita-v391-source-evidence.json`; the bounded handoff is
`/tmp/samgita-v391-skill-omission-boundary.md`. No executable source changes;
the passing four-case/two-seed matrix retains its original389-source guard.

This documentation adds no runtime verification, mock acceptance, protected
checks, implementation, inventory promotion or aggregate-count change. No
security or permission-related test was run. The five named owners remain
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
[skills-method]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L894-L898
[skills-catalog]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/catalog_processor.rs#L515-L593
[skills-metadata]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/skills/src/loader/metadata.rs#L77-L152
[skills-convert]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/catalog_processor.rs#L23-L73
[skills-wire]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/plugin.rs#L465-L485
[skills-serialize]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L318-L368
