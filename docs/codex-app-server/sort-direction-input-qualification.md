# Native sort-direction unit inputs

Default validation accepts `{"asc":null}`, `{"asc":{}}`, `{"desc":null}` and
`{"desc":{}}` on six native request paths. The correction preserves caller
bytes and existing experimental negotiation. Base:
`856ad1a5a1801fa9a82d3dc1bfccf40bc4f3de36`.

| Request | Direction field | Negotiation |
| --- | --- | --- |
| thread/list | sortDirection | Standard |
| thread/turns/list | sortDirection | Standard |
| thread/items/list | sortDirection | Standard |
| thread/resume | initialTurnsPage.sortDirection | Present enclosing page is experimental |
| project/list | sortDirection | Experimental method |
| thread/search | sortDirection | Experimental method |

## Reproduction and bounded correction

Before the correction, protocol coverage reports **5 tests /3 failures** and
real-native coverage **2/2**; both native cases are rejected locally before their
first object query reaches Codex. Exact original objects pass the real native
decoder when only the helper's validation option changes to `:wire`. Final
delivered tests use default validation. Diagnostic files stay outside the
repository; no runtime validation bypass is added.

The immutable target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Twenty-five complete protocol, handler, store and recovery sources match their
unique archive members. Pinned serde source, license, origin and Cargo.lock
bindings remain checked.

`thread.rs:1554–1560` declares the snake_case Asc/Desc unit enum. The internally
tagged ClientRequest buffers its parameters through pinned serde, whose decoder
accepts one known key with null or empty-map payload. Official JSON exports
describe strings only. Fresh property-reference traversal finds exactly three
standard and six full input paths, including the nested resume page.

The eleventh input descriptor augments only those paths with two disjoint object
branches around the complete canonical schema. Malformed keys, additional keys,
non-unit payloads, required fields and enclosing constraints remain enforced.
Original maps/bytes, canonical strings, outer null/omission and all existing
method/field gates remain intact. In particular, a present page with nested null
direction differs from an outer null page. The native project handler still owns
its direction-requires-key rule; the test does not invent that schema constraint.

The generator guards exact sources, all six declarations/defaults, the nested
page and method gates, eleven raw schema hashes and both reachable graphs.
`source/project.rs` is added verbatim from the pinned archive. Provenance adds
only that file and the new descriptor. All **ten prior descriptors**, existing
pins and **770 official exports** retain their bytes. Outputs and Session,
transports, cleanup and platform code are unchanged.

## Actual ordering, history and recovery

The history case creates two genuine paginated threads and three assistant-only
turns A1/B1/A2. A read-only native SQLite observer independently establishes
creation order. Original native item events establish three distinct turn IDs,
six distinct item IDs, exact text/content and start/completion timestamps.
Those independent expectations prescribe complete list/search order, A's two
turns and its four items in both directions, including resume bootstrap pages.

Each object reaches all five history-related methods warm and after replacement.
All sixteen cold list/search/turn/item queries execute before explicit resume;
loaded threads remain empty and provider requests remain exactly three. Original
maps, literal object bytes, response correlation and null terminal cursors are
checked. Thread/item content and page metadata remain exact across replacement.

Native list/search adds loaded-runtime projections. Each warm row must report
exact Idle status and its known local environment; each cold pre-resume row must
report NotLoaded and null environments. Only these two independently asserted
fields are removed from the subsequent whole-page comparison. Every other
thread/page field, read state, cursor and snippet stays exact. Initial diagnostic
whole-page equality incorrectly expected the runtime projections to survive
process death; the compact diff and pinned enrichment source establish the cause.

The first explicit cold resume is a mutation boundary. Pinned Session::new
persists one `thread_settings_applied` checkpoint and native metadata sync uses
`Utc::now()` to advance updated_at_ms. The successful correlated resume response
awaits persistence. The test requires the entire original rollout as an exact
prefix plus exactly one bounded, newline-terminated record with the original
thread ID, next ordinal and known ordinary model/provider/cwd/roots. Its native
timestamp and updated_at_ms must lie inside the independently measured request
interval. Creation time must match the original session metadata exactly;
recency and every other thread's timestamps remain unchanged. The resulting
complete bytes and timestamp maps are frozen before the
remaining three warm resumes, which must preserve them exactly. No extra turn
or inference is allowed. Earlier diagnostic failures from assuming immutable
cold-resume bytes/time remain in the logs; they are fixture expectation errors.

