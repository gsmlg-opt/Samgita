# Ordinary native realtime start and stop

## Configured V3 initial items and requested-stop boundary

V482 (2026-10-28) adds one actual-native ordinary case. The original startup
request omits `version`; the frozen configuration selects V3. The native
started notification reports `v3`, and the independent backend receives one
connection at `/v1/live?model=owned-v432-realtime-model`. Its exact
`session.update` preserves ordered developer, user and assistant initial items,
their role-specific `input_text`/`output_text`, Unicode, LF, CRLF and trailing
whitespace. The peer implements only the backend, never app-server responses.
No model turn, transcription, handoff or generated media is involved.

The first focused run was **8 tests / 1 failure**: startup and the initial-item
mapping passed, but the proposed stop oracle incorrectly expected a
`session.close` message and WebSocket close frame. The actual journal contained
two frames, no error, no close messages and zero remaining connections. The
original failed log is retained at
`/tmp/samgita-v482-initial-items-focused/native-initial-items.log`, SHA256
`9258039ea69df5db263d5a4ab4a1b32aed92cd753c1b3e59705512359b12bda7`.

The complete pinned requested-stop chain explains that observation:

1. `turn_processor.rs:1389–1405` submits `RealtimeConversationClose`;
   `session/handlers.rs:553–555` dispatches it.
2. `realtime_conversation.rs:2022–2057` detaches the conversation;
   `:1270–1288` marks it inactive, cancels and awaits its input task.
3. The input task exits at `:2147–2149`; its wrapper at `:2060–2075` only
   flushes transcript state. Dropping its writer releases the last stream owner.
4. `methods.rs:235–239` aborts the socket pump. The separate graceful
   `RealtimeWebsocketWriter.close` at `:441–467` is **not called** by this path.

The public stop contract at `v2/realtime.rs:350–362` promises no graceful backend
frame sequence. Native requested closure and graceful backend shutdown therefore
remain different outcomes. The corrected finite peer independently records
exactly one empty-frame-boundary EOF while it is still running, before native
or fixture teardown. Before stop it must show an active connection and zero
EOFs; after stop it must show one EOF, no `session.close` and no WebSocket close
frame. Partial frames still fail. Both close counters and the complete journal
remain asserted; no alternative shutdown result, timeout increase, sleep or
removed assertion substitutes for this evidence. Graceful backend shutdown
remains a pinned native limitation, not a passing compatibility claim.

Original correlated start/stop bytes, all six native lifecycle notifications,
the requested reason/ended outcome, exact repeated warm/cold timeline, empty
ordinary turns, immutable rollout/config/workspace and owned process/Port/socket/
thread/listener cleanup remain required. Post-stop queries use the still-ready
native session before its explicit shutdown. The corrected focused run passes
**8/0** in 13.681 command seconds; its log SHA256 is
`76964bc8a6d9cb55db415e4c5f58d45505efd900cadb2438ea9f061557ba6509`.

Only physical owners **644/645** gain scoped implemented evidence for initial
item `role` and `text`. The nine complete producer files match the unchanged
archive binding, and both canonical nodes match the immutable native export.
The source/test/failure binding is
`/tmp/samgita-v482-initial-items-binding/source.json`, SHA256
`e774c3fd4376650f9dcafe0bfcbaf02a9cf25978f6e170c4b7c86404b8a4a3ad`.
An initial helper used compact JSON instead of the inventory's pretty canonical
encoding and stopped before writing an artifact; correcting that helper changed
no source, schema node or native assertion.

