# Native item-anchor pagination values

One functional scenario qualifies twelve exact request owners on immutable
Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The official process creates a persistent paginated thread and three explicit
assistant-only turns against a local synthetic model provider. No Samgita
database, endpoint or external provider is required.

## Independent records and exact page effects

Six expected entries are derived from actual correlated `item/started` and
`item/completed` frames before any page is read. Prescribed user text and fixed
assistant output, unique item IDs, owning turn IDs and positive ordered item
timestamps are checked independently. Complete public history must contain the
three prescribed completed turns and exactly their emitted items.

The unchanged-byte transport captures **19** exact `thread/items/list` envelopes,
including each response's owning request ID:

| Requests | Independently expected native result |
| --- | --- |
| Seven first-page maps with omitted/null cursor and omitted/null/asc/desc direction | First two of six expected entries in the prescribed direction |
| Three pages in each direction, passing each actual opaque cursor unchanged | All six entries exactly once in prescribed ascending or descending order; final cursor null |
| Selected middle-turn user anchor, omitted/null/asc direction | Only its assistant; anchor excluded |
| Selected middle-turn user anchor, descending | Empty page with both cursors null |
| Selected middle-turn assistant anchor, descending | Only its user; anchor excluded |
| Selected middle-turn assistant anchor, ascending | Empty page with both cursors null |

Surrounding first/last turns make leakage outside the selected turn observable.
Paging preserves the validated complete history, ID/path/preview, existing file,
exact three-request provider journal, configuration and empty workspace. Only
explicit turns add model requests. The final session has no pending request,
uncertain operation or event gap. Capture is bounded to 32 frames/4096 bytes;
the completion collector retains at most 256 events and the ordinary 20-second
turn deadline. Fixed experimental opt-in supports process diagnostics. Exact
binary/process hashes and confirmed owned-process disappearance retain the
existing cleanup repairs.

The pinned [processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L3561)
distinguishes opaque and object positions, requires a selected turn for object
anchors and defaults omitted/null direction to ascending. The pinned
[store](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/thread_history/segment_paging.rs#L240)
resolves an anchor within that turn with `include_anchor: false`.
Paginated persistent `thread/read includeTurns:true` is supported but deprecated
at this pin; it is a public history observation here, not a general flush
barrier. Four inspected source files match archive bytes. Mapping, implementation
and public-history proof are retained in `/tmp/samgita-v194-next-functional-gap/`
and `/tmp/samgita-v195-item-anchor-implementation/`. Independent source review is
`/tmp/samgita-v197-item-anchor-review/REVIEW.md`; subsequent formatting is bound
to the final test hash below.

## Exact owners and final checks

Only owners **620–625**, **5265–5267** and **5269–5271** become implemented:

- `ClientRequest.json`'s assigned anchor object alternative, itemId/type/literal
  and cursor string/object alternatives.
- `v2/ThreadItemsListParams.json`'s cursor field/ref/null and sortDirection
  field/ref/null.

No enclosing method/response unions, unrelated siblings or aliases inherit
evidence. Schema identities/hashes and all requirement rows remain unchanged.
Contracts become **4,630 implemented / 1,932 missing / 59 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**. Both
inventories retain **zero verified** entries.

The final thirteen-file block is the twelve files in
[source qualification](thread-start-source-qualification.md#exact-owners-and-final-evidence)
plus `test/native_item_anchor_values_test.exs`. Both complete runs with
`--warnings-as-errors --seed 501432` and `--seed 987654` pass **26/0**, in
**45.826/48.477** command seconds. Format, warnings-as-errors compile, root
strict Credo and the **236-file** unchanged-source guard pass. No runtime
failure, removed assertion or increased deadline occurs in this unit.

Exact commands/logs/source: `/tmp/samgita-v196-item-anchor-checks/functional/`.
Results/source SHA256:
`01b93bea0cb777674d1e9db7e0544ace3dba207941ed31a5e52b283bd98d5e2a` /
`56365bcaf86a32e72dd46cd17a56e6951d60545147654f97fa96f2ffd229ea24`.
The adjacent `manifest-binding.json` retains original/current twelve rows and
final formatted test SHA256
`b3c5690eb2060f145b87f8b009c0739955acbbfd57d24ee70160f32a0abc4136`.
Runtime libraries/dependencies remain unchanged. Earlier outside-consumer
evidence is retained, not counted as a new run.

Nonempty anchor-to-opaque continuation inside one selected turn remains
unqualified: these turns each contain only two items. Foreign/malformed anchors,
concurrent mutation, forks/lineage, general backwards-cursor behavior and other
transports/backends/platforms also remain unqualified. This is local Linux/stdio
evidence from real Codex with synthetic model responses. Security/permission
checks and related broad/hosted workflows remain unrun under the user's
restriction. Full compatibility, A11 and release gates remain incomplete; no
publication, production migration or deployment occurs.

## Next bounded functional investigation

`/tmp/samgita-v198-next-functional-gap/` confirms the pinned successful
`thread/readState/update` producer cannot return the turn alternative owned by
5850–5853: Read returns null and Unread returns threadStart. Conflict errors and
attention snapshots are different physical owners. Keep these missing with
upstream source evidence; do not substitute a mock or manufactured race.
Continue mapping actual turn-list explicit-null defaults (6454/6458) and archive
identity (5127) before selecting the next genuine functional scenario. This
bounded source pass neither completes the goal nor exhausts independent work.
