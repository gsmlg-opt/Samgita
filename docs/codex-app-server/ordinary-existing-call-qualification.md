# Native ordinary existing-call attachment

This functional continuation follows `231eb2de08570f50d7aeab61178aa61f06d00d39`
on `main`. The target remains official Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, combined binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
YOLO is fixed opaque setup. No security, credentials, authentication,
authorization, approval, sandbox or permission behavior is tested. No real
account, media negotiation, inference or external service is used.

## Actual input consumption

The ordinary realtime fixture adds one finite `existing-call` scenario. Its
prearranged descriptive ID is `rtc_owned_existing_call`; it accepts exactly one
sideband WebSocket upgrade at
`/v1/realtime?intent=quicksilver&call_id=rtc_owned_existing_call`. This is a
local synthetic dependency, not an app-server emulator. It supplies no
app-server reply, notification or canonical history. Default fixture branches
and the existing22 case bodies/helpers remain byte-identical after reversing
the additive block, scenario choice and fixture checksum change.

The new separately tagged case creates a persistent paginated thread in the
actual binary, then sends `thread/realtime/start` with the exact
`{"type":"existingCall","callId":"rtc_owned_existing_call"}` transport,
explicitV1, audio output and a prescribed realtime session ID. It omits
new-session prompt/model/voice/initial-items options. The captured original
outgoing request is schema-validated and compared to the prescribed parameters.

Native code consumes that callId: the independent dependency journal must record
its exact sideband URL and one active connection. This case uses a new
path/connection readiness predicate; the unchanged old helper expects a
session.update/ACK exchange and would be wrong for existingCall. The dependency
sends no application message, rejects unexpected native JSON and never accepts
a call-create POST. Its model request count remains zero.

The real binary publishes the prescribed started item/lifecycle. Explicit stop
publishes the closed item and `reason:requested`; all six original notices
retain exact IDs, native payloads, causal order, generation and bounded emitted
timestamps. Native requested-stop EOF is recorded before fixture teardown.
Warm repeated timeline reads return only the two original lifecycle facts and
turn history remains empty. After confirmed owned native shutdown, a distinct
cold binary's first and repeated timeline reads return the exact same history.
They cause no sideband reattachment, turn or realtime notification.

Every one of the fourteen warm/cold requests has its own original correlated
reply. The outgoing sequences are independently prescribed. Warm capture and
the dependency's one-request/zero-message journal remain unchanged through the
cold read and cleanup. Native owner completion, closed Ports, absent owned PIDs
and final zero handler/socket state precede removal of the disposable root.
No borrowed service resource or real project is used.

## Physical schema and immutable source

Only these four physical `ClientRequest.json` owners gain implemented evidence.
The inventory resolves them from the experimental export. The test binds its
complete root SHA256
`92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352`,
exact method102, all four canonical node preimages, pointer resolution and
validation of the actual submitted transport. No stable/standalone alias or
parent-only credit is inferred.

| Owner | Pointer below `/definitions/ThreadRealtimeStartTransport` | Canonical SHA256 |
| --- | --- | --- |
|653|`/oneOf/2`|`321616f07930c9c94f003addbd3eb3550b0850b2462eb0104ed85975d849e47f`|
|654|`/oneOf/2/properties/callId`|`24d091fbf29516ce34ad3f1b54ebf2a84e8a474c2bae1109114c0d7fe3c55a9b`|
|655|`/oneOf/2/properties/type`|`3f6f0e88f1102d22a0db69047b58fd42d4f33abb37d0799df8240bb7b5bb7fb2`|
|656|`/oneOf/2/properties/type/enum/0`|`a7eed88cc53db222a1d5d2db23a868dbe0f584ba69c75eb4a48c5163bdf90e45`|

Pinned native route:

- `app-server-protocol/src/protocol/v2/realtime.rs:282–295` defines the
  existingCall/callId wire shape.
- `app-server/src/request_processors/turn_processor.rs:1217–1221,1270–1272,1293–1297`
  passes that exact ID to `ConversationStartTransport::ExistingCall`.
- `core/src/realtime_conversation.rs:1376–1400,1721–1757` selects the configured
  sideband URL/V1 attachment and emits real started lifecycle.
- `core/src/realtime_conversation/existing_call.rs:41–70` attaches with the ID;
  `codex-api/src/endpoint/realtime_websocket/methods.rs:904–925,1083–1089,1234–1259`
  sets `initialize_session=false` and inserts V1 `call_id` into the query.