Final **84 ordinary cases at both 501432/987654**, three selected WebSocket
cases at each of 455834/501432/987654, outside consumer **1/0**, warning-strict
compile, format, inventory consistency, strict Credo, forced Dialyzer and assets
pass: all **14** reviewed steps and **1,668** identical before/after hashes.
Exact commands and logs: `/tmp/samgita-ordinary-v482/`; `results.json` SHA256
`22c4b1efa2472bb403fc9cbe68d452286a700ba687a81c8cdec0e2efd1219cf6`,
`source.json` SHA256
`60a4de2dabe32d4fb6245154ecc5fd7928319068a2373b4a511426c3e9a97d76`.
Reviewed fingerprint:
`60044dbdfb5057154ad2871166811c0afda6188d92f8fe50bf709cabe0e7b2c0`.
Counts are
**5,417 implemented / 1,088 missing / 116 blocked** contracts and unchanged
**462 implemented / 12 missing / 11 blocked** requirements, zero verified.
Fixed YOLO is setup only. Prohibited tests/audits, broad/hosted suites, A11,
unavailable emitters/external/OS/full-goal and release gates remain incomplete.
Rollback reverts this test/fixture/metadata unit without changing runtime code,
platform data or histories. Continue ordinary native marketplace/review
envelopes and substantive realtime instruction effects; startup alone cannot
qualify instruction injection or handoff fields.

## Current builtin voices and speech qualification

V481 (2026-10-28) extends the text/PCM profile below with one ordinary native
case. Two `thread/realtime/listVoices` calls return independently prescribed
complete V1/V2/V3 lists, order and defaults, before any loaded/persisted thread,
workspace effect or backend connection exists. Full original outgoing bytes,
distinct string request IDs and correlated native responses remain required.
The test explicitly uses the returned `defaultV2` value `marin` for a V2 audio
session and independently observes it in the actual backend session.update.
This qualifies explicit use of a reported default, not omitted-voice fallback
or synthesis with every advertised voice.

Empty and whitespace-only `appendSpeech` inputs receive correlated submission
ACKs and produce no backend frames. One nonblank Unicode input preserves its
LF/trailing space and produces exactly two independently prescribed frames:

```json
{"type":"conversation.item.create","item":{"type":"message","role":"user","content":[{"type":"input_text","text":"[BACKEND] Owned ordinary speech λ🙂\nkeep trailing space "}]}}
{"type":"response.create"}
```

Both frames must be observed before requested stop. The final closed peer
journal detects delayed blank dispatch and duplicates as well. The peer emits
only session readiness, no generated speech, audio or model response. Thus a
native RPC result, backend request, audio production and audible playback
remain separate boundaries. Complete original lifecycle notifications, repeated
warm/cold start/closed timeline, empty ordinary turns, byte-identical rollout/
peer journal/config/workspace and existing owned cleanup remain required.
All previous cases/assertions and frame/byte/journey/RPC limits are retained.

Exactly six missing physical ClientRequest owners gain scoped implemented
evidence: **780/781/784** (`/oneOf/105`, appendSpeech) and **795/796/799**
(`/oneOf/108`, listVoices), each the object, ID property and params reference.
No other RequestId alternative, parameter branch, referenced type, capability,
transport, OS, voice or whole-method verification is inferred.

The exact native builtin implementation is
`protocol/src/protocol.rs:349–404`; `turn_processor.rs:331–340` returns it without
loading a thread, while `:1364–1386` queues speech. The nonblank/blank behavior,
V2 `[BACKEND] ` prefix, ordered message and response scheduling are in
`realtime_conversation.rs:1171–1194,1648–1658,2509–2520`. Role conversion is in
`methods_v2.rs:39–64`. All five complete producer sources match the immutable
archive binding below. An initial binding helper assumed a separate queue file
and searched the wrong type name; it stopped without writing an artifact.
The actual `RealtimeResponseCreateQueue` is in the already-bound
`realtime_conversation.rs`; no source identity or native assertion changes.
The corrected six-node/source/test binding is
`/tmp/samgita-v481-realtime-speech-binding-final/source.json`, SHA256
`5e00acccd9ba28d1b673568e7ed0bb88d352faac781ae65666b35b949e664370`.

