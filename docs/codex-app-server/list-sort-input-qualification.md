# Native list-sort unit inputs

Default validation now accepts the eight native `thread/list.sortKey` objects:
`created_at`, `updated_at`, `recency_at` or `section_position` as the sole key,
with null or empty-map payload. Caller values reach native Codex unchanged.
Timestamp and custom-section ordering are checked before and after owned-process
replacement. Base: `8ce03b0be3f602b54795bfdec69b7b111263dc34`.

## Reproduction and correction

Before the correction the protocol regression reports **5 tests /2 failures**,
and the real-native case **1/1**, rejected locally at its first object list after
creating the real threads, section and moves. An exact-copy diagnostic changes
only the request helper to `validation: :wire` and passes **1/0**, 2.3 seconds.
The diagnostic remains outside the repository. Final default-validation coverage
passes protocol **5/0** and native **1/0**, 2.8 seconds. Logs:
`/tmp/samgita-v363-{protocol-red,native-red,native-wire-diagnostic,protocol-green,native-green}.log`.

Target remains stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Eight complete relevant sources match their unique archive members. Existing
serde 1.0.228 source/license/origin and Cargo.lock bindings remain checked.

`thread.rs:1534–1543` declares the snake_case unit enum; nullable input is
declared in ThreadListParams. The internally tagged ClientRequest buffers nested
parameters through pinned serde, whose enum/unit decoder accepts these eight
single-key objects. Official JSON exports describe strings only. Both standard
and full request graphs reach this type solely through `thread/list`.

The tenth input supplement wraps the complete canonical definition with four
disjoint required-key object branches. Empty/unknown/multiple/extra keys and
non-unit payloads remain invalid. Original bytes, canonical strings, outer
null/omission, enclosing constraints and existing gates stay intact. The generator
checks complete source hashes, declarations, both request graphs and all four
ClientRequest/standalone schema hashes. Provenance adds one descriptor; all
**nine prior descriptors**, previous pins and **770 official exports** keep their
bytes. Output schemas, transport/session behavior and native cursors are unchanged.

## Actual ordering and persistence

An assistant-only local model fixture supplies text; all app-server responses,
identities and stored histories come from the pinned executable. It creates two
paginated threads and completes exactly three explicitly requested turns. Public
custom-section creation and moves prescribe section order B,A. The third A turn
then establishes created(A) < created(B), updated/recency(A) > updated/recency(B)
and position(B) < position(A), with independent query-only SQLite column checks.
No native database row is seeded or rewritten.

All eight original objects are queried in both directions, producing sixteen
warm lists. Every complete page must match independently observed timestamp or
section order, exact membership, projected fields and terminal null cursor.
Captured original maps/bytes and response IDs establish correlation. A distinct,
reaped-and-replaced owned process starts unloaded and repeats all sixteen queries
before history hydration, using the same independent expected ordering.

Exact completed public histories, rollout bytes, configuration/catalog/helper
files, SQLite observations and provider journal survive replacement unchanged.
The journal remains three inference requests. Capture is explicitly bounded to
48 frames of 4KiB and exactly40 sends: two starts, three turns, one section create,
two moves and32 lists. Existing case/request/turn deadlines, bounded collectors
and native/Port cleanup barriers are retained. Standard/full schema options are
structural coverage; the actual native session uses full negotiation.

This does not qualify pagination or distinguish UpdatedAt from RecencyAt in every
lifecycle; their clocks may coincide. It does not repair or qualify the separate
upstream reverse/search cursor precision defects. No new physical schema owner,
task transition or acceptance behavior is inferred from an alternate input form.

## Final permitted checks

The final serialized matrix passes without selected-test exclusions:

| Check | Result |
| --- | --- |
| Thirteen reviewed protocol modules | **62/0**, seeds `501432` and `987654` |
| Twenty-six ordinary driver modules | **128/0 twice**, 186.097/206.308 seconds |
| Outside-umbrella native consumer | **1/0**; local eight-form validation and native handshake/list |
| Scoped format and package warning-free compilation | Pass |
| Root strict Credo | Pass on **529** sources |
| Python ASTs, source derivation and inventory consistency | Pass |
| Executable source guard | **353** stable files; **346** other prior sources unchanged |
| Root warning-free compilation, full format, assets build | Pass |
| Root `mix dialyzer --force-check` | Pass; zero errors or skips |
| Legacy architecture scanner and its functional tests | Pass |
| Production compilation, assets deployment and local assembly | Pass; local archive only |

Exact commands, log hashes and source bindings:
`/tmp/samgita-v363-functional-checks/{final,aggregate,assembly}/`.
Runner/source/binder: `/tmp/samgita-v363-{run,source,bind}.py`.
Independent source review: `/tmp/samgita-v363-final-review.md`. Local assembly
does not start a service, migrate a database, publish or deploy.

Only supplemental requirement citations change. Ledger stays **5,038 implemented
/1,517 missing /66 blocked** contracts; **462 implemented /12 missing /11 blocked**
requirements, **zero verified**. Strict completeness exits **1**. The user's
restriction leaves security, credential, authentication, authorization, permission
and approval tests, audits, mixed broad suites and hosted workflows unrun and
incomplete. A11, producerless legacy, required external/OS/platform profiles and
complete compatibility remain incomplete. No tag, publication or deployment.

Rollback removes this descriptor, registration/provenance addition, derivation
and associated tests/evidence together. Preserve all native histories; no database
migration, redispatch or task acceptance is involved. Next reproduce the four
source-selected SortDirection objects on six reachable request paths with
independent native list/history/project ordering.
