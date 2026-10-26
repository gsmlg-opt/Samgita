# Native search-sort unit inputs

Default validation accepts six source-supported `thread/search.sortKey` objects:
`created_at`, `updated_at` or `recency_at` as the sole key, with null or empty-map
payload. Original values reach native Codex unchanged. Actual persisted ordering
is checked before and after owned-process replacement. Base:
`1f2bbe1a46a5e9e510e9a61cd37583fc6d4003e8`.

## Reproduction and correction

The protocol regression initially reports **5 tests /1 failure**; the native
case reports **1/1**, rejected locally at its first object search after creating
two real threads and completing three turns. A temporary exact-copy diagnostic
changes only `request_native` validation to `:wire` and passes **1/0**, 2.3s.
The temporary file is removed from the package. The final committed case uses
default validation and passes **1/0**, 2.8s; protocol coverage passes **5/0**.
Logs: `/tmp/samgita-v362-{protocol-red,native-red,native-wire-diagnostic,protocol-green,native-green}.log`.

Target remains Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Eight complete relevant sources match their unique archive members. The existing
serde 1.0.228 source/license/origin and Cargo.lock bindings remain checked.

`thread.rs:1545–1552` declares the snake_case unit enum; its nullable input is
at1494. `common.rs:225–289` buffers nested request parameters through pinned
serde, whose enum/unit decoder accepts the six single-key forms. The official
JSON contains only strings. Full ClientRequest reaches this definition only
through `thread/search`; stable contains an unused enum but no method, params
definition or standalone params export. The method remains experimental.

The ninth input supplement wraps the complete canonical schema with three
disjoint required-key object branches, rejecting extra keys and non-unit payloads.
It preserves caller bytes, canonical strings, outer null/omission, required
`searchTerm`, enclosing constraints and experimental negotiation. Generation
guards the exact source declarations, hashes, singleton graph and stable/full
boundary. One provenance entry is added; all **eight prior descriptors**, every
previous pin and all **770 official JSON exports** retain their bytes. Outputs,
transport/session code and native cursor behavior stay unchanged.

## Actual query effects and persistence

The assistant-only model fixture supplies text, not app-server responses or
history. Stock Codex creates two durable paginated threads and completes exactly
three explicitly requested turns. A continuation on the first thread establishes
created order opposite to updated/recency order. A query-only SQLite observer
reads native-generated millisecond columns without seeding or editing state.

Each of the six original objects is queried in both directions, using bounded
complete pages. Responses must match independently observed column ordering,
exact two-thread membership, snippets, timestamp projections, model/cwd/path and
history-mode fields, with null continuation. Captured actual bytes/maps and
response IDs must retain the original object and complete request envelope.

A checked distinct owned process begins unloaded and repeats all twelve queries
before hydration, with the same independent oracles. Public cold histories retain
the exact three user/assistant turns, native paths and rollout bytes. Loaded
threads remain empty. Config/catalog/helper/provider bytes, native timestamps and
the complete provider journal remain unchanged; query/restart inference count
stays three. Capture is bounded to32 frames of4KiB, with exactly29 sends: two
starts, three turns and24 searches. Existing clock/turn/deadline/event bounds and
owned native/Port cleanup barriers are retained.

Updated and recency clocks may move together; this fixture detects a key ignored
in favor of created order, without proving universal UpdatedAt/RecencyAt swap
discrimination. It does not exercise pagination or fix the separately documented
pinned created-search cursor precision defect. Native uses full negotiation;
stable method rejection has structural evidence only.

## Final permitted checks and gates

All eleven commands pass, without selected-test exclusions:

| Check | Result |
| --- | --- |
| Twelve reviewed protocol modules | **57/0**, seeds `501432` and `987654` |
| Twenty-four ordinary driver modules | **126/0 twice**, 199.994/200.762s |
| Driver composition per seed | 97 actual-binary cases and29 scripted faults |
| Outside-umbrella native consumer | **1/0**; local six-form validation, native initialization/listing |
| Scoped format / package compile | Pass, warnings as errors |
| Root strict Credo | Pass on **527** sources |
| Nine Python ASTs / inventory | Pass |
| Executable source guard | **350** stable files; **343** other prior sources unchanged |

Runner, source check and binding: `/tmp/samgita-v362-{run,source,bind}.py`.
Exact commands/logs/hashes: `/tmp/samgita-v362-functional-checks/final/`.
The source binder's initial stale report filename is corrected before its full
successful run; no code, test or assertion changes for that correction.
Independent final source-review SHA256:
`2c6c437963c091a718c4dd6973d99564a3521afd13068a01f4ed20d7635e5809`.

Only supplemental requirement evidence changes. Ledger remains **5,038
implemented /1,517 missing /66 blocked** contracts and **462 implemented /12
missing /11 blocked** requirements, **zero verified**; strict completeness exits
**1**. Security/credential/authentication/authorization/permission/approval tests,
audits, mixed broad suites and hosted workflows remain unrun/incomplete. A11,
producerless legacy, external/OS/platform/final aggregate and full compatibility
remain incomplete. No tag, publication, deployment or real credentials.

Rollback removes this descriptor, registration/provenance addition, derivation
and associated tests/evidence together. Preserve all native histories; no task
state, database migration, redispatch or acceptance is involved. Next reproduce
the independently source-selected `thread/list` ThreadSortKey objects with real
timestamp and custom-section ordering.