The initial focused **7/0** and the strengthened blank-input focused **7/0**
pass. Final **83 ordinary cases at seeds 501432/987654**, three selected
WebSocket cases at each of 455834/501432/987654, outside consumer **1/0**,
warning-strict compile, format, inventory consistency, strict Credo, forced
Dialyzer and assets pass: all **14** steps, all **1,668** before/after hashes
identical. Exact commands/logs: `/tmp/samgita-ordinary-v481/`;
`results.json` SHA256
`e6e4eb11a562df4b8d735f74f5d94de492e5e0d3186e33703f5bc25f53edccb4`,
`source.json` SHA256
`a64908d144356f84c895cd6b94f8ac4c59d2f36421446b7b65291d19972c6717`.
Reviewed fingerprint:
`4be4417fad8abfe7c5b083a8d087e23932256a99d41c282a1be843fe1809a9f1`.

Counts are **5,415 implemented / 1,090 missing / 116 blocked** contracts,
unchanged **462 implemented / 12 missing / 11 blocked** requirements, zero
verified. No prohibited security/permission/approval/authentication/credential
test or audit, broad suite or hosted workflow runs. Full compatibility, A11,
unavailable emitters/external/OS and release gates remain incomplete; no
publication, deployment, production migration or sibling edit. Rollback reverts
this scoped test/fixture/metadata commit without changing platform data or
production driver code. V3 initial items and configured fallback are qualified
separately above; that investigation corrects the proposed explicit
`session.close` oracle using the actual requested-stop caller chain.

## Current text and PCM input qualification

V480 (2026-10-28) adds one ordinary actual-native case to the existing five-case
module. The official binary/source pin below is unchanged. Fixed YOLO settings
are launch setup, with no policy or permission assertions. The finite local
peer implements only the realtime backend; Codex itself handles every
app-server request and emits the original notifications.

After native V2 start and independently observed peer readiness, three public
`appendText` requests send developer, user and assistant text, followed by one
`appendAudio` request. Each complete outgoing envelope and original correlated
empty response is retained and validated. The next input or requested stop
cannot begin until the peer journal contains the exact independently prescribed
backend effect. This distinguishes submission ACK from actual input delivery
and detects extra, reordered or duplicated backend frames.

The developer and user messages use `input_text`; only the user text gains the
literal `[USER] ` prefix. Assistant text uses `output_text`. Unicode, trailing
whitespace, LF and CRLF remain exact. PCM base64 data arrives in exactly one
`input_audio_buffer.append`. Sample rate, channel count, sample count and item ID
are accepted and retained in the original app-server request; the pinned V2
writer deliberately sends only audio data to the backend. This does not prove
resampling, playback, transcription or generated audio.

The peer produces no transcript or model output. The complete selected native
lifecycle remains the six start/close notifications. Repeated warm and cold
timeline reads contain exactly the original start and ended facts, while the
ordinary turn list stays empty. The rollout, peer journal, workspace and frozen
inputs remain byte-identical across the cold reads and checked owned cleanup.
Original capture/frame limits, twenty-second journey deadline, individual
five-second bounds and sixty-second case timeout are unchanged.

Scoped implementation evidence is attached to **36** independently hash-bound
physical owners, rather than inherited by equal-hash siblings:

| ClientRequest owners | Qualified scope |
| --- | --- |
| 127–129, 639–643, 770/771/774, 775/776/779 | Three text roles, audio input metadata and exact append request envelopes |
| 303, 305/306, 649–652, 765/769, 785/789, 790 | Existing literal V2, text/audio selections, local V1 SDP transport, start/stop and persisted timeline request envelopes |
| 810–814 | Existing original `model/list` request and independent static catalog preserved across two reads in each of two fresh processes |
| 944–948 | Existing original MCP event-stream start request, actual subscription activation, released event and stop/EOF |

The last two rows reuse the unchanged substantive native catalog/MCP tests,
both rerun in this matrix. String request IDs do not qualify unobserved ID
alternatives. No whole method, parameter union, transport or deployment profile
inherits complete verification. The separate
[producer investigation](native-projection-boundaries.md) annotates thirteen
other owners while retaining their missing state, empty tests and empty
transport coverage; private analytics and supplied history provide no substitute
for native production evidence.

