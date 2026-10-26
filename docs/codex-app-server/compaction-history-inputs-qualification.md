# Genuine compaction checkpoint history inputs

Two original actual-native profiles transfer a genuine installed remote-v2 compaction
checkpoint through the pinned unstable `thread/resume.history` API. One imports
the original maps unchanged; the other changes only an absent checkpoint
metadata field to explicit client null. Both consume the checkpoint in one
deliberate followup without executing another compaction. A later third profile
adds one deliberately client-supplied metadata object, as detailed below.

## Native records and lifecycle

`apps/samgita_codex_driver/test/native_supplied_compaction_history_test.exs`
uses the real immutable binary and new ordinary Responses provider
`scripts/codex/supplied_compaction_history_fixture.py`. Its first two replies
delegate to the unchanged `model_fixture.py` compaction scenario; the third
reply is a prescribed assistant answer after validating actual native input.
It never creates app-server frames, native rows, sidecars or database records.
Yolo is fixed setup throughout; no external service is required.

One seed turn completes, then `thread/compact/start` merely acknowledges
submission. Separate native compact-turn/item start and completion establish
actual installation; the second provider request contains one real
`compaction_trigger`. Close/reap precedes bounded inspection of the source
rollout. The checkpoint is inside the **current**
`compacted.payload.replacement_history`, not an invented top-level legacy
`response_item`. Exactly one native user and checkpoint are selected in order.
Independent whole-map oracles require the original user turn/time/classification
and this checkpoint:

```elixir
%{
  "type" => "compaction",
  "id" => actual_native_cmp_id,
  "encrypted_content" => "SYNTHETIC_COMPACTION_CHECKPOINT"
}
```

The source checkpoint has no internal passthrough metadata. Its separate
`replacement_history_metadata` is a harness sidecar and is never copied into a
ResponseItem. The selected user/checkpoint are whole genuine native maps; this
is a subset transfer, not restoration of the entire original context or rollout.

A second owned cold native has an empty loaded list, imports the two original
maps into a distinct idle thread/path, and persists their exact IDs/order once.
The null profile instead submits that same checkpoint with only
`internal_chat_message_metadata_passthrough: null`; native serde omission
produces the same independently prescribed original field-absent map. Every
other field remains exact. This is modified client input, not native-null
production and not a non-null metadata-object claim.

Import adds no inference, turn-start, client interaction or workspace effect.
One explicit followup consumes the complete checkpoint **including the original
cmp_ ID**, both accepted user messages and supplied-history initialization
metadata. There is no new compaction trigger/item or rewritten source history.
Requests are **2 → 2 → 3** per profile. Imported maps remain exact through
followup and close/reap. Source/config/provider bytes and the empty owned
workspace remain unchanged; no inode/timestamp-monitoring claim follows.

## Exact owners and pinned producers

All selected physical nodes are in `ClientRequest.json` under
`/definitions/ResponseItem/oneOf/13`:

| Owners | Evidence and limit |
| --- | --- |
|418/419|Compaction object and exact opaque checkpoint string|
|420|Actual nonempty native cmp_ ID; null-ID behavior remains open|
|424/425|Exact compaction type and literal|
|421/423|Explicit client-null metadata property/branch, normalized to omission|
|422|Not covered by the original two profiles; the later client-object profile below supplies its evidence|

No shared-hash, enclosing union, reference, other variant or full-goal promotion
follows. Pin remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Seventeen full files match the official source archive:

- `core/src/compact_remote_v2.rs:375–504` receives the actual checkpoint and
  builds replacement history; `compact_remote_v2_installation.rs:192–252`
  installs it.
- `core/src/session/mod.rs:4260–4300,4324–4333` assigns missing IDs and persists
  `CompactedItem`; `protocol/src/models.rs:1434` selects the cmp prefix.
- `history/src/rollout_payload.rs:245–299` serializes nested original maps and
  the distinct harness sidecar. No conversion or fabrication is necessary.
- `app-server-protocol/src/protocol/v2/thread.rs:354–363`,
  `app-server/src/request_processors/thread_processor.rs:4788–4803` and
  `core/src/session/mod.rs:1729–1785` decode, fork and persist actual input maps.
- `core/src/session/rollout_reconstruction.rs:492–519` reconstructs the prefix;
  `protocol/src/models.rs:1263–1267` defines optional checkpoint metadata with
  skip-on-None serialization.
- `core/src/client.rs:1006–1028,1092–1096` preserves the opaque checkpoint and
  strips only non-prefixed IDs. `protocol/src/response_item_id.rs:36–39` recognizes
  the generated cmp_ ID, supporting exact request-copy equality.
- The retained common request decoder, live-thread/writer, rollout policy and
  recorder complete the same persistence chain as the earlier
  [history-input qualification](supplied-history-inputs-qualification.md).

## Initial verification and bounds

The owning two-case module passes **2/0**, seed501432, in **4.0 seconds**, log
`/tmp/samgita-v310-compaction-history-501432.log`. Before execution the draft's
optional request-copy ID expectation was strengthened to require the original
whole checkpoint and its ID. Source review confirms that oracle and finds no
functional defect; there is no native semantic repair round.

The existing 60-second owning-case and 20-second event deadlines remain.
Sessions use the existing bounded **256 events / 8 MiB event/message** defaults;
the test's collected events and nested history each have a **1 MiB** bound.
Rollout/request files are bounded to4 MiB,2048 rows,262 KiB per line; nested
history has at most256 items. Requests are capped at3. Existing process guardians,
explicit native close/reap and provider-owner completion/Port checks precede
random-root removal. No timeout increase, gap suppression or blind retry occurs.

