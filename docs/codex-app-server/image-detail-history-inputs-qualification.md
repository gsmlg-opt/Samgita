# Explicit-null image-detail history inputs

Two real pinned-native profiles qualify deliberate current client-null image
detail inputs from genuine native user and dynamic-tool producers. Neither
establishes native-null emission, upload, file retrieval, external visual
reasoning or arbitrary image fidelity.

## Source, import and consuming followup

`apps/samgita_codex_driver/test/native_supplied_null_image_detail_history_test.exs`
uses `scripts/codex/supplied_null_image_detail_history_fixture.py`. Source replies
delegate unchanged to the original provider. Only the explicit cold followup gets
the new fixed answer. The fixture supplies model data, never app-server frames,
native IDs, raw/history records or envelope sidecars.

The user profile sends real text plus an image/fileId with detail:low. After
completed source turn and native close/reap, it captures whole genuine user and
assistant maps. Independent oracles fix actual native IDs, source turn, bounded
creation time, content/classification/order and the complete source assistant.
The file reference is input; successful retrieval is not inferred. Requests
stay **1 → 1 → 2** across source, import and explicit followup.

The tool profile registers one ordinary dynamic lookup and receives exactly one
real callback on the expected source thread/turn. One public reply supplies text
and a2×2 PNG. Native conversion creates structured FunctionCallOutput with
detail:high, generated fco_ ID and source turn/time metadata. Captured history
keeps the complete matched fc_/fco_ call/output pair, user and assistant in order.
Source continuation requires the entire original high-detail pair. The single
owned local effect remains once. Requests stay **2 → 2 → 3**.

Each profile changes exactly the selected nested detail to present client null
on a clone only. Independent expected durable maps omit exactly that key; every
other map, ID, metadata field, content item and order remains unchanged. A
distinct cold native starts empty, imports into a new idle thread/path and
persists every selected map once. Import creates no turn, callback or inference.
Cold history registers no dynamic tool and sends no new callback reply.

One explicit followup consumes the whole selected maps in order. The exact
file_id or tiny PNG image_url survives with detail omitted, rather than
null/high/auto. Request metadata identifies supplied_history. Source/followup
require singleton literal assistant answers correlated by thread, turn and item
type, plus exactly one completed turn. Source rollout, config, model catalog and
both scripts remain byte-identical through cold shutdown.

Durable maps and provider copies have separate complete oracles. Durable
originals retain all IDs/metadata. For this custom provider, only outbound copies
lose top-level passthrough and IDs failing the actual nonempty split-once
underscore predicate. Native msg_/fc_/fco_ IDs remain; fixture-message-1/-2 loses
its ID outbound. The initial source report's blanket provider-ID-retention
wording was corrected against pinned source before integration. No runtime
assertion or deadline is weakened; no native failure or repair is observed.

## Exact owners and pinned paths

Only these physical ClientRequest null branches gain implemented evidence:

| Owner | Pointer |
| --- | --- |
|114|/definitions/ContentItem/oneOf/1/properties/detail/anyOf/1|
|198|/definitions/FunctionCallOutputContentItem/oneOf/1/properties/detail/anyOf/1|

Pin: rust-v0.163.0, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Sixteen complete official files match the immutable archive; both physical nodes
independently match their canonical hashes. No sibling, alias, shared hash or
enclosing method gains evidence.

`protocol/src/models.rs:884–889,2216–2221` defines optional detail with omission
when absent. The genuine public dynamic InputImage conversion at2266–2284
supplies high; the official current dynamic-tool test at
`app-server/tests/suite/v2/dynamic_tools.rs:694–805` exercises that producer.
No synthetic raw output replaces the public callback.

`core/src/session/mod.rs:1831–1856` prepares replay in memory without rewriting
persisted records, using DetailBased and InlineAttachmentStore.
`core/src/image_preparation.rs:358–360,404–426` preserves file references and
leaves optional detail None in this mode. The image-capable private catalog
disables Responses Lite/original support and unified budget as fixed functional
setup. The2×2 PNG fits high-image limits;
`utils/image/src/lib.rs:196–205,308–317,345–360` retains the original preservable
bytes without resize. Independent PNG checks cover bytes, CRCs, dimensions and
decompressed pixels. Resized/other-format images remain unqualified.

`core/src/client.rs:1007–1025,1092–1096` explains the separate provider-copy
transformations; `protocol/src/response_item_id.rs:36–39` defines the prefix
predicate. Those outbound rules do not normalize durable originals.

## Final functional checks

Owning module: **2/0**, seed501432,3.7seconds, log
`/tmp/samgita-v317-null-image-history-501432.log`.
Commands/environment: `/tmp/samgita-v317-run.py`; artifacts:
`/tmp/samgita-v317-functional-checks/functional/`. The reviewed **48-file matrix
passes95/0 twice**, seeds501432/987654, in **174.118/173.751 seconds**. Scoped
format, warnings-as-errors compile, strict Credo on498 sources, outside
actual-binary consumer **1/0**,27 fixture ASTs and the **296-source** guard pass.
All prior294 sources match baseline
`f0e17109c6d4103ab93c6dd81bfc64f5952d0491` byte-for-byte. Only the new native
module and dedicated provider subclass are added.

| Evidence | SHA256 |
| --- | --- |
| Results | `aeab8f655d54dedab156d197bf5815abf657b04d3250b1b4f5a2a5ae446b963c` |
| Source guard | `31414b09bedaba8e02008f3123bc97c89e6b474321a3c4137c05585e9edecc0f` |
| Sixteen pinned files and two nodes | `d8fb6d4b72c2a256a9376b5eb76efe37c1ee9d3aed8b553a76035986f06ef75b` |
| Resulting manifest | `4ffc5eb47236eb2416d5146fb72063b6ad2b501287826ff724d21e02a3409705` |

Session256event/8MiB defaults,256event/1MiB local capture/import,4MiB files,
2048JSONL rows/262KiB rows and20s lifecycle/10s callback/60s case bounds remain.
Owned native close/reap, session guardian and provider owner/completion/Port
checks precede root removal. Fixed yolo is setup, not policy qualification.

Final binding proves exactly two promotions with schema identities/planned
tests, every other contract and all requirements unchanged. Inventory consistency
passes; strict completeness exits **1**. Contracts become **4,949 implemented /
1,606 missing / 66 blocked**; requirements remain **462 implemented / 12 missing /
11 blocked**, zero verified. Full restoration, external/OS/transports, A11 and
full-goal/release remain incomplete. Prohibited security/auth/permission/approval
tests and broad/hosted workflows stay unrun. No publication or deployment occurs.
