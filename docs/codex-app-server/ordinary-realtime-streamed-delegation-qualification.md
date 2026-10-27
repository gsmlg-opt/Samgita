# Ordinary native V3 streamed delegation

V492 (2026-10-28) qualifies one genuine bounded streaming path with official
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, binary
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
Linux x86_64 musl/stdio. Actual Codex receives the backend delegation, starts
one native backing turn and forwards model text before completion. The finite
loopback peer supplies backend WebSocket and Responses data, never app-server
messages or fabricated history. No client `turn/start` is sent. All earlier
[output-branch checks](ordinary-realtime-output-branches-qualification.md) remain.

The original explicit request keeps V3, WebSocket, Cove, commentary mode,
client-managed handoffs false, response-items false and the original nonempty
response-item prefix. The provider sends exactly six literal SSE events:
response created, empty assistant item added, head delta, tail delta, full
assistant item done and response completed. Its fixed item ID is
`owned-v492-stream-message`; its fixed response ID is
`owned-v492-stream-response`. Independent expected strings are:

```text
head: Owned streamed head λ
tail:  + owned streamed tail 🙂
full: Owned streamed head λ + owned streamed tail 🙂
```

The provider sends only the first three events initially. It withholds the tail,
full item and completion until the real dependency WebSocket receives exactly
the first frame below. That positive receipt records `streamHeadBarrier: true`
before sending the remaining bytes. Completion-only forwarding cannot satisfy
this causal barrier. Final backend output must be exactly these two frames in
order, with no prefix, duplicate full output, session append or completion ACK:

```json
{"type":"delegation.context.append","delegation_item_id":"owned-handoff-1","channel":"commentary","content":[{"type":"input_text","text":"Owned streamed head λ"}]}
{"type":"delegation.context.append","delegation_item_id":"owned-handoff-1","channel":"commentary","content":[{"type":"input_text","text":" + owned streamed tail 🙂"}]}
```

The six original provider events are compared to independent literal maps, and
both base64 SSE segments are parsed back to their exact three-event halves.
Original provider request bytes/base64/length/SHA256 and genuine thread/turn
metadata remain required. The enriched handoff transcript and wrapped model
input are unchanged.

The actual native assistant start must use the same fixed item ID and empty
text. Exactly two original `item/agentMessage/delta` envelopes carry the literal
head and tail, each with actual thread/turn IDs and that same item ID. The full
completed item must independently contain the literal full string. Their exact
maps, original encoded capture, Wire/schema validation, timestamps and
start/delta/delta/completion order are checked. Expected full text is never
derived by concatenating observed deltas. Exactly two native item lifecycles
(user and assistant) complete in the one real turn.

Pinned production chain: `codex-api/src/sse/responses.rs:362–365,482–488` parses
the real added item/deltas; `core/src/session/turn.rs:2934–3020,3120–3149,
2350–2381` retains item identity, emits empty start and exact visible deltas.
The ordinary extension registry has no turn item contributor; its complete
source and app-server extension setup are bound. The assistant/citation/hidden
tag parsers pass each selected plain-text chunk without retaining a possible
markup prefix. These chunks contain no `<` character and exercise no plan,
citation or hidden-tag behavior.

`core/src/session/mod.rs:2477–2498,2573–2603` mirrors primary item/delta/completion
events only once. `core/src/realtime_conversation.rs:500–506,1040–1134` selects
the stated streaming branch, registers an empty item and buffers the head.
The unchanged 200ms timer drains the whole short head; its actual WebSocket
receipt is the provider's release barrier. Once the tail arrives, timed and
final drains share the same buffer lock and sent-byte accounting
(`:330–358,1137–1172,2303–2337`). Either tail drain consumes it completely and
the other cannot duplicate it. Successful stream finish suppresses separate
full-result forwarding. Both chunks stay below the writer's split threshold.
The selected commentary writer maps appends to their original handoff ID.

`app-server/src/bespoke_event_handling.rs:1004–1015` and
`app-server-protocol/src/protocol/event_mapping.rs:364–374` retain original delta
identity/text. Canonical history projection ignores delta/start events, so all
six timeline rows remain required: realtime start, turn start, user item,
assistant item, turn completion, realtime close. Every row binds its original
rollout ordinal. Loaded full history is still the persistence barrier. Repeated
warm/cold history/timeline reads preserve exact items, bytes and peer snapshots,
with no new inference/realtime activity or replayed deltas. Original RPC lists,
requested-stop EOF before teardown, all deadlines/frame/body/count/capture/
journal/rollout/socket/handler caps and owned process/Port/PID/listener cleanup
remain unchanged. No sleeps, extra model request or timeout increase is added.

