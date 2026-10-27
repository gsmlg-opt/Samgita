# Ordinary native realtime start and stop

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
