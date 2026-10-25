# Required output variants blocked by the immutable pin

Status: **59 required field contracts blocked; none verified or excluded**.
Target: source `83086188ae0614bd882818ff1aa23f3194962012`, Codex
`rust-v0.163.0`. Source evidence does not substitute for a real emission.

| Required physical contracts | Count | Exact upstream constraint |
| --- | ---: | --- |
| Non-null error in `ThreadQueueStartResponse` | 50 | The sole successful constructor fixes `turn.error = None`. Pre-start failures use the outer JSON-RPC error channel; they cannot produce this result branch or its nested error fields. |
| Other queue-start item views | 4 | The same constructor fixes `items_view = NotLoaded`; summary/full alternatives cannot occur in this response. |
| Terminal queue-start turn statuses | 3 | The constructor fixes `status = InProgress`. Later completion, failure or interruption emits separate messages and cannot rewrite the already constructed response. |
| Null image detail / generated-image savedPath in selective history | 2 | Their exact typed output fields use `skip_serializing_if = Option::is_none`. A null deserialized as None is omitted again when the response is serialized. Omission does not qualify null output. |

Immutable upstream evidence:

- [Queue-start response constructor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_queue_processor.rs#L186-L245).
- [Outer result/error routing](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/message_processor.rs#L1897-L1907).
- [Image detail serializer](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/models.rs#L2206-L2231).
- [Generated-image serializer](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/items/src/image_generation.rs#L21-L43).

The lossless native schema/codec can represent these declared alternatives.
Scripted peers can exercise their handling. Neither fact establishes an
upstream production emitter, and no mock, imported canonical payload or later
notification is counted as native success for these result owners. All original
requirements, planned checks and the 6,621-contract denominator remain intact.
`--require-verified` must continue to fail; no scope exclusion is approved.

Five separate selective-history `inProgress` leaves remain **missing**, pending
exhaustive producer/migration proof or a real native scenario. Canonical history
projects completed items; the inspected completion paths use terminal states,
but core-to-public conversion still permits inProgress, including a patch with
no status. The bounded audit does not prove every producer/migration path is
unreachable. Live item-start evidence cannot qualify canonical completed history.

The recovery artifact contains 64 original rows/nodes, the 59 blocked proposals,
five unresolved histories, 52 immutable/source excerpts and 43 preimages:
`/tmp/samgita-v37-canonical-output-blockers-20261025.json`, SHA256
`ed649f3525ec74b0da4e9370072138fec0d120f168a4a7fb3f9e270c6e0e4bba`.
Its bookkeeping repair distinguishes the older compact-JSON node hashes from
the inventory's indented/newline encoding. Every node value and both historical
hash conventions are checked; source/schema conclusions are not rewritten to
make incompatible hashes match.

The parent validates every selected original row, canonical node/hash and source
excerpt. Only the 59 selected states/evidence/limitations change; tests, transport
coverage, all requirements and the five unresolved histories stay unchanged.
The full manifest matches the generated expected JSON. Binding report:
`/tmp/samgita-v37-pinned-output-blockers-bound-20261025-report.json`, SHA256
`6b8505812b0aa6184319b47c41ce7fbb61bb34f8c78c0a36a4e2bed19ee7fb72`.

Contracts are **0 verified / 4,383 implemented / 2,179 missing / 59 blocked**;
requirements remain **0 verified / 462 implemented / 12 missing / 11 blocked**.
Inventory consistency passes. The unchanged mandatory
`python3 -B scripts/codex/inventory.py --check --require-verified` exits **1**
because required entries remain unverified; this failure is retained.
Real legacy approval emission, required external/backend/OS success and A11
remain incomplete. No upstream executable is modified to manufacture an emitter.
No release, publication, production migration or deployment is authorized here.
