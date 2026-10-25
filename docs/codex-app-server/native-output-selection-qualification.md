# Native output conversion and selective history

This unit exercises stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The driver receives every app-server frame from that executable. Local Responses
peers provide prescribed model output; they do not supply app-server frames.
This is selected native conversion/persistence evidence, not real search-service,
memory-retrieval, account, backend or full-compatibility acceptance.

## Producers and independent expectations

`native_web_search_items_profile.exs` prescribes five completed web-search items:
Search, OpenPage, FindInPage, an unknown action and an absent action. The last
two become native Other actions; results remain explicit null. It asserts the
complete live started/completed items and generated timestamp bounds, then exact
warm and first cold `thread/items/read` results. Reordered/duplicate selection
IDs, missing items and wrong turns have explicit result assertions. The URLs
are inert strings; web search and execution are disabled.

The immutable [output conversion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/stream_events_utils.rs#L315-L456),
[action conversion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/event_mapping.rs#L228-L242)
and [native item mapping](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L856-L871)
establish the actual producer. This does not prove hosted browsing, dispatched
search-tool execution, structured search results or an `action:null` result.

`native_memory_citation_profile.exs` prescribes two assistant messages with modern
and legacy citation markup. It independently expects exact entries, line numbers,
trimmed Unicode notes/paths, first-seen ID deduplication, modern rollout-ID
precedence and stripped visible text. Complete live objects, warm selective
reads, first cold selective reads and subsequent public history retain those
values. Citation paths and non-UUID IDs are inert strings; memory use/generation
is disabled, and no host-memory retrieval is qualified.

The immutable [citation parser](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/memories/read/src/citations.rs#L6-L85),
[ordinary message finalization](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/stream_events_utils.rs#L465-L488)
and [wire conversion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L888-L904)
establish this producer without inventing a memory-retrieval path.

Both cases start explicitly owned native processes inside private user/network
namespaces, require loopback-only routing with no IPv4/IPv6 default route, and
restart the actual native PID before the first cold content read. A prior full
read supplies only the native store barrier; expected item content comes from
fixed inputs, never a history response. Cold reads require an empty loaded-thread
list, byte-preserved provider journals and no additional inference/execution.
Owned native/controller/namespace PIDs must disappear after shutdown. The shared
native shutdown/owner-death implementation and its deadlines remain unchanged.

## Executed checks and exact coverage

The external copied-source layout passes both complete cases **2/0** at seeds
`501432` and `987654`, in 4.4/4.6 seconds. Current-checkout integration then passes
**2/0 twice**, 3.7 seconds each, plus root/driver warning-free compile and format,
strict Credo on **451 files**, all **38 tooling regressions** and inventory
consistency. Explicit required hosted steps invoke both profiles; hosted execution
of this new source remains a separate gate.

Run from `apps/samgita_codex_driver`, with the pinned `CODEX_BINARY` and the
documented namespace prerequisites:

```sh
mix test test/native_web_search_items_profile.exs test/native_memory_citation_profile.exs --warnings-as-errors --seed 501432
mix test test/native_web_search_items_profile.exs test/native_memory_citation_profile.exs --warnings-as-errors --seed 987654
```

Candidate evidence is `/tmp/samgita-v129-output-candidate-check/`; final integrated
commands/logs and the six-file guard are in `/tmp/samgita-v134-output-integration/`.
Its result/source SHA256 are
`9525c473d13244f112d68d95171922e9dc62332549e4d874d111984b76fecd9d` /
`b62f320d8ab092fccebb6fe3818047431cb047d44a106c08167667546d373023`.
The first integrated static run at `/tmp/samgita-v133-output-integration/` failed
two cleanup-helper nesting checks before native execution. Extracting the same
PID-disappearance predicate preserves every assertion and deadline; the complete
integrated block above then passes without exclusions.

Exactly **29** physical `v2/ThreadItemsReadResponse.json` contracts gain scoped
implemented evidence: 23 web-search item/action owners and six canonical
MemoryCitation/MemoryCitationEntry properties. Original rows, generated node
hashes, called-result reference closure and independent assertion ownership are
retained in the v121/v124 owner maps. Ref wrappers, null/omission alternatives,
structured results, notification copies and sibling/equal-hash schemas receive
no promotion. Requirements remain **462 implemented / 12 missing / 11 blocked**;
contracts become **4,515 implemented / 2,047 missing / 59 blocked**; zero verified.

Complete new-source local and hosted qualification, A11, unavailable native
emitters and real external/backend/OS success remain required. No release,
publication, production migration, deployment or sibling-service change occurs.
