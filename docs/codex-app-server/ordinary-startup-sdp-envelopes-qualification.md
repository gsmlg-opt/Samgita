# Ordinary startup warning and V1 SDP envelopes

V477 adds one nonfatal configuration-warning case and one V1 call/sideband
case against stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
All app-server frames originate in that executable. The finite local HTTP/WS
peer supplies realtime dependency responses; it never writes app-server frames
or runs inference. No external service, paid task, database, security,
credential, authentication, authorization, permission or approval test runs.
Each native launch uses fixed ordinary YOLO configuration.

## Nonfatal configuration warning

An empty key with inert text in `otel.span_attributes`, with all exporters
`none`, reaches the ordinary [attribute validator][validator]. The
[configuration resolver][resolver] drops the invalid attribute and preserves
the valid file configuration and static model catalog. The startup-warning
producer and [initialization dispatcher][initialize] emit exactly:

```json
{"summary":"Ignoring invalid `otel.span_attributes` config: configured span attribute key must not be empty","details":null}
```

The test independently prescribes the complete notification envelope, with
absent path/range, bounded native `emittedAtMs`, current driver generation and
unique ordered sequence. Captured original bytes and decoded driver/Wire
payloads must match. Original initialize request/response and warning indices
prove causation. No order is invented between the driver's outgoing
`initialized` and incoming warning, which may race.

Two distinct fresh native processes each return the exact static model twice,
retain empty loaded-thread state, emit exactly one warning and complete exactly
twelve frames: six outgoing, five correlated RPCs and the warning. Config,
catalog, copied shell and capture bytes remain exact through owned
Session/owner/Port/PID cleanup. There is no empty-catalog fallback, inference,
tool execution, listener, exporter or credential behavior in this profile.

## V1 SDP forwarding and control channel

The native request explicitly selects V1 conversational WebRTC and passes a
fixed offer containing Unicode and CRLF. Both [call and sideband destinations][destinations]
point to the owned loopback peer. The actual native [call client][multipart]
sends exactly one bounded multipart request, with the exact offer and complete
independently prescribed session. The peer returns a fixed Unicode/CRLF answer
and functional call-ID Location. Native code joins exactly one sideband WS
using that call ID; the peer requires the exact V1 `session.update` and returns
only a readiness message.

The [core producer][producer] publishes started then the returned SDP; the
[app-server mapper][mapping] emits the complete original `thread/realtime/sdp`
envelope. The test requires its literal answer, thread identity, original raw
bytes, bounded native time, current generation and
`started < SDP < requested closed` sequence. It issues one explicit stop after
observing both the native notification and sideband readiness. No retry or
another execution follows closure.

Public store reads provide persistence barriers. The [history observer][history]
does not observe SDP, so the exact repeated warm/cold timeline contains only
start and closed facts, with zero ordinary turns. A distinct cold native
process cannot re-emit SDP. Exact finite warm/cold RPC lists, unchanged owned
config/catalog/fixture bytes and backend journal, and Session/owner/Port/PID/
listener/socket/handler/server-thread shutdown remain required.

The four previous ordinary realtime cases remain unchanged, apart from the
shared fixture hash and adding the new scenario argument. Existing bounds stay
128 frames, 8 KiB outgoing, 64 KiB incoming and 2 MiB total; the peer additionally
limits HTTP bodies to 16 KiB, WS frames to 64 KiB and 32 total frames. Existing
five-second RPC/observation bounds, twenty-second active scenario and
sixty-second case deadline remain unchanged.

This proves inert SDP string forwarding and control-channel handshake. It does
not qualify ICE/DTLS negotiation, real media interoperability, playback or a
live WebRTC service. V2 WebRTC is unsupported by the pinned producer; no V2
success claim follows. The historical mixed SDP profile is neither imported
nor executed.

## Focused results and binding

