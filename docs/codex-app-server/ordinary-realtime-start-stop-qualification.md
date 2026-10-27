# Ordinary native realtime start and stop

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