Producer references include `turn_processor.rs:1309–1360`,
`realtime_conversation.rs:858–908,1648–1653,2292–2301,2740–2749`,
`methods_v2.rs:39–64`, `methods.rs:345–370` and
`realtime_history.rs:128–149`, all at the immutable source revision below.
The seven complete producer sources and all 36 canonical nodes are bound by
`/tmp/samgita-v480-realtime-inputs-binding/source.json`, SHA256
`c68381f8c4f7b9d0bb51cb8dc0f172029324d2424e6ccd1fe7fbfc1a88b5a91b`.
Its parent binding archive-matches all 5,259 Rust sources.

Focused native **6/0** passes. The final reviewed matrix passes **82 ordinary
cases at each of seeds 501432/987654**, the same three selected WebSocket cases
at each of 455834/501432/987654, the isolated outside consumer **1/0**, compile
with warnings as errors, format, inventory consistency, strict Credo, forced
Dialyzer and assets. All **14** steps pass, with **1,668** identical before/after
source hashes. Exact commands/logs: `/tmp/samgita-ordinary-v480/`;
`results.json` SHA256
`adaf6a45167a991fa398f15ee76acea95bab7d736ac0c5d40af5ab3a9e54d5b8`,
`source.json` SHA256
`13af708d9e3ccf2326b8dd6bc51c3d57bff283fc4172245520235354ed42576d`.
Reviewed fingerprint:
`d4a0e0c1eb29e82b9ff946d2fd346fc401bbd45ddf5b06388b630100fc2838a0`.

Counts are **5,409 implemented / 1,096 missing / 116 blocked** contracts and
unchanged **462 implemented / 12 missing / 11 blocked** requirements, zero
verified. No security, authentication, authorization, credential, permission or
approval test/audit, broad suite or hosted workflow runs. Both retained
Plug.Crypto locks remain 2.2.1; no audit is rerun. A11, unavailable emitters,
external/OS success, full compatibility and release gates remain incomplete.
No publication, deployment, production migration or sibling-service edit.
Continue the source-confirmed builtin voice catalog and ordinary appendSpeech
two-frame backend effect; no live media success may be inferred.

## Initial start/stop checkpoint

V432 is delivered after the V433 evidence-only unit on `main`
`9d0a096c3cd76c37afbebc7d6655bb997223b6bd`. Its actual execution base is
`2ed7731284ad05380de24db9c4acb5a04365da77`; all414final executable-source
hashes retain the tested bytes. Only14distinct physical owners become scoped
implemented:646–648(WebSocket transport),2680–2682(started item),2694–2699
(closed item and shared IDs),6392/6406(the separate timeline alternatives).
Canonical identities/hashes remain in the manifest and bound source artifact.

The [new dedicated ordinary test][test] launches the official pinned native
binary directly with fixed YOLO. Its [new finite loopback peer][peer] implements
only HTTP upgrade/WebSocket framing, one session.update acknowledgement, ping/
pong and close. It never implements app-server methods or emits model output.
Only functional paths/messages/counters are journaled; HTTP headers are not
retained. The historical mixed realtime module and header-journaling fixture
are neither imported nor run. Inert local provider configuration is setup, with
no credential, policy or permission assertion/variant.

One paginated thread receives exactly one explicit V2 WebSocket start with the
caller session `owned-v432-realtime-session`, prescribed model/prompt, text
output, startup context/tail flush false and client-managed handoffs. The test
requires the actual peer connection at its exact model route and one native
session.update with the prescribed prompt/output. Both that peer readiness and
native started observations precede one explicit public stop. Each RPC retains
the complete original request and correlated native `{}` response; the ACK is
separate from processing completion.

Complete independent native item facts are:

```text
S = {id:A,realtimeSessionId:"owned-v432-realtime-session",type:"realtimeSessionStarted"}
C = {id:B,realtimeSessionId:"owned-v432-realtime-session",type:"realtimeSessionClosed",outcome:"ended"}
```

A/B must be distinct native UUIDv7 IDs. Each exact S/C object appears once in
item/started and once in item/completed. The selected six-notice order is S
started/completed, realtime/started, C started/completed, realtime/closed. Full
params require the actual thread, caller session and version v2, with final
reason requested. Every original envelope has the prescribed method/params and
bounded native emittedAtMs, current generation and increasing unique sequence.
Raw JSON is captured before Session decoding and compared with the complete
decoded maps and canonical schema. Expected type/outcome/session fields never
come from the observed notification. The peer's different backend session ID
does not replace the caller-owned identity.

