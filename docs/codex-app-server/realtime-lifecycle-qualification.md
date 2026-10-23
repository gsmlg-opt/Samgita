# Native realtime WebSocket V2 lifecycle qualification

This unit targets immutable Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, through the reusable driver and
the actual Linux stdio app-server. The private Python stdlib peer supplies only
synthetic realtime backend traffic. It never implements app-server RPCs.

## Source contract

Paths below are relative to pinned `codex-rs/`:

- `app-server-protocol/src/protocol/common.rs:1080–1120` marks all six realtime
  methods experimental. `app-server-protocol/src/protocol/v2/realtime.rs` defines required audio sample
  metadata, transport discriminants, prompt omission/null/string, start options,
  notifications and typed durable items.
- `app-server/src/request_processors/turn_processor.rs:1185–1405` requires a
  loaded thread, rejects unsupported existing-call options before thread lookup,
  and otherwise submits core operations before returning empty RPC results.
  Voice lists at `331–341` use the builtin catalogue without auth or a thread.
- `core/src/realtime_conversation.rs:1288–1319,1353–1700` emits asynchronous
  realtime errors for preparation/start failures, applies model and prompt
  precedence, validates voice/version/initial-item constraints and resolves
  synthetic API-key auth. `1926–1949` defines key resolution. Invalid-request
  display in `protocol/src/error.rs:151–153` preserves the message unchanged.
  `core/src/realtime_prompt.rs:5–27` gives nonblank configured prompts precedence
  over request prompts; with a blank configured prompt, explicit text and null
  retain their distinct request behavior.
- `core/src/realtime_conversation.rs:620–640,1750–1865,2810–2830` describes
  replacement, started/event fanout and requested/error/transport closure reasons.
  `1171–1198,2470–2520` routes explicit speech to a V2 backend item and response
  request without launching a backing Codex turn.
- `codex-api/src/endpoint/realtime_websocket/methods.rs:860–884,1174–1224`
  connects to the normalized model-specific URL and sends session update. V2
  does not require a backend session-update acknowledgement before reporting
  connection success. `methods_v2.rs:40–170` maps role/text and session settings.
  `protocol_v2.rs:23–128` maps transcript, audio, item and error events.
- `protocol/src/protocol.rs:339–405` owns exact builtin voice ordering/defaults.
  Native reference journeys are in
  `app-server/tests/suite/v2/realtime_conversation.rs:677–819,1536–1732,2989–3062,3427–3510`.

## Eight scoped cases

`apps/samgita_codex_driver/test/native_realtime_lifecycle_profile.exs` covers:

1. Exact builtin voice lists and defaults with no auth, loaded thread, realtime
   handshake or Responses request.
2. Actual native V2 startup, model configuration/request precedence, normalized
   URL and synthetic authorization, default/explicit voice, audio/text output,
   configured/explicit/null prompt and enabled/disabled startup context.
3. Audio and all three text roles plus explicit speech, with peer journals proving
   translated native frames. Backend transcript/audio/raw-item events verify
   thread correlation and preserved audio metadata.
4. Native UUIDv7 typed start/transcript/closure items, item-correlated deltas,
   final transcript versus durable delta facts, persisted timeline, cold read
   and explicit resume without model work.
5. Replacement closes the prior identity; requested stop retains closure outcome
   and allows another explicit session on the same thread.
6. Backend error and ordinary transport closure preserve their separate native
   reasons and durable outcomes; explicit starts restore usability.
7. Empty RPC acknowledgements followed by exact asynchronous missing-auth,
   voice/version and initial-item errors, with no backend handshake after
   preparation rejects the settings.
8. Absent/false experimental negotiation, malformed required fields/enums/audio
   ranges, and all six existing-call option exclusions preserve direct native
   RPC rejection. Existing-call exclusions precede lookup of an absent thread.

## Isolation and evidence boundaries

Each test owns scratch HOME/CODEX_HOME/workspace, loopback HTTP/WebSocket peer,
synthetic bearer token and explicitly owned pinned-native processes. The driver
transport excludes inherited credentials. Cleanup is registered immediately
after every native start. The peer implements bounded masked WebSocket framing
using Python stdlib only, journals native frames atomically and accepts explicit
stdin emit/close/barrier commands. Positive event/journal barriers avoid timing
assumptions about request acknowledgement or backend delivery. Every case
requires an empty Responses request journal and a ready driver without pending
or uncertain calls. No backend delegation/tool event, real credentials, paid
model call, platform database or production task is authorized or exercised.

Prepared at baseline `dd1f845cee79420116a4aac007395f4cc2a8295d` and installed
after parent integration at `23c25a7aa8a828e1678829e97f31283d1860b1f0` on
2026-10-24. Drafts remained outside test discovery until the coordinating agent
granted the exclusive validation slot. The command below exited `0` on its first
run: compile with warnings as errors and format checks passed, and **8 tests,
0 failures** ran under both seeds (`501432`: 5.4 seconds; `987654`: 5.5 seconds).
Full output is retained at `/tmp/samgita-native-realtime-initial.log`.

```sh
devenv shell --no-tui -- bash -c 'cd apps/samgita_codex_driver &&
  MIX_ENV=test mix format test/native_realtime_lifecycle_profile.exs &&
  MIX_ENV=test mix compile --warnings-as-errors &&
  MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_realtime_lifecycle_profile.exs --include real_codex --seed 501432 &&
  MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_realtime_lifecycle_profile.exs --include real_codex --seed 987654 &&
  MIX_ENV=test mix format --check-formatted test/native_realtime_lifecycle_profile.exs'
```

The first focused strict Credo invocation in `MIX_ENV=test` exited `4` with
exactly three readability findings: native error-code literals `-32600` needed
underscore spelling `-32_600`. Its output is retained at
`/tmp/samgita-native-realtime-credo.log`. Repair round 1 changed only those three
numerically identical literals; no schema, runtime, assertion semantics or
timeouts changed. The entire command above was repeated, followed by:

```sh
devenv shell --no-tui -- bash -c 'MIX_ENV=test mix credo --strict --files-included apps/samgita_codex_driver/test/native_realtime_lifecycle_profile.exs'
```

The combined repair validation exited `0`: **8 tests, 0 failures** under each
seed (`501432`: 5.6 seconds; `987654`: 5.9 seconds), compile and formatting
passed, and strict Credo analyzed 315 files with 69 checks and found no issues.
Output is retained at `/tmp/samgita-native-realtime-repair-1.log`. Python source
syntax validation and scoped `git diff --check` also passed. Cumulative Sol
repair rounds: 1 successful, 0 unsuccessful; Astra repair rounds: 0.

The native binary was independently SHA256-checked as
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215` at
`tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl`. All owned native and peer
processes were reaped after validation; shared host processes were untouched.

V1/V3 and WebRTC/existing-call success, delegated backing turns, tool/handoff
execution, live backend/audio quality, remote transports, unavailable external
and platform success profiles and A11 remain unqualified. Listing V1/V3 voices
and rejecting unsupported settings do not qualify those success paths. Local
native evidence cannot establish full compatibility, publication or production
readiness.
