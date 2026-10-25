# Native turn-list null defaults and archive retention

One functional scenario qualifies three exact request owners on immutable
Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The real process creates one persistent paginated thread and performs three
explicit assistant-only turns against a local synthetic model provider. There
is no Samgita database, external provider or remote repository operation.

## Independent records, defaults and retained archive

Actual correlated completed-turn and completed-item frames establish three
prescribed native turn IDs and ordered user/assistant items. Exact user markers,
fixed instructions/output and unique item identities are checked before paging.
Public complete histories independently match those records. The model journal
grows only through the three explicit turns.

Eight exact `thread/turns/list` first-page envelopes distinguish omission,
individual explicit nulls, joint nulls and explicit control values. Results must
have independently prescribed turn IDs, completed status, exact item contents
and the actual `itemsView` label. Omitted/null values select summary/descending;
explicit ascending changes order, and notLoaded yields empty items. Three
additional size-one pages, keeping both fields explicitly null, pass each actual
opaque cursor unchanged and cover the three turns exactly once in descending
order, ending at a null cursor.

Each turn has only one user and one final assistant, so full and summary contents
coincide. The native `itemsView` label, independent records and empty notLoaded
control establish these scoped defaults; this does not qualify general summary
truncation for longer/tool turns. Existing resume-page fixtures already included
null inputs in a broader harness. This unit supplies direct owning list-envelope
and independent event evidence for the two specific missing branches.

One exact `thread/archive` request names only this owned completed thread. Its
empty success response and separate native `thread/archived` notice precede
observations that the stable ID moves from active to archived list membership.
Public complete history retains exactly its turns/items/preview. Its real file
now exists in the pinned `archived_sessions` destination with the original
basename. A final joint-null turn-list request returns the same expected summary
page for the archived ID. All **12 list + 1 archive** envelopes and their owning
response IDs are captured exactly. The provider journal remains byte-identical
at three calls, configuration stays unchanged and the workspace remains empty.

Pinned [processor defaults](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L3342)
select Summary/Desc and permit archived turn reads. Its public stored-history
read includes archived records; list filters select the requested archived flag.
The local archive implementation moves the retained file and updates its stored
path. Three full source files match pinned archive bytes; exact excerpts and
ownership are in `/tmp/samgita-v199-next-functional-gap/`. Paginated full-history
read is supported but deprecated. No general flush, crash-atomicity, restart or
durability-ordering guarantee is inferred from observing this completed operation.

Capture remains bounded to 32 frames/4096 bytes, collection to 256 events, ordinary
turn completion to 20 seconds and the archive notice to 5 seconds. Fixed
experimental opt-in enables diagnostics. Exact executable/process hashes and
confirmed owned-process disappearance preserve prior cleanup repairs. The final
session has no pending request, uncertain operation or gap. Independent review
`/tmp/samgita-v202-turn-list-review/REVIEW.md` found no actionable findings and
binds the same final test hash used below.

## Exact owners and final evidence

Only **5127**, **6454** and **6458** become implemented:
`v2/ThreadArchiveParams.json#/properties/threadId` and
`v2/ThreadTurnsListParams.json#/properties/{itemsView,sortDirection}/anyOf/1`.
No aliases, parent fields, whole enums, response schemas or lifecycle owners
inherit evidence. Schema identities/hashes and all requirement rows are unchanged.
Contracts become **4,633 implemented / 1,929 missing / 59 blocked**;
requirements stay **462 implemented / 12 missing / 11 blocked**. Both inventories
retain **zero verified** entries.

The final fourteen-file block is the thirteen files in
[item-anchor qualification](item-anchor-values-qualification.md#exact-owners-and-final-checks)
plus `test/native_turn_list_null_values_test.exs`. Both complete runs with
`--warnings-as-errors --seed 501432` and `--seed 987654` pass **27/0**, in
**47.641/47.896** command seconds. Format, warnings-as-errors compile, root strict
Credo and the **237-file** unchanged-source guard pass. No runtime failure or
deadline/assertion weakening occurs in this unit.

Exact commands/logs/source: `/tmp/samgita-v201-turn-list-checks/functional/`.
Results/source SHA256:
`9f6897011e69a3fee65cde225ea79779b9ae3c2a5316b532e47da8c03ded1f19` /
`2c61312353110ad294f26b9a2a25ab225a64a2ba12ee057e8f7709928358197e`.
The adjacent `manifest-binding.json` retains the original/current three rows and
final test SHA256
`24e1131b3231d55503d1d50ff7b3c35a04c126ff9de6b797ae638c8f2f0ddc2f`.
Runtime libraries/dependencies remain unchanged; earlier outside-consumer
evidence is retained rather than counted as a new run.

This is local Linux/stdio evidence from real Codex with synthetic model responses.
Other transports, platforms/backends, general projections, concurrent mutation
and restart/crash behavior remain unqualified. Security/permission checks and
related broad/hosted workflows remain unrun under the user's restriction. Full
compatibility, A11 and release remain incomplete; no publication or deployment
occurs. Next qualify the four source-backed search GitInfo owners 6094–6096/6137
through public metadata updates and actual content-search results, preserving
the independent control thread and model journal.