Exact final commands/environment/artifacts use `/tmp/samgita-v310-run.py` and
`/tmp/samgita-v310-functional-checks/`. Existing fixtures/defaults stay unchanged.
The opaque synthetic marker establishes retention/transport and consumption;
it does not establish real provider compaction quality, encryption/decryption,
complete state restoration, automatic compaction, other providers/OS/transports,
A11, full compatibility, publication or deployment. Prohibited security/permission/
approval tests and broad/hosted workflows stay unrun; their gates remain open.

The final **43-file matrix passes 83/0 twice**, seeds501432/987654, in
**150.920/149.233 seconds**. Scoped format, warnings-as-errors compile, strict
Credo on493 sources, outside actual-binary consumer **1/0**, twenty-one fixture
ASTs and the **285-source** unchanged-byte guard pass. The prior283 guarded
sources also match committed baseline `177977df9ad354721bf48de61471d046722fd28a`
byte-for-byte; only the new owning test and provider are added.

| Evidence | SHA256 |
| --- | --- |
| Results | `3c7c150d4c2bf042099c3618db82e3a98f87f835a343155691c148fdd9c4d28f` |
| Source guard | `dbd490548934a1595c5b6f607d9afd444e3893181cc6586867435d8f706e6765` |
| Seventeen pinned files and eight exact nodes | `017b5afb3a8b171a602526ed20391c6c3599c4f3694fd768de002559e529e608` |
| Resulting manifest | `500696e07744aaa623400b7a43adebfb97c941d048ba1ef6ffe164e6ae45048e` |

Unique-record patches and final binding prove exactly seven promotions with
unchanged schema identities/planned tests/requirements and metadata object422.
Inventory consistency passes; strict completeness exits **1**. Contracts become
**4,919 implemented / 1,636 missing / 66 blocked**; requirements stay
**462 implemented / 12 missing / 11 blocked**, zero verified. Full-goal, A11,
historical/external/OS and release gates remain incomplete. No publication,
production migration or deployment occurs.

## Client-supplied metadata object

A separate third case captures the same genuine current native checkpoint,
requires its original metadata field to be absent, and clones only that
checkpoint into a client input with this additional field:

```elixir
%{"internal_chat_message_metadata_passthrough" => %{"turn_id" => actual_source_turn}}
```

Deleting the added field must recover the complete original checkpoint; its
native cmp_ ID, opaque checkpoint string and original user map remain exact.
The actual source turn ID is intentionally supplied by this client, not proof
that the original native checkpoint emitted or attested this metadata.

Real `thread/resume.history` creates a distinct idle thread/path and writes both
complete submitted maps exactly once in order, without restamping turn/time
metadata. Equality is required before followup, after followup and after cold
native close/reap. Import performs no inference or work. One deliberate
followup requires the same original checkpoint in the non-OpenAI provider copy,
with only passthrough removed, including its original cmp_ ID and checkpoint
bytes. It must complete with the prescribed assistant answer and no new
compaction or tool work. Requests remain **2 → 2 → 3**.

The existing provider, setup and every original helper remain byte-identical.
Both original named/tagged unchanged/null cases retain their exact assertions;
their shared journey is extracted to avoid duplicating the entire lifecycle.
Their original omission helper remains unchanged and the new object has a
separate whole-map oracle. Existing source/config/provider retention, cleanup,
buffer/file bounds and20s/60s deadlines remain. No native semantic repair or
timeout increase occurs.

The owning module passes **3/0**, seed501432, in **5.6 seconds**,
`/tmp/samgita-v313-compaction-object-501432.log`. Final commands/environment:
`/tmp/samgita-v313-run.py`; artifacts:
`/tmp/samgita-v313-functional-checks/`. Final **44-file matrix passes87/0 twice**,
seeds501432/987654, in **152.514/153.915 seconds**. Scoped format,
warnings-as-errors compile, strict Credo on494 sources, outside actual-binary
consumer **1/0**, twenty-two fixture ASTs and the287-source guard pass.
Sixteen complete production files again match the pinned official archive;
exact physical nodes421/422 independently match their schema hashes. All
prior286 other guarded sources match baseline
`33c40a8307a0f5ae6180460bc7076cfbbc9af8ed` byte-for-byte.

| Evidence | SHA256 |
| --- | --- |
| Results | `67ecfdf568f9f0876a45cef177d5d59a4d423cd9acd40b8539735b93a13587ff` |
| Source guard | `376adc2e2b36310c4e1b5afeb185e5b535ca5e0a1dc5136aacc2c8515a52f32c` |
| Sixteen pinned files and two nodes | `7c84b4ca5ece67cc9cfc235513ca9f523eda41e4de3d132ac103665b43f99e69` |
| Resulting manifest | `87aad04ce75ceadbb31f069eac7e5e29c5df348186df22432c1fff35390a6ec4` |

Final binding proves exactly **one promotion,422**, supplemental property421
coverage, and historical-wording corrections only for418/419/420/423/424/425.
Schema identities, planned tests and all requirements stay unchanged. Inventory
consistency passes; strict completeness exits **1**. Contracts become **4,934
implemented / 1,621 missing / 66 blocked**; requirements stay **462 implemented /
12 missing / 11 blocked**, zero verified. This covers only the selected nonempty
client turn_id object on current unstable raw input. Native-object emission,
arbitrary metadata, sidecar equivalence, full state restoration, provider quality,
external/OS/transports, A11 and the complete goal remain unqualified. Fixed yolo
is setup only. Prohibited security/auth/permission/approval tests and broad/hosted
workflows stay unrun; release gates stay incomplete. No publication or deployment.