The first realtime focus preserves **5/1**, 10.7 seconds, in
`/tmp/samgita-v477-realtime-501432.log`. The sole failure omitted the mandatory
nullable `backwardsCursor` from an empty turns-page expectation. Pinned
[`ThreadTurnsListResponse`][turns] explicitly serializes that field. Both warm
and cold expectations now require its exact null; no assertion, behavior,
bound or timeout is removed or weakened. The corrected focus passes **5/0**,
8.6 seconds, in `/tmp/samgita-v477-realtime-cursor-501432.log`.

The independent config-warning focus passes **1/0**, 1.4 seconds, in
`/tmp/samgita-v477-config-warning-501432.log`. Commands run from the independent
driver directory in Devenv Elixir 1.18.5/OTP 27, with `MIX_ENV=test`,
`ERL_FLAGS='+S 2:2'` and the pinned `CODEX_BINARY`:

```sh
mix test test/native_realtime_start_stop_test.exs --warnings-as-errors --seed 501432
mix test test/native_config_warning_envelope_test.exs --warnings-as-errors --seed 501432
```

Strict Credo passes on 587 source files; Python AST parsing passes. Source-only
cross-review agrees with the producer, multipart and persistence contracts.
Runtime evidence comes from the actual native checks, not that review.

Seventeen complete producer/projection sources and all **5,259** current Rust
files match the [official full-source binding](legacy-file-output-boundary.md).
Both generated/vendored stable and experimental canonical nodes match. Binding
`/tmp/samgita-v477-startup-sdp-binding/source.json`, SHA256
`92e064c3a602a7a735f76c7a572ad6e05e4360eccc1984601579a24d1a7be1e9`,
records each source/test/fixture hash, canonical owner and focused failure/pass.

Only eight physical owners gain scoped implemented evidence: configWarning
**3067–3070**, `/oneOf/68` plus method/literal/params reference, and SDP
**3115–3118**, `/oneOf/79` and the same siblings. Nested aliases, other variants,
entire methods/schemas, transports/backend/OS profiles and requirements gain no
credit. Current contracts are **5,372 implemented / 1,133 missing / 116 blocked**;
requirements stay **462 implemented / 12 missing / 11 blocked**, zero verified
in both.

## Final reviewed functional matrix

`devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v477`
passes all **14/14** reviewed steps. The **50 files / 81 ordinary cases** pass
at seeds 501432 and 987654 in 137.043 and 136.235 seconds. Three selected
WebSocket cases pass at each of 455834, 501432 and 987654; the outside consumer
passes **1/0**. Driver/root formatting, driver/umbrella warning-strict compile,
inventory consistency, strict Credo, forced Dialyzer and assets build pass.

All **1,668** guarded before/after hashes are identical, with reviewed
fingerprint
`bbf5b40aa66dc69327d8fbba3e19bfb322286bba9b13a7cf09136361902ce481`.
Compared with V476, exactly the new config-warning test and four reviewed
test/fixture/manifest/runner changes differ; no source is removed.
`/tmp/samgita-ordinary-v477/results.json` SHA256
`3bb50098df186b19deddd41f7ae719f0042f3ada8c3808b21b8e236f00776213`;
`source.json` SHA256
`2ec6096ab67a03da7cff40f26787f90f6ce238690bb2a9f00f84aaae642ce3db`.
Each original command, duration and log hash remains in those files. Neither
the functional selection nor this source-only cross-review runs a prohibited
test/audit, broad suite or hosted workflow.

Full compatibility remains active. Prohibited tests/audits, broad/hosted suites,
A11, unavailable legacy emitters, external/platform/other OS/backend success,
live media and release gates remain incomplete. No publication, deployment,
production migration or changes to sibling services.

[validator]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/otel/src/config.rs#L39-L47
[resolver]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/otel.rs#L42-L65
[initialize]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/initialize_processor.rs#L232-L251
[destinations]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/realtime_conversation.rs#L1376-L1396
[multipart]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-api/src/endpoint/realtime_call.rs#L129-L209
[producer]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/realtime_conversation.rs#L1755-L1777
[mapping]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/bespoke_event_handling.rs#L458-L466
[history]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/realtime_history.rs#L128-L145
[turns]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread.rs#L1761-L1771