Only already implemented requirement **230** (`item/agentMessage/delta`) and
physical field owners **3313–3316/5957** gain this branch evidence. Counts and
states remain unchanged. This qualifies selected short plain-text streaming,
not arbitrary/long/multibyte-boundary chunking, truncation, markup/plan/BEM,
multiple/steered delegations, client-managed true, interruption/reconnect,
other versions/transports/providers/platforms, real remote media or full methods.
Client-managed true does not suppress the native backing-turn producer in the
pinned source; its separate output-suppression behavior remains unqualified.

Focused **21/0**, seed501432, retains all twenty earlier cases. Log:
`/tmp/samgita-v492-streamed-delegation-focused.log`, SHA256
`ea5b5bd9086b5f245619edaa688fd74a496363bbefa6a76a3883de00ace26578`.
The final reviewed matrix and complete producer binding follow after execution.

The first reviewed matrix passed both **100-case** seeds and the outside
consumer, then stopped at step **12/14**: strict Credo reported complexity11
(limit9) in the test's expanded `delegation_row`. No subsequent step ran.
The three existing assistant assertions were extracted unchanged into explicit
helper clauses; no expected value, deadline, count or assertion was weakened.
Strict Credo then passed independently. The complete matrix is rerun from its
first step against the corrected source. The initial record remains at
`/tmp/samgita-ordinary-v492/`: `results.json` SHA256
`2b4ebf03539615fe004076379e2383262c7f06ca9395075e2dc440d720f5fb62`,
`source.json` SHA256
`9231b2405782e9e973462c875006828d36f04a0c95bc6f0f7f0429e5045fff30`,
strict Credo log SHA256
`a3327901b2c4ce95a69f2dac349be205334ffde83288c90a26c48da1a003825d`.
The standalone corrected Credo log is `/tmp/samgita-v492-refactor-credo.log`,
SHA256 `bf7d0befcd43f308fc77ee84d2c4132a761557f4fa9ba8322e1ea1d9f6d8d9de`.

The corrected test then passed all fourteen steps at
`/tmp/samgita-ordinary-v492-final/`: `results.json` SHA256
`0aeb02112b4ecf5d25ed19c1c314a1506fbac36284c74efbbd55c0d372020fca`,
`source.json` SHA256
`550982c6af2aab3846b57e3b52fbfa5f65b514f9e7a658927d3d1cd1fa0276ac`.
A separate manifest diff review found that a generated evidence-link hunk had
matched identical context on adjacent owner5956 instead of5957. Its test and
runtime code were unaffected. The two-link correction uses stable owner IDs in
the patch context and a byte-for-byte comparison against the intended complete
manifest. Exactly requirement230 and fields3313–3316/5957 now differ from the
committed baseline; every state is unchanged. The final matrix is rerun with
that corrected manifest, retaining both earlier records above.

The final corrected manifest passes all **14** reviewed steps at
`/tmp/samgita-ordinary-v492-qualified/`: **53 files / 100 ordinary native cases
at both seeds 501432/987654**, the three selected neutral WebSocket cases at
455834/501432/987654, outside consumer **1/0**, warning-strict driver/umbrella
compile, driver/root format, inventory consistency, strict Credo, forced
Dialyzer and assets. All **1,668** before/after source hashes agree. Exact
commands/log hashes are in `results.json`, SHA256
`7ec55c0bf912dcf2ce877517550b6065a7850920a9da73f25936af0df90471d8`;
`source.json` SHA256
`1f3fbfbe64504e547bd933365bdeb1ee023e54269d3c0ecab253dab3eaed47b9`.
Reviewed source fingerprint:
`7c14b025c101570c8b72b538540d2acac89b4802a23643cb6bcb502625dd9f6f`.
The immutable binding checks **45** complete producer files, the selected exact
method/schema nodes and final owning test/fixture/launch/runner bytes:
`/tmp/samgita-v492-streamed-delegation-binding/source.json`, SHA256
`fcf240f235f6256a7dc5cd6e784603ee91f77975736018a690d30667cd0d87f3`.
Counts remain **5,451 implemented / 1,054 missing / 116 blocked** contracts,
**462 implemented / 12 missing / 11 blocked** requirements and zero verified.
Next ordinary units are the source-reviewed native PreCompact/PostCompact and
root-replacement SessionEnd lifecycles; their scratch artifacts are unrun and
earn no compatibility credit yet.

Fixed YOLO is ordinary launch setup. No security, credential, authentication,
authorization, permission or approval tests/audits, broad suite or hosted
workflow is run. A11, unavailable emitters, external/OS/full-goal and release
gates remain incomplete. No real model-service, full-compatibility, database,
publication or deployment claim. Rollback reverts this test/fixture/evidence
unit without touching persisted data.