The second-seed checkpoint initially fails **1/10** because creation time also
changes by1ms. Bounded source diagnosis establishes two independently sampled
clocks: ThreadMetadataSync::for_create initializes SQLite creation time before
the recorder samples `session_meta.payload.timestamp`. Cold history observation
restores creation from that original payload timestamp. The correction parses
the untouched original metadata, requires its thread ID, and converts that
precise timestamp to milliseconds. It does not use the outer JSONL record time,
accept a tolerance or assume the difference is bounded to1ms. The entire
post-resume timestamp map must equal the original map with only this exact
creation value and the independently bracketed update value replaced. All other
times remain exact. The original SQLite clock still independently prescribes
every pre-resume list/search order. Source and native behavior are preserved;
the driver neither edits upstream state nor rewrites returned timestamps.

The separate project case creates P/Q, publicly moves Q before P, and checks all
four direction objects against that prescribed position order and its reverse.
Independent project reads and read-only stored positions, names, keys, roots,
metadata and timestamps must match complete pages before and after replacement.
There are no threads or inference requests in this case.

Capture is bounded to **45/48** history frames and **11/16** project frames, each
at most4KiB. Existing 60-second case, 20-second turn, 5-second request, 2-second
clock and bounded event/snapshot limits remain. Owned native PIDs are verified,
closed and reaped before replacement. Source/config/catalog/provider journals,
original history and every subsequent frozen snapshot remain checked.

This qualifies full-session negotiation and paginated ordinary complete pages.
Only the first of four cold-process resumes is an unloaded branch. Independent
cold load for every object, legacy/active overlays, pagination/cursor guarantees,
other transports/backends and real provider success remain unqualified.

## Permitted qualification and remaining gates

The scoped final matrix runs fourteen reviewed protocol modules and six affected
ordinary driver modules at seeds `501432` and `987654`, plus the independent
consumer, warning-free compilation, formatting, strict Credo and inventory.
Executable source guards cover357 files, including349 unchanged prior sources.
The first strict check rejected two complex test helpers; extracting their
unchanged parameter/event bodies resolves that finding without exclusions.
All eleven final commands pass: **67/0 schema and10/0 actual-binary cases at
both seeds**, **1/0 outside consumer**, warning-free compile/format, strict Credo
on531 sources and inventory. The final native blocks take24.468/24.118 seconds.
The retained neutral WebSocket overflow/live/replay, queued-owner overflow and
oversized-replay/gap cases also pass **3/3** at original seed455834 and987654.
Only those three source-reviewed functional cases are selected (13 other cases
are unrun); no authentication, authorization or approval test is executed.
Exact results and hashes are in
`/tmp/samgita-v364-functional-checks/qualified/`; source/runner records are
`/tmp/samgita-v364-{source,run-qualified}.py`. Earlier failed `focused/` and
`final/` records remain intact. Independent source reviews are
`/tmp/samgita-v364-{independent,final}-review.md`.

Only supplemental requirement evidence changes. The ledger remains **5,038
implemented /1,517 missing /66 blocked** contracts and **462 implemented /12
missing /11 blocked** requirements, **zero verified**. Complete final-source
aggregate checks remain required after further executable changes. The user's
restriction leaves security/credential/authentication/authorization/permission/
approval tests, audits, mixed broad suites and hosted workflows unrun/incomplete.
A11, producerless legacy, external/OS/platform profiles and full compatibility
remain incomplete. No tag, publication, service start or deployment.

Rollback removes this descriptor, source/provenance additions, derivation and
tests/evidence as one unit. Keep all native histories and the prior ten input
corrections. No platform database migration, redispatch or task acceptance is
involved. Next reproduce the four source-selected ProjectSortKey objects on
project/list with independent position, recency and key-dependent default order.