Source report `/tmp/samgita-ordinary-existing-call-input-20261029-report.md`
has SHA256 `07f51d38c9b9d053599941af44a2e29368241c9f62c67d32738f9927c8649218`.
Five complete causal files match the immutable source archive. The reviewed
draft `/tmp/samgita-existing-call-draft-20261029-r2/existing-call.patch` has
SHA256 `cb9bbafb18d428d8dd5f37c2a3180b0ae37b75be85466c0289f34eed02b79458`;
fixture SHA256 becomes
`b881b45392d7d18243f88ce3f6b7f5f9f72849236412eebb994864a0331bab38`.
Source-only review is not native acceptance. Historical mixed realtime profiles
remain unrun and contribute no new runtime credit.

## Functional verification and limits

Focused command runs only the new case at line2491 of
`native_realtime_start_stop_test.exs`, seeds501432/987654: each reports23 total,
22 excluded and1 passed, in5.062s/5.162s. Format and strict Credo pass.
Evidence `/tmp/samgita-existing-call-focused-20261029` has native log SHA256
`f02a8576cf1c5f81bb6187b21649fa276fac1a01324f5a599b6a8317ab92c868`
and `f3b4fcec7f3ba75946a098be2bcdf3c78b230028a88ad2713d2ae2b57e16852e`.
An independent inverse reconstruction matches the entire prior test module
byte-for-byte, preserving all22 old cases/helpers and their assertions.

Original20-second active, five-second observation/RPC and60-second case bounds,
128 native frames,8KiB outgoing/64KiB incoming,2MiB capture/journal and32
dependency-frame bounds remain. No sleeps or timeouts are added to fix a
failure. The original main argv gains one ordinary case,165 to166; all old
cases stay and the320s bounds remain. Extensions stay21 with120s bounds.
Focused success alone does not establish the complete goal or a release gate.

## Final combined source functional qualification

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-existing-call-combined-20261029
python3 -B /tmp/samgita-existing-call-binding-20261029.py
```

All **17 reviewed functional steps pass** against1,762 identical before/after
guarded hashes. Main166/0 passes twice in289.071s/286.311s within the original
320s bounds. Extensions21/0 pass twice in35.278s/35.028s within120s. The three
selected WebSocket seeds, four cleanup cases, independent outside consumer1/0,
inventory, driver/root format and compilation, strict Credo, Dialyzer and assets
build pass. No prohibited test/audit, broad mixed suite or hosted workflow runs.

Reviewed fingerprint is
`cdc60700292db9d2989f335052ae9d58e6fbd05966a3785df73070cb93072dac`.
`results.json` SHA256 is
`dc0fe4f442ecd2031b452adebe506489cf1fe684eb41bc3a50db2fcd2d0e03c3`;
`source.json` SHA256 is
`d6c49b729b57dca19be1cd914ec9f590efe62de9a0beb7d1b7c00478e429b9fa`.
Binding evidence is `/tmp/samgita-existing-call-binding-20261029/binding.json`,
SHA256 `2d9cbd44b12b2616b4fc2ef96b1c2000348e88911df656e36ffb3fd8925fe332`.
It verifies every command/count/log/bound, all1,748 other tracked guarded files
against baseline and ten ignored outputs against the preceding successful
snapshot, five complete causal source files against the immutable archive,
exact canonical owner nodes, and inverse reconstruction of the old22-case
module. All485 requirements and6,617 other schema contracts remain exact.

Scoped contracts are **5,756 implemented /729 missing /136 blocked**;
requirements stay462 implemented/12 missing/11 blocked, zero globally verified.
Only653–656 change state. Production source,
schemas, dependencies, shared cleanup, database recovery and historical records
are unchanged. The prearranged dependency ID is not evidence of a real
negotiated ICE/DTLS/media call. External success, V2/V3, reconnect/activation
errors, A11, prohibited/broad/hosted tests, source-bound legacy/nullable branches,
full compatibility and release remain incomplete. No publication/deployment.

Further bounded source review finds a separate prerequisite for HookSource
owner2259 (`project`): the reviewed ordinary generators supply user/CLI/plugin
config, without a project config-layer fixture. The native provenance mapper
supports Project, but that does not establish its input or delivered notice.
The report `/tmp/samgita-hook-project-source-boundary-20261029-report.md`, SHA256
`01075c36a4b5839a04d30e199d37f0d19859b98726a418c8e2b33ef796e51a5d`,
stops before any new admission/trust setup or investigation. Owner2259 stays
missing; this is a fixture prerequisite, not an upstream impossibility claim.

Next: record the inspected ordinary child-notification emitter boundary and
project-hook fixture prerequisite with immutable source evidence only. They
must retain missing states, without fabricated native frames or alias credit.

Rollback restores the additive test/fixture scenario, four evidence records
and reviewed runner count/fingerprint. No runtime or data migration occurs.
