# Pinned native projection boundaries

The original eight physical schema owners remain incomplete. The two explicit-null
skill owners and two nonnull search owners are **blocked** by the stock pinned
implementation; the four selective tool-status owners remain **missing**.
Thirteen further WebSearch, collaboration and command-source owners below also
remain **missing** after tracing their public producers and history inputs.
Source evidence explains the native producer boundaries; it is not a native
success test or completion of the compatibility goal.

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
| 5307 | `v2/ThreadItemsReadResponse.json#/definitions/CollabAgentToolCallStatus/enum/0` | Selective persisted collaboration `inProgress` |
| 5336 | `v2/ThreadItemsReadResponse.json#/definitions/CommandExecutionStatus/enum/0` | Selective persisted command `inProgress` |
| 5406 | `v2/ThreadItemsReadResponse.json#/definitions/McpToolCallStatus/enum/0` | Selective persisted MCP `inProgress` |

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
cover their own contracts. The dynamic analysis does not transfer to the related
command, MCP or collaboration owners. Their separate producer chains follow;
none gains runtime or state credit.

## Other live tool starts are distinct from persisted completion

Command start [emission:170-194][command-events] uses `InProgress`.
The completion [emitter:516-592][command-events] selects terminal statuses
(Completed, Failed or Declined) from the outcome. It never selects InProgress.
Short-lived execution uses that same helper at
[`process_manager.rs:786-834`][command-process]. Background execution does not
settle the item when it returns a live session ID: its
[watcher:180-244,331-382][command-watcher] waits for exit and output drain before
the terminal completion. [User-shell completion:269-350][user-shell] likewise
uses only terminal outcomes. A running background process or live start notice
therefore does not establish persisted command owner **5336**.

The normal [MCP tool-call:992-1077][mcp-call] and separate
[resource handler:215-281][mcp-resource] start with InProgress, then complete
with result-derived Completed/Failed. The local selective projector cannot turn
the discarded start into persisted MCP owner **5406**.

Collaboration [V1 completion status:86-97][collaboration] maps even a still
running child to a completed call; the child status and the collaboration item's
status are different fields. V1 [wait:246-251][collaboration-wait] uses the same
terminal distinction; V2 [wait:114-134][collaboration-v2-wait] completes explicitly.
V2 private analytics is not another public tool-item producer. None supplies
persisted collaboration owner **5307**.

These are closed ordinary local-store producer chains, **not global
unreachability claims**. Stock [store selection:464-520][store-selection] chooses
Local or InMemory; InMemory inherits [unsupported `list_items`:490-496][store-api].
[`thread/resume.history`:354-362][resume-input] accepts ResponseItems, whose
[conversion:181-264][resume-events] does not create these tool completions. The
external session exporter produces ordinary legacy events/ResponseItems, and
legacy command/MCP completion conversion is terminal.

Crucially, [canonicalization:231-240][canonicalizer] preserves arbitrary existing
ItemCompleted payloads except for thread-ID normalization. Supplied/custom
rollouts can therefore contain inProgress; this code does not reject or erase
them. Such manufactured data cannot stand in for a genuine stock production
completion. All three owners remain **missing**, with no tests or transport
coverage added. Existing `native_persisted_execution_items_test.exs`,
`native_persisted_mcp_variants_test.exs` and
`native_collaboration_failure_running_test.exs` retain only their own live-start
and terminal-history evidence.

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
thread cannot supply these two nonnull search branches at this pin.

The stock process-scoped store is constructed at
[`message_processor.rs:302–305`][store-construction]. Configuration permits only
[Local/InMemory:612–618,2569–2574][store-config]; the existing
[store constructor:464–519][store-selection] implements exactly those choices.
The complete InMemory implementation has no `search_threads` override and
inherits [Unsupported:457–466][search-store-api]. The handler maps that error to
method-not-found; it does not fall back to live threads or local search. Thus
InMemory supplies no alternate successful nonnull projection. Custom stores
are not selectable in this stock binary. A custom store could carry attribution
through the shared converter, but the same constructor still sets extra None.

The wire type [derives serialization:201–215,277][thread-wire]. The response
pipeline passes the typed result unchanged; ordinary transport and in-process
serialization cannot inject either field. This closes the stock producer chain,
not every possible custom protocol implementation. Native creation/read can
preserve attribution elsewhere; this boundary applies specifically to search.
Exact owners **6133/6164** now become **blocked**, retaining the earlier missing
annotation as history. No fixture, mock, rewritten result, native-positive test
or transport credit is added.

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
evidence. Omission is not null. The alternate `From<CoreSkillMetadata>` constructor
at `v2/plugin.rs:985` preserves the same Options and serializer. Both exact null
owners are now source-bound **blocked**, with their earlier missing annotations
retained as history. No runtime test, native-positive result or transport credit
is added. This is not an upstream-defect assertion or exhaustion of ordinary work.

## Completed WebSearch null is different from its live start

