# Ordinary native request envelopes

Ten physical `ClientRequest.json` owners gain selected implementation evidence
from the already passing actual-native functional matrix. This mapping adds
no test, runtime or fixture change. It uses immutable Codex `rust-v0.163.0`,
source `83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Owned native launches retain fixed yolo; no security or permission profile
is introduced.

| Exact method | Physical owners | Independently observed contract |
| --- | --- | --- |
| `thread/timeline/list` | 791–794 | Unique caller string ID, literal method/discriminator and complete explicit page params |
| `thread/compact/start` | 1269–1272 | Unique caller string ID, literal method/discriminator and exact thread params |
| `thread/turns/list` | 1404 | Caller string ID retained through exact wire capture and native response |
| `thread/items/list` | 1409 | Caller string ID retained through exact wire capture and native response |

Other fields on the two listing envelopes already have implementation evidence
and are unchanged. The separate exact method `thread/sections/list` does not
exist in this pin; no synthetic alias is introduced.

## Timeline

The [timeline journey](timeline-position-values-qualification.md) captures
the actual Stdio transport's encoded requests and requires complete envelope
equality with independently constructed IDs, method and query params. Every
native result must retain that exact ID. Real canonical rollout ordinals,
genuine opaque continuation cursors and identical cold page reads establish
dispatch and effects, rather than treating a local encode/decode as evidence.
Original rollout/configuration/catalog/provider bytes and inference budgets
remain intact. Its failed/recovered history case also remains in the matrix.

## Compaction

The [local compaction journey](native-runtime-values-qualification.md) sends
exactly `thread/compact/start` with `{"threadId": <native thread ID>}` through
the direct `Session.request_native` interface. Its helper requires the native
response ID to equal the independently generated string ID. This profile does
not have an additional transport capture, and this continuation adds none.

The empty acknowledgement is distinct from actual completion. The test waits
for real compaction's second provider request, a distinct native turn, paired
contextCompaction items and terminal completion. Independent UUID/time checks,
seed user/assistant preservation and final warm/first-cold selective history
prove the native effect. The stock executable writes every event/history row;
no local app-server peer supplies a successful response.

## Listing IDs

The [turn listing](turn-list-null-values-qualification.md) and
[item anchors](item-anchor-values-qualification.md) each capture exact encoded
requests and require the matching raw native result ID. The former performs
twelve list requests over three completed turns, covering omitted/null/explicit
paging and genuine continuation cursors. The latter performs nineteen list
requests over six independently prescribed entries, checking page rows/order,
opaque cursors and anchor exclusion. History/input bytes, exact inference
budgets, empty workspaces and owned cleanup remain enforced.

## Provenance, validation and limits

The pinned method/params registrations are at
[common.rs:734–738](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L734),
[869–879](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L869)
and [1110–1115](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L1110).
The native dispatcher preserves the caller ID at
[message_processor.rs:640–643](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/message_processor.rs#L640)
and [1897–1901](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/message_processor.rs#L1897).
Five complete registration/dispatch/type files byte-match the immutable source
archive; all ten exact physical nodes match pinned schema provenance.

Base: `9b0d068c`. The final **38-file, 65/0 twice** matrix is reused from
`/tmp/samgita-v298-functional-checks/functional/`, with compile/format, strict
Credo, outside actual-binary consumer **1/0**, fourteen fixture ASTs and all
eight commands passing. It is not repeated: all **274** guarded sources match
both current bytes and their committed blobs at the base. New offline
inventory, unique-record patch and final owner/source binding checks pass.
Evidence is in `/tmp/samgita-v299-functional-checks/`. The reused results and
source-guard SHA256 values are
`4d2948f27b0062262a17c1579f139fb9086d62a49d54b2c5901da676dc07c7d2` /
`f62873df86e827b286a36d3e46f2c1459fa5abba2482a6a7d8458d51a331c352`.

Exactly ten records change: **4,850 implemented / 1,712 missing / 59 blocked**
contracts; requirements remain **462 implemented / 12 missing / 11 blocked**,
zero verified. Strict completeness remains exit **1**. Numeric RequestId
alternatives, enclosing branches790/1268/1403/1408, referenced definitions,
aliases and other exports/OS/transports remain outside this mapping. Existing
required tests/gates are preserved. Security/permission tests, audits and broad/
hosted workflows stay unrun; A11, unresolved legacy, unavailable external/OS,
full compatibility and release remain incomplete. No publication/deployment.
