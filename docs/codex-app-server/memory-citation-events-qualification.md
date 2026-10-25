# Native memory-citation event fields

This unit covers six physical `ServerNotification.json` fields **2295–2300**:
citation entries and thread IDs, then each entry's line end/start, note and path.
It does not enable memory retrieval. The target remains Codex `rust-v0.163.0`,
source `83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

`native_memory_citation_events_test.exs` uses the ordinary local TurnFixture
setup and an explicitly owned native process with fixed yolo settings. Its
Responses-only provider emits two literal assistant messages. Stock Codex
parses their hidden citation markup and creates all app-server events and
history. Synthetic paths and non-UUID reference IDs are inert strings. No
app-server peer, edited history or real memory service substitutes for Codex.

The actual producer is
[stream_events_utils.rs:465–488](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/stream_events_utils.rs#L465),
which parses and removes citation markup during message finalization. Its
done-only item path emits finalized starts and completions. The pinned
[citation parser](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/memories/read/src/citations.rs#L6)
trims paths/notes and deduplicates reference IDs in first-seen order. Modern
`rollout_ids` take precedence over `thread_ids`; the second message exercises
the older `thread_ids` syntax through this same current producer. This is an
actual parser path in the immutable executable, not a fabricated legacy
app-server interaction. No inference about legacy approval emissions follows.

Independent literal expectations require both complete visible messages and
complete native citation maps. The modern message has two entries and two
deduplicated rollout references; the fallback message has one entry and two
deduplicated thread references. Complete ordered `item/started` and
`item/completed` parameters, stable provider IDs, explicit phases, thread/turn
association and timestamps within host-observed bounds are asserted.

Saved full history and separately executed selective reads must match those
prescribed items and timestamps. Individual, duplicated/reversed and absent
selection IDs are checked. After confirmed owned-process shutdown, selective
read is the replacement's first content operation. Full history follows;
rollout, configuration, catalog and one-request provider-journal bytes remain
unchanged, and both loaded-thread lists stay empty. The workspace stays empty.
These are orderly restart checks, not live-service, power-loss or production
cutover qualification. The original 5-second request, 20-second turn and
256-event/1-MiB bounds and owned cleanup remain.

Seven producer/parser/conversion files byte-match the retained immutable
archive. The six exact notification nodes match pinned provenance; the separate
response export is never promoted through equal node hashes. Source evidence:
`/tmp/samgita-v293-functional-checks/source-evidence.json`. Existing selective
response-owner qualification remains distinct.

The owning test passes **1/0** in the initial two-file functional run, log
`/tmp/samgita-v293-web-citation-501432-repair2.log`; the other file's independent
oracle failure remains recorded. The final explicit **33-file** matrix passes
**59/0** at seeds 501432/987654, including both new units. Warning-free compile,
scoped format, strict Credo, outside actual-binary consumer **1/0**, ten Python
AST checks and the **265-source** unchanged-byte guard pass.
The [standalone-web record](standalone-web-search-qualification.md#verification-record)
contains exact commands, durations, artifact hashes and manifest binding.

Only these six direct notification fields become implemented. Combined with
the independent null-action owner, counts are **4,800 implemented / 1,762
missing / 59 blocked** contracts; requirements remain **462 implemented / 12
missing / 11 blocked**, zero verified. No whole-union, alias, memory-retrieval,
other-OS/transport or full-compatibility claim occurs. Inventory consistency
passes; strict completeness exits **1**. Security/permission tests, audits and
broad/hosted checks remain unrun; their gates stay incomplete. No release or
deployment.