Selective owner **5483** requires `action:null` in a completed, persisted search.
The hosted [response mapper][search-response] replaces absent action with the
nonnull core `Other` variant; the [public converter][search-item] wraps that
core action in `Some`. The standalone [search handler][search-tool] emits null
only for its start, then a completed extension with `Some(command_action)`.
Its error/cancellation paths do not synthesize a null-action completion.
[Extension emission][extension-emitter] forwards starts and completions separately.

The legacy full-history builder can show null from WebSearchBegin, but that
event and ItemStarted are [excluded from persisted history][persistence].
The selective projector consumes only ItemCompleted. [Legacy migration][legacy-search]
converts WebSearchEnd with its nonnull core action; it cannot promote the begin.
`thread/resume.history` accepts ResponseItems, not arbitrary display items.
The [resume mapper][resume-history] wraps those as ResponseItem records, and
the [full-history response handler][response-history] does not convert supplied
search responses into completed display items. The external
[session exporter][session-export] normalizes conversation text to Message
ResponseItems, rather than preserving arbitrary WebSearch display records.

This closes the reviewed ordinary producers, not the raw-history input space.
The extension representation permits absent action, and the rollout decoder
accepts canonical ItemCompleted values. Canonicalization preserves those values;
`thread/resume.path` can select a caller-supplied rollout. Such input could test
native decoding and projection, but cannot prove a stock-generated completed
null search. Owner **5483** stays missing, with no runtime or transport credit.

## Private collaborator analytics is not a public tool item

Owners **2094–2097 / 5303–5306** require public `collabAgentToolCall` values
`sendMessage`, `followupTask`, `interruptAgent` and `listAgents`; owners
**2101 / 5310** require that item's `interrupted` status. The explicit
[analytics helper][private-collab] says it records private analytics without
another public tool item. All four V2 handlers use that helper. An unfinished
drop retains Interrupted; finished calls record Completed/Failed. Analytics
separately synthesizes an InProgress start. These values pass through
`AnalyticsFact::Notification` to the analytics queue, not the app-server outgoing
channel. A notification-shaped internal analytics value is not a wire emission.

The real public [message/followup effects][collab-message] and
[interruption effect][collab-interrupt] use `SubAgentActivity`. List returns
ordinary tool output. V2 wait emits Wait with InProgress/Completed; V1 handlers
emit only the older five tool names and terminal Completed/Failed call status.
The [legacy conversion][collab-legacy] explicitly returns no legacy event for
the four newer tool names. TurnAborted changes turn status, not a collaboration
item's status. Existing native subagent activity/interruption tests cannot
qualify these distinct enum owners.

The [public converter][collab-converter] does support all four tools and
Interrupted. A genuine canonical event would survive public event forwarding,
full history and selective ItemCompleted projection. Supplied canonical rollouts
can retain those values, so a global impossibility or decoder limitation would
be incorrect. Public `resume.history`/item injection accept ResponseItem rather
than TurnItem; a fabricated model function call is also a different record.
All ten owners stay missing; no mock, analytics capture or manufactured history
receives native-production credit.

## Unified stdin interaction retains the original command item

Owners **2109 / 5335** require CommandExecutionSource `unifiedExecInteraction`.
The source enum and [public enum conversion][command-source] retain the value.
An exact-symbol search across all 5,259 archive-matched Rust sources finds
declarations, analytics/TUI consumers and synthetic tests, but no stock core
production assignment. The [launch path][unified-start] and both
[success/failure watchers][unified-end] assign UnifiedExecStartup.

The actual [stdin path][stdin-event] instead emits TerminalInteraction carrying
the original execution call/process IDs. It does not start a second command
item with another source. The real
[ordinary terminal qualification](ordinary-terminal-interaction-qualification.md)
already proves this notification and original warm/cold execution history.
Legacy command conversion copies any supplied source and canonicalization
preserves supplied ItemCompleted records, so raw/custom history remains an
input caveat here too. Both owners stay missing. Enum support and synthetic TUI
tests do not establish a genuine producer.

## Source identity and verification limits

The V479 producer follow-up archive-matches all **5,259** Rust files, including
all **40** complete sources linked here, and independently checks the thirteen
newly annotated owners against their exact experimental canonical nodes.
Binding `/tmp/samgita-v479-producer-boundaries/source.json`, SHA256
`076a05454140fedec888827c200854f1c56db6f1f327993c8d5a8b3867d5a147`,
also records every UnifiedExecInteraction symbol location. Only scoped source
limitations/evidence are added to those thirteen missing rows: states, tests
and transport coverage stay unchanged. No native process or test runs for this
source investigation; it grants no native-success, alternate-transport or full
compatibility credit. The earlier source reviews and totals below remain
historical checkpoint evidence.

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

The initial review added no runtime verification or state change. Its source
evidence and original missing classifications remain historical context. The
current follow-up archive-matches **all 5,259 Rust files**, hashes **42 key
files**, and independently binds five exact canonical nodes: two skill nulls
and the three tool-status variants. Binding
`/tmp/samgita-v468-projection-binding/source.json`, SHA256
`28115218243bc39b0b503dbcdc88f0c2c18c69d0bacd0a6686dea8f988fcfe7b`.

