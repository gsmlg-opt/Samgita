# Ordinary native V3 delegation output branches

V491 (2026-10-28) adds three independent functional cases for official
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, binary
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
Linux x86_64 musl/stdio. Actual Codex receives a genuine backend delegation and
starts one native backing turn without client `turn/start`. The finite loopback
peer/provider supplies backend frames and model responses, never app-server
messages. This extends the [original delegation profile](ordinary-realtime-delegation-qualification.md)
while retaining all [startup-null checks](ordinary-realtime-startup-null-qualification.md).

Each case changes one parameter from the original V485 commentary request:

| Original request change | Required actual result |
| --- | --- |
| `delegationAckFiller: true` | Exact `session.delegation: {type: "client", ack_filler: true}` in the backend session update; unchanged prefixed commentary result |
| `codexResponseItemPrefix: null` | Original key/null remains on wire; session context receives bare assistant text without the prefix or separator |
| `codexResponsesAsItems: false` | Original nonempty prefix remains in the request but the result targets the handoff as a single bare-text delegation context append |

Only filler=true changes the exact session oracle. Both fixture and native test
independently require the complete session map, including the original
instructions and `audio.output.voice: "cove"`. This establishes literal
forwarding to the dependency wire; the peer generates no filler audio and no
real backend filler behavior is claimed.

The prefix-null case requires exactly:

```json
{"type":"session.context.append","channel":"commentary","content":[{"type":"input_text","text":"Owned bounded assistant result 🙂"}]}
```

The response-items=false case requires exactly:

```json
{"type":"delegation.context.append","delegation_item_id":"owned-handoff-1","channel":"commentary","content":[{"type":"input_text","text":"Owned bounded assistant result 🙂"}]}
```

It permits no session context append, extra prefix or completion ACK. V485's
unchanged true/nonempty-prefix case remains the positive control. Public native
items and persisted assistant text remain the original model text in every
case; a forwarding prefix never changes the native assistant item.

The false branch uses an existing production stream buffer, but this finite
provider emits only `output_item.done`, with no prior added item or text delta.
`core/src/stream_events_utils.rs:368–389` therefore emits ItemStarted containing
the complete short text, then ItemCompleted. `core/src/session/mod.rs:2573–2603`
registers and finishes that item. In `core/src/realtime_conversation.rs`,
`:500–506` selects buffered handoff appends for FramelessBidi with
client-managed handoffs false and response-items false. `:1040–1093` registers
the short initial buffer. Timed drain `:330–345` and final drain `:348–358` both
consume the buffer and increment sent bytes under the same item lock.
Completion `:1137–1172` removes the item, drains any remainder, then checks the
updated sent-byte count before deciding whether a separate handoff output is
needed. Whichever drain wins sends this one whole short append; the other sees
an empty or removed item and cannot duplicate it. The unchanged production
timer needs no sleep, timeout increase or extra fixture control. This does not
qualify actual streamed deltas, arbitrary chunking, truncation or multiple items.

`app-server/.../turn_processor.rs:1255–1267` forwards filler/prefix and the
explicit response-item boolean. `realtime_conversation.rs:688–695,986–993`
retains the item policy and prefix; `:1659–1665` preserves input text when
prefix is None. The frameless writer `methods_frameless_bidi.rs:35–73` retains
the optional filler boolean. The stream path routes through
`realtime_conversation.rs:2450–2470`, its selected commentary writer and
`codex-api/.../methods_common.rs:56–70` to delegation context append with the
original handoff ID. V3's internal V1 session kind exits the separate completion
ACK branch at `:1207–1213`. Complete producer files, including the retained
delegation, model, persistence and timeline chains, are bound in final evidence.

All cases retain exact original request/JSON/Wire/schema/correlation checks,
enriched public handoff transcript and wrapped model input, original body
base64/length/SHA256 and real thread/turn/item IDs. Each requires one model
request, two completed native items, three provider SSE events and all six
canonical timeline rows. Loaded full history remains the persistence barrier.
Repeated warm/cold history and timeline reads preserve snapshots and produce
no new inference or realtime activity. Original RPC lists, requested-stop EOF
before teardown, all frame/body/count/capture/journal/rollout/socket/handler
and deadline caps, plus owned Port/PID/process/listener cleanup are unchanged.

Only already implemented owners **5958/5956/5957** gain branch evidence. Their
nullable schemas use type arrays, so no extra null owner exists. Counts and
states are unchanged; there is no verified promotion. Other values/defaults,
omitted or empty prefix recognition, streaming, multiple/steered delegations,
versions/transports/providers and whole-method completeness remain unverified.

Focused **20/0**, seed501432, retains all seventeen earlier cases. Log:
`/tmp/samgita-v491-delegation-output-focused.log`, SHA256
`6818f08ad076f8e08cda9f7f27e16db421c9e5b0729b86e6e7192e90f1841134`.
Final **53 files / 99 ordinary real-binary cases at both seeds 501432/987654**,
three selected neutral WebSocket cases at each of 455834/501432/987654, outside
consumer **1/0**, warning-strict compile, format, inventory consistency, strict
Credo, forced Dialyzer and assets all pass. All **14** reviewed steps complete;
all **1,668** before/after guarded source hashes agree. Exact commands/logs:
`/tmp/samgita-ordinary-v491/`; `results.json` SHA256
`34b555e771f5af19c8cc0cef72d24cd86dc38659869bc28b93728972d3024374`,
`source.json` SHA256
`963dfe26656760c2b852927c953afddf79d2261a53d307c2d1bbf27d1c7a88ae`.
Reviewed fingerprint:
`fc0fc36cf64f64844382191f9bb8840b25af58baf3a48524f8e7a0145c02f469`.
The final three-node/test/source binding checks **39** complete producer files
against the immutable archive binding:
`/tmp/samgita-v491-output-branches-binding/source.json`, SHA256
`bb0a434984d7e10a4541ae7073e45fb23f58f366515ccff2d5d7f688a91509a4`.
Counts remain **5,451 implemented / 1,054 missing / 116 blocked** contracts and
**462 implemented / 12 missing / 11 blocked** requirements, zero verified. Next
scoped unit is genuine two-chunk realtime forwarding with an actual first-head
receipt barrier before provider completion; source is reviewed, runtime unrun.

Fixed YOLO is ordinary launch setup. No security, credential, authentication,
authorization, permission or approval tests/audits, broad suite or hosted
workflow is run. A11, unavailable emitters, external/OS/full-goal and release
gates remain incomplete. No real model-service, full-compatibility, database,
publication or deployment claim. Rollback reverts this test/fixture/evidence
unit without changing persisted data.
