# Native realtime SDP and V1/V3 control paths

Source pin: Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`. The immutable Linux musl binary SHA256
is `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

Eight actual-binary cases pass at seeds `501432` and `987654`, 12.3 seconds each
on final source. Selected `implemented` evidence is scoped below; full behavior
and real media/provider/platform acceptance remain incomplete.
Existing V2 lifecycle evidence remains in `native_realtime_lifecycle_profile.exs`;
this profile adds distinct V1/V3 dependency exchanges and genuine native SDP.

## Source-backed production path

All source references below are under the pinned `codex-rs/` directory.

- `app-server/src/request_processors/turn_processor.rs` forwards the submitted
  `webrtc.sdp` through `Op::RealtimeConversationStart`; it does not synthesize an
  answer or a successful connection.
- `core/src/realtime_conversation.rs:1350` prepares call and sideband providers
  from `experimental_realtime_webrtc_call_base_url` and
  `experimental_realtime_ws_base_url`. WebRTC/existing-call default to V1 even
  when configured realtime version is V2. WebRTC requires conversational mode;
  WebRTC/existing-call reject V2. V1/V3 text output is unsupported.
- `core/src/client.rs:740` performs actual native call creation using the
  configured provider's auth and retains the same auth for sideband attachment.
- `codex-api/src/endpoint/realtime_call.rs:129` sends multipart form parts `sdp`
  and `session`. V1 posts `/v1/realtime/calls?intent=quicksilver&architecture=avas`;
  V3 posts `/v1/live`. The answer is decoded as UTF-8 and a call ID is extracted
  from `Location`. There is no SDP semantic validation or native media engine on
  this app-server path. A fixed synthetic offer/answer therefore exercises the
  actual HTTP/notification path without a real account or media connection.
- `core/src/realtime_conversation.rs:1760` emits started, then the actual answer
  SDP. `app-server/src/bespoke_event_handling.rs:458` forwards it as
  `thread/realtime/sdp`. A successful SDP notice alone does not prove sideband
  success: the profile also requires authenticated WS attachment and a real
  native text/transcript/audio dependency exchange before requested stop.
- `codex-api/src/endpoint/realtime_websocket/methods.rs:884` joins V1 at
  `/v1/realtime?intent=quicksilver&call_id=rtc_owned_synthetic`; V3 joins
  `/v1/live/rtc_owned_synthetic`. Only the V1 WebRTC sideband sends a new
  `session.update`. Existing-call attachment sends no session configuration.
  New V3 WebSocket sessions send `session.update` and wait for `session.started`.
- Pinned upstream app-server tests
  `app-server/tests/suite/v2/realtime_conversation.rs:2371` and `:2620` exercise
  the same V1/V3 SDP and sideband routes. Those source tests are supporting
  evidence, not a substitute for this driver's stock-binary run.

## Executed checks

Eight fresh owned native processes cover WebSocket, WebRTC and existing-call
success with explicit V1/V3, plus omitted-version WebRTC/existing-call fallback
to V1 while configured version remains V2. All use audio output, synthetic bearer
auth, fixed peer events and explicitly requested stop. V3 WebSocket/WebRTC carry
one initial developer item; existing-call requests omit session configuration.

The peer validates actual native HTTP multipart body, version-specific session
JSON, native WS path, bearer/alpha/session headers and outbound text encoding.
The profile requires exact started/SDP correlation and ordering, transcript and
audio translation, no duplicate session update, no unexpected turn/error/server
request, no uncertain operation, requested closure and process cleanup.

## Stock-binary safety prerequisites

- Linux must support unprivileged user/net namespaces and provide `unshare`, `ip`
  and Python 3. The fixture fails closed if any `/etc/codex/config.toml`,
  `requirements.toml` or `managed_config.toml` exists.
- `CODEX_BINARY` must name the hash-pinned stock binary. No debug build,
  instrumentation, binary patch or fake app-server frame is accepted.
- Each case exclusively creates a root using 16 random bytes, with fresh HOME,
  CODEX_HOME, TMPDIR and workspace. The native environment is explicitly rebuilt;
  no host credential, proxy, desktop or D-Bus environment is inherited.
- The native process and dependency peer share a private network namespace with
  loopback only and no IPv4/IPv6 default route. No real account, service, media
  negotiation, paid inference, model turn, delegation or tool execution exists.
- Only fixed app-server lifecycle/text requests are forwarded to the genuine
  native process. The fixture speaks dependency HTTP/WS only. Sockets and worker
  threads are tracked and shut down within a 0.75 second total cleanup budget;
  the driver's existing stdio-owner grace/deadlines are unchanged.

In verified Devenv, from `apps/samgita_codex_driver` with `MIX_ENV=test` and
the immutable `CODEX_BINARY`:

```sh
mix compile --warnings-as-errors
mix test test/native_realtime_sdp_profile.exs --seed 501432
mix test test/native_realtime_sdp_profile.exs --seed 987654
mix format --check-formatted test/native_realtime_sdp_profile.exs
```

Both native runs pass **8 tests / zero failures**. Python AST, namespace preflight
and root scoped `mix credo
apps/samgita_codex_driver/test/native_realtime_sdp_profile.exs --strict` pass.
Initial native runs also passed. Strict Credo identified complexity 12 in the
test orchestration helper; extracting its unchanged dependency assertions into
a separate function preserves every predicate, effect and deadline. The entire
scoped block was repeated on final source. No production code or timeout changed.
Initial/final logs remain at `/tmp/samgita-realtime-sdp-*-20261024.log`.
CI explicitly selects this profile.

One new notification entry and nineteen directly asserted fields/variants gain
scoped evidence. Existing start/appendText/stop request/result entries receive
the stronger version/transport evidence. V2 enum, null version/transport, media
semantics, every handoff flag and unexercised initial-item roles are not inferred.
No entry becomes fully verified; aggregate and hosted evidence are separate.

## Limits retained

This supplies scoped control-plane evidence. It does
not establish valid SDP/ICE/DTLS/SRTP negotiation, browser/audio devices, real
audio playback, remote provider availability, account authorization, paid
inference, realtime handoff/delegation, reconnect/retry, privacy across multiple
owners, or production readiness. The backend-api JSON call-creation variant and
platform-specific success remain unqualified. V2 WebRTC/existing-call remain
unsupported by the pin; existing V2 WebSocket evidence is separate. A11 remains
blocked and no full-compatibility or release claim follows from this profile.