A public native thread/read forms the store barrier. Two timeline/list reads
must return exactly S then C, complete realtime rows with independently checked
increasing nonnegative positions, nextCursor:null and
activeRealtimeSessionAtPageStart:null. The entire page is checked against its
own schema and original correlated response, separately from notification
ownership. Final bounded drain preserves the exact six events. No Responses
request, ordinary turn/item execution, transcript input, duplicate connection
or implicit reconnect is allowed. Frozen config/catalog/script and the empty
workspace remain unchanged.

Requested stop closes the real peer connection. Cleanup closes native/peer
owners and Ports, verifies completion and vanished owned PIDs, and checks the
peer's actual zero sockets/handler threads, closed listener and joined server
thread. Sockets close before joins, including error cleanup. The peer bounds
concurrent handlers at2 and admitted requests at4 so unexpected HTTP during an
open WS remains observable; the successful profile requires one request.
Limits remain128native frames/events,64KiB inbound/8KiB outbound,2MiB capture;
peer64KiBframes/32frames/2MiBjournal/8KiBupgrade. Startup/RPC/collectors5s,
active journey20s and case60s. No deadline or assertion was relaxed.

Official pin remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Fourteen whole sources match the immutable archive. Genuine V2 session startup
is in `realtime_conversation.rs:1371–1387,1748–1762`; requested detach at2036–
2057 emits closure. `realtime_history.rs:181–194,281–296` creates native start/
ended facts. `session/realtime_history.rs:33–52` durably appends them before
native event delivery; `bespoke_event_handling.rs:467–499` preserves public
items. `thread_history/realtime.rs:137–174,242–247` reads the persisted rows.
Source/canonical-node evidence `/tmp/samgita-v432-binding/source.json`, SHA256
`ebb13c48c47acdef21bb6ad988005bd8d3c986090d10962d52ca7be5e519b94e`.

Focused actual-native **1/0** and the29-module selection **47/0** twice at
501432/987654 pass,78.248/79.198 command seconds. Eleven Python syntax checks,
scoped format, driver compile with warnings as errors, root strict Credo and
inventory consistency pass. All414sources stay stable; all412prior paths remain
exact and these two files are new. Exact commands/logs/source guard:
`/tmp/samgita-v432-functional-checks/final/{results,source}.json`, SHA256
`183ff93270f20986c643f1fb9e5717f21b8ed7789fb490166e60c4f41d81c531` /
`dde2fd49b2eb72676e895a184a7d0e2e39e18d4fd6920c1f2272500347425964`.
Test/peer SHA256:
`c1d08e9b35ad75f084a6d7f9d6bd72161d4dd3dab2439d004c120ccd5f21b91c` /
`738e607671c129efc35e26a2d5304eef7cd9d9d0d60df74d23e8d19c91941315`.
Binder `/tmp/samgita-v432-bind.py`; binding
`/tmp/samgita-v432-binding/evidence.json`, SHA256
`baee77dd481c5e678344c1460ca4be8525341b4c4c80ba3966911defb31a2482`.

Contracts become **5,214 implemented /1,341 missing /66 blocked**; requirements
remain **462 implemented /12 missing /11 blocked**, zero verified. Transcript,
failed closure, WebRTC/existingCall, media/remote backends and other transports
are unqualified. Prohibited security/credential/authentication/authorization/
permission/approval tests and audits, broad suites and hosted workflows remain
unrun. A11, unavailable legacy/external/platform/full-goal/release gates remain
incomplete. Push suppresses CI; no publication/deployment. Rollback removes the
two files and14bindings, retaining runtime/history. Continue the bounded shell
output-delta original-envelope profile.

[test]: ../../apps/samgita_codex_driver/test/native_realtime_start_stop_test.exs
[peer]: ../../scripts/codex/ordinary_realtime_fixture.py
