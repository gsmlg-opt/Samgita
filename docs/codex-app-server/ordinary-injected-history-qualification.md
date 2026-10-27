# Native idle history injection and cold continuation

V508 follows `01ec748` on the existing `main`. Official target remains
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The dedicated ordinary functional module reuses ModelFixture unchanged. Stock
Codex owns every app-server frame and persisted record; the peer supplies only
one deterministic model response. No driver or platform runtime changes.

## ACK, actual durable records and exact cold model input

`native_injected_history_lifecycle_test.exs` creates one persistent idle native
thread and sends exactly one `thread/inject_items` request. Two independently
authored assistant output-text messages carry distinct prefixed Unicode IDs,
different literal content and an explicit source turn ID. The full original
request, string correlation ID, actual native empty result, codec round trip
and exact request/response schemas are checked.

Immediately after ACK, the test reads the real rollout path returned by
`thread/start`, with no intervening read/flush RPC. Both complete prepared
payloads must match the independent expected maps exactly, appear once and
remain ordered. There must be zero model requests and no observed turn start
or completion. Thus the later cold read does not create the initial durability
observation, and successful acknowledgement alone is insufficient.

The warm Session, owner, Port and actual native PID must finish before the
second process starts. Cold requires distinct native/Session identities,
explicit resume of the original thread/path and unchanged original durable
records, still without inference. Exactly one explicit user turn then produces
one actual model request and the fixture's fixed answer/completed turn.

That real provider input must contain both full authored messages exactly once
with their original IDs, content and ordering before the complete new user
message. The provider projection independently removes the entire internal
metadata object. Prefixed message IDs survive this projection; generated user
IDs use `msg_<UUIDv7>` and are checked separately from its complete remaining
literal payload. This does not claim arbitrary unprefixed IDs survive native
provider serialization. The original durable rows, including their timestamps
and metadata, remain identical and unduplicated after resume, turn completion
and final shutdown. The whole warm raw-capture prefix stays unchanged.

## Source boundaries and corrected full oracle

The immutable [turn processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/turn_processor.rs#L994-L1022)
awaits the thread injection/checkpoint path. `core/src/session/inject.rs:74–103`
records idle items immediately; active-turn injection queues them. This profile
qualifies only idle durability. Neither the ACK nor this test establishes
active-queue durability or cancellation semantics.

Preparation preserves nonempty IDs and supplies missing ones, persists the
prepared history and awaits the ThreadPreparation flush barrier. The initial
source review missed a text-only preparation step. The first native run fails
at complete immediate disk equality because Codex adds
`content_item_kinds: ["unknown"]` to each message's existing metadata.
Original IDs, text, order and source turn ID remain intact.

The fixed source explains the exact value:

- [Image preparation](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/image_preparation.rs#L132-L157)
  annotates all Message content, including unchanged output text.
- [Annotated content](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/context-fragments/src/annotated_content.rs#L58-L95)
  pairs missing content kinds with literal `unknown` and writes them into the
  existing metadata while preserving the supplied turn ID.
- [Provider preparation](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/client.rs#L1092-L1102)
  applies provider projection separately from durable storage.

The correction keeps the input literals unchanged and adds a separate full
durable expected map with that exact literal field. It retains complete `===`
equality; no subset match or value learned from observed rows is used. The
provider oracle still removes the whole metadata object. No timeout, assertion,
fixture or stock behavior changes.

Original failed log: `/tmp/samgita-v508-focus-501432.log`, SHA256
`3556317fee69bc131c461f722362881d73819259e792ca7ea7de2a3bd1cedf3b`.
Source evidence: `/tmp/samgita-v508-source-evidence.json`, SHA256
`7cb075f898bfeaff14e9342cbe29d1ec7fc7b76ec263387451c4c2050a728238`;
review correction: `/tmp/samgita-v508-review-correction-evidence.json`, SHA256
`b5a4c2b695eeea83fcac7f9c8c6dc3fce1ce504ad3e35883a4705912dd4528db`.
The additional annotation sources match the same immutable archive.

## Qualification, limits and rollback

Corrected actual-native focus passes **1/0** at seeds501432/987654 in1.8/2.0s;
strict Credo passes across594 files. Logs are
`/tmp/samgita-v508-corrected-focus-501432.log` and
`/tmp/samgita-v508-corrected-focus-987654-credo.log`.

Final combined-source qualification passes all fourteen reviewed checks in
`/tmp/samgita-ordinary-v508-qualified`: **62 files / 121 actual-native cases**
at both seeds501432/987654 (207.990s/209.894s), three selected WebSocket cases
at seeds455834/501432/987654, outside consumer **1/0**, warning-free driver and
umbrella compilation, scoped/root formatting, strict Credo, Dialyzer and assets.
All1,681 guarded source hashes remain identical before/after and match the
current files. The reviewed fingerprint is
`49ee05cb21390257dc8e296fdad0db2802279c2eb725659e6eaa0221c7409aed`.

The source binding independently rechecks16 complete archive-equal producer
files, all five physical schema subtree hashes, retained helpers and fixture,
the pinned binary, original failed log and corrected logs. Evidence:

| Artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-v508-qualified/results.json` | `ff94b3a331b9f24d7f3eb6ff8e05606e583ceb280caa8d2e35edbe4b947c8411` |
| `/tmp/samgita-ordinary-v508-qualified/source.json` | `20d39b3d2b600c0c15333e76b13e02a2151bf76c22f4c63e1a36251561125e66` |
| `/tmp/samgita-v508-final-binding/source.json` | `56a9c1bfebcd1b9f8c486667a8602e258031d15cffd1df79e11e2ed255136dee` |

These checks execute only the reviewed ordinary selection. Required broad,
security/permission and hosted gates remain unrun under the current restriction.

Only five precise ClientRequest owners1418–1422 gain scoped implemented
evidence: injection wrapper, original string ID, method property/literal and
params reference. Their canonical hashes remain separate. No raw-item union,
arbitrary-ID/field variant, active lifecycle or other transport inherits credit.
Existing method/response records gain only supplemental idle/cold evidence.
Contracts are **5,482 implemented / 1,009 missing / 130 blocked**; requirements
stay **462 implemented / 12 missing / 11 blocked**, with zero verified in both.

Limits stay30s per case,5s per request/terminal wait,128 captured frames and
1MiB aggregate,4KiB outbound/64KiB inbound,1MiB/128 rollout rows. Event
accumulation and actual request/response inventories are bounded; all fixture,
config and code inputs stay frozen. Existing owned shutdown proofs remain.
No mutation retry, private Session-state manipulation or manufactured history.

No security, credential, authentication, authorization, permission or approval
test/audit, broad suite or hosted workflow runs. Fixed yolo is ordinary setup.
Prohibited checks, A11, unavailable emitter/external/OS success, full compatibility
and release stay incomplete; nothing becomes verified. Rollback removes the
test/evidence extension without modifying persisted platform records. No
publication, deployment, production migration or live credential change occurs.
