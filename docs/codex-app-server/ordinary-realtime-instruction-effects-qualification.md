# Ordinary realtime instructions in actual model requests

V484 (2026-10-28) qualifies two explicit custom instruction values through real
Codex turns. The immutable target remains official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
Linux x86_64 musl/stdio. The finite loopback peer implements a realtime backend
and two assistant-only Responses streams; Codex itself handles every app-server
request, constructs model inputs and emits/persists the original turn events.
This is no real model-service, reasoning-quality or complete compatibility claim.

After V2 realtime readiness, one explicit turn runs while the session is active.
Its actual model input must contain exactly this developer content element:

```json
"<realtime_conversation>\nOwned active context λ\nkeep trailing space \n</realtime_conversation>"
```

After the genuine requested-close notification and independently observed
backend EOF, a second explicit turn must retain that first fragment once and
add exactly the following element once:

```json
"<realtime_conversation>\nOwned stopped context 🙂\nkeep trailing space \n</realtime_conversation>"
```

Each illustrated instruction's last body line ends in one space. The test uses
exact string equality, preserving that space and all newlines. Source can
coalesce adjacent developer fragments into one message with separate content
elements, so it does not assume a dedicated message or use substring matching.
Original Responses bodies, base64/length/SHA256, native thread/turn metadata,
user markers, retained prior assistant text and literal new assistant results
are checked independently of the app-server startup ACK. Exactly two model
requests and three accepted HTTP requests are permitted; no extra inference,
realtime connection, control request or forwarded assistant frame can pass.

Both turns must complete through the native user/assistant item lifecycle.
Original request/response bytes and IDs, all six realtime lifecycle notices,
notification generation/order and causal start/turn/stop boundaries remain
required. A loaded `thread/read(includeTurns: true)` explicitly persists/projects
both completed turns before history reads. Two full ascending turns and the
entire ten-row timeline are then repeated warm and cold. Every position maps to
the actual canonical rollout ordinal, including both realtime records and all
ordinary turn boundaries/items. Raw realtime storage uses snake_case; public
timeline items use camelCase. No normalization joins those distinct contracts.

The standalone test validates every original response with public
`Schema.validate_result(:server_response, method, result, experimental: true)`.
That applies the existing hash-checked
[native timeline output correction](thread-history-qualification.md); official
exports and received response bytes remain untouched. There is no platform
dependency or new schema exception. After producer shutdown, cold reads start
no turn and preserve rollout, backend journal, workspace, config and catalog.
Existing owned PID/Port/socket/thread/listener cleanup remains required.

Source ownership is explicit: `session/world_state.rs:186–201` reads saved
options; `context/world_state/realtime.rs:37–101` selects start/end fragments;
the two `context/realtime_*_instructions.rs` types and
`context-fragments/src/fragment.rs:88–103` preserve exact developer text.
`context_manager/updates.rs:10–26` handles grouping. Requested detach awaits
inactive state through `realtime_conversation.rs:1270–1288,1827–1843,2036–2059`.
`thread_processor.rs:2948–2990,3164–3178` provides the loaded persistence
barrier. Raw event fields/timings come from `protocol.rs:2057–2070,2266–2321`;
raw realtime fields are in `protocol/src/realtime.rs:8–31`.

Pre-execution review corrected two draft assumptions: raw/public realtime
payloads need separate expectations, and metadata-only reads are not the loaded
persistence barrier. The first executed native check passes **9/0**, retaining
all eight prior realtime cases. Log:
`/tmp/samgita-v484-instructions-focused/native-instructions.log`, SHA256
`bdb7fc28f8d19d48073fdffb7f85c9ddd7dcc0955f43457e3c8a26a0202d082a`.
The following strict Credo check exits8 on one nested conditional in
`assert_events`; its log is `/tmp/samgita-v484-credo.log`, SHA256
`152716ec573671c0ad291cf745c047ef0058ad20bdc8f47d611cbdcb11de09c7`.
Extracting the scenario's forbidden-method list preserves every old prohibition,
the new case's explicit completed-item checks and all deadlines/bounds.

Final **53 files / 88 ordinary real-binary cases at both seeds 501432/987654**,
three selected WebSocket cases at each of 455834/501432/987654, outside consumer
**1/0**, warning-strict compile, format, inventory consistency, strict Credo,
forced Dialyzer and assets all pass. All **14** reviewed steps complete and
all **1,668** before/after executable source hashes agree. Exact commands/logs:
`/tmp/samgita-ordinary-v484/`; `results.json` SHA256
`dbfdb515714be634ca0d620c0606ac24d4df6cc9ed6416116c7421d70c1d1380`,
`source.json` SHA256
`2901bd05ffb0c5ec07e9f1114a89a7b0cb1405d8ffd06463fb86e578118b9b57`.
Reviewed fingerprint:
`b012a7b607bf466a8d045168eceff4a350c8ae6fe75d3d605b134fc82f7a137d`.
The final two-node/source/test binding hashes all **22** linked complete producer
files against the retained immutable archive binding:
`/tmp/samgita-v484-instruction-effects-binding/source.json`, SHA256
`3179c73335fe5246f1bf05d01b22276e31e4fdafcec198584f04416db105f40d`.

Only physical owners **5966/5968**, `ThreadRealtimeStartParams` custom end/start
fields, gain scoped implemented evidence. Counts are **5,434 implemented /
1,071 missing / 116 blocked** contracts, unchanged **462 implemented / 12 missing /
11 blocked** requirements and zero verified. Empty/null/omitted/default
instructions, other handoff flags, versions, transports and external backends
receive no credit. Fixed YOLO is launch setup; no security, credential,
authentication, authorization, permission or approval tests/audits, broad suite
or hosted workflow runs. A11, unavailable emitters/external/OS/full-goal and
release gates remain incomplete. No runtime, database/history migration,
publication or deployment change. Rollback reverts this test/fixture/evidence
unit. Continue the source-confirmed V3 delegated backing-turn output path.