At V468 only **5092/5097** changed from missing to blocked. **5307/5336/5406** gained scoped
source annotations while staying missing; their tests/transports remain empty.
The other three table owners were unchanged. No test runs, synthetic acceptance
or native-positive credit is added. Full compatibility, external integration,
A11, publication and deployment remain incomplete.

All 14 final V467 logs retain their original hashes. Among the **1,660** guarded
sources only manifest metadata differs; the runner's normalized logic and exact
command-plan digest are unchanged. No new tests run. Inventory consistency
passes; audit evidence `/tmp/samgita-v468-projection-binding/qualification.json`,
SHA256 `0d984950bc2c8b6f6803b5d133ae8859986bcb35b9a7f268d2512fed05db14df`;
inventory log SHA256
`f79f570470b5dab788feeb4482724064a24f7b8f0aa621f2d4e12dec5aca126c`.

V468 counts: **5,301 implemented / 1,210 missing / 110 blocked** contracts;
**462 implemented / 12 missing / 11 blocked** requirements, zero verified.
No prohibited security/permission check, audit or hosted workflow runs. Continue
reviewing existing ordinary configuration metadata evidence for its exact schema
owner before adding a duplicate fixture or granting compatibility credit.

The current V470 search follow-up archive-matches **all 5,259 Rust files**,
binds **15 key complete sources** and both exact experimental search nodes.
Stable ThreadSearchResponse is absent. Binding
`/tmp/samgita-v470-search-binding/source.json`, SHA256
`35249e75dca982450f8755f2ccf3859930b740b8dbc43c7011822cb1118c5c5c`.
Only **6133/6164** change from missing to blocked; all tests and transport
coverage remain unchanged. Counts: **5,302 implemented / 1,207 missing /
112 blocked** contracts, unchanged **462 implemented / 12 missing / 11 blocked**
requirements, zero verified. The preceding config-origin object qualification
accounts for the one implemented contract since V468. This source-only follow-up
does not rerun runtime checks or grant native-success acceptance. Continue
ordinary method/behavior evidence; unavailable/prohibited/external/full-goal,
A11 and release gates remain incomplete. No publication or deployment.

All 14 V469 result logs retain their exact hashes and the command-plan digest
is unchanged. Among 1,660 guarded sources only manifest metadata differs; the
runner's normalized logic remains exact. Inventory consistency passes.
Qualification `/tmp/samgita-v470-search-binding/qualification.json`, SHA256
`069f651987748f3fc831ff5fa828d1cb2af493639b23cd61cee842c3dc153996`;
updated reviewed fingerprint
`7627bd20261254e25cba1b2fb3f16a3d5c7c2744138a80a3fba49811dc0fe46b`.

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
[command-events]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/events.rs
[command-process]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/unified_exec/process_manager.rs#L786-L834
[command-watcher]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/unified_exec/async_watcher.rs
[user-shell]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tasks/user_shell.rs#L269-L350
[mcp-call]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/mcp_tool_call.rs#L992-L1077
[mcp-resource]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/mcp_resource.rs#L215-L281
[collaboration]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents.rs#L86-L97
[collaboration-wait]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents/wait.rs#L246-L251
[collaboration-v2-wait]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents_v2/wait.rs#L114-L134
[store-selection]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/thread_manager.rs#L464-L520
[store-api]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/store.rs#L490-L496
[resume-input]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread.rs#L354-L362
[resume-events]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/event_mapping.rs#L181-L264
[canonicalizer]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/rollout_migration/canonicalizer.rs#L231-L240
[store-construction]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/message_processor.rs#L302-L305
[store-config]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/mod.rs#L612-L618
[search-store-api]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/store.rs#L457-L466
[thread-wire]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs#L201-L215
[search-response]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/event_mapping.rs#L228-L238
[search-item]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L992-L1005
[search-tool]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/web-search/src/tool.rs#L135-L192
[extension-emitter]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/extension_tools.rs#L136-L178
[legacy-search]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/rollout_migration/legacy_event.rs#L206-L215
[resume-history]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L4789-L4803
[response-history]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/thread_history.rs#L479-L504
[session-export]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/external-agent-migration/src/sessions/export.rs#L44-L190
[private-collab]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents_v2/analytics.rs#L10-L62
[collab-message]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents_v2/message_tool.rs#L86-L100
[collab-interrupt]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents_v2/interrupt_agent.rs#L62-L75
[collab-legacy]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/legacy_events.rs#L270-L337
[collab-converter]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L1229-L1259
[command-source]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L1117-L1126
[unified-start]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/unified_exec/process_manager.rs#L586-L594
[unified-end]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/unified_exec/async_watcher.rs#L330-L441
[stdin-event]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/unified_exec/process_manager.rs#L1119-L1134
