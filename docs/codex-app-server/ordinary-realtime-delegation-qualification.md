# Ordinary native V3 delegation and commentary result

V485 (2026-10-28) exercises a genuine backend delegation through official
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
Linux x86_64 musl/stdio. The bounded loopback fixture implements only the
realtime backend and one assistant-only Responses stream. The actual Codex
process handles app-server RPCs, starts its backing turn, constructs the model
request and emits/persists every original lifecycle event. No client
`turn/start` is sent. This does not qualify a real model service or all V3 modes.

The original start RPC explicitly selects `clientManagedHandoffs: false`,
`codexResponsesAsItems: true`, `codexResponseHandoffMode: "commentary"` and
`codexResponseItemPrefix: "Owned delegate result λ"`. After its readiness ACK,
the backend sends exactly one `delegation.created` with item ID
`owned-handoff-1` and input `Owned bounded request λ`. The live backend must
receive exactly one result:

```json
{"type":"session.context.append","channel":"commentary","content":[{"type":"input_text","text":"Owned delegate result λ\n\nOwned bounded assistant result 🙂"}]}
```

The original handoff notice retains its real ID and enriched transcript. The
independently captured model request must contain exactly this user element:

```json
"<realtime_delegation>\n  <input>Owned bounded request λ</input>\n  <transcript_delta>user: Owned bounded request λ</transcript_delta>\n</realtime_delegation>"
```

Original raw-body base64, SHA256 and length, native thread/turn metadata,
literal assistant answer, request/response correlation, original notices and
schema validation remain required. A loaded full `thread/read` provides the
native persistence barrier. Full ascending one-turn history and the entire
six-row timeline (start, turn start, user, assistant, turn completion, close)
repeat warm and cold. Every position maps to its canonical rollout ordinal;
raw snake_case and public camelCase realtime maps are checked separately.
Requested stop must produce peer-observed EOF before any teardown. Reads must
leave model request count, peer journal, rollout and fixture inputs unchanged.

Limits stay at 60 seconds per case, 20 seconds per journey, 5 seconds per RPC/
observation, 25 seconds per backend socket, two handlers, four HTTP requests,
32 frames, 64 KiB body/frame, 128 captured app-server frames and 2 MiB journal/
capture. The scenario actually requires two HTTP requests and one model request.
It creates no control-request race. Existing owned process/Port/PID/socket/
handler/listener shutdown proofs remain in force. No total ordering is imposed
between handoff delivery and backing-turn notifications, which are concurrent.

The first focused run fails **10 tests / 1 failure** at the exact wrapped-input
oracle, while the nine retained realtime cases pass. Log
`/tmp/samgita-v485-delegation-focused.log`, SHA256
`ce6ad5b58fa7a7c93a17dd26ab82e1c4628a865d93bcbcdf0226da092946abe0`.
Two diagnostic executions select only this case and preserve the failure:
`/tmp/samgita-v485-delegation-diagnostic.log`, SHA256
`e048c2e4c8cfa786789eb659e1e2a9268f3bfa1aa34e312b976f2b368b6c4eaa`,
and `/tmp/samgita-v485-delegation-input-diagnostic.log`, SHA256
`887f7897670310b6b6dde8485081d9a46e3ecc576a09f8c1670229ce961b1d63`.
The parser initializes an empty transcript, but
`codex-api/.../methods.rs:568–572,682–686,814–824` enriches it with the handoff
input before core receives it. `core/src/realtime_conversation.rs:1890–1923`
and `context/realtime_delegation.rs:59–72` render the extra transcript element.
The original synthetic request confirmed that chain. Temporary diagnostic
capture was removed; fixed exception class/source-line diagnostics remain.
Correcting the exact public transcript and wrapped text gives focused **10/0**;
no deadline, guard or assertion was removed.

The producer continues through `session/turn_input.rs:734–759` with a genuine
native submission ID; `bespoke_event_handling.rs:606–621` emits `itemAdded`.
`realtime_conversation.rs:986–993,1211,1660–1666,2350,2483–2492` and frameless
writer methods produce the prefix and exact commentary channel. V3 uses the
internal V1 session kind, so the separate V2 completion acknowledgement is not
emitted. History reduction adds no extra transcript/presentation row for this
plain assistant response. Public output validation uses the existing pinned
correction interface; official schema exports and wire bytes remain unchanged.

Only physical owners **92/5930/5951/5953/5954/5956/5957** gain scoped implemented
evidence for these exact values, including both commentary enum graph nodes.
Other values, defaults/nulls, modes, prefixes, repeated/steered handoffs,
streaming, providers and transports remain unverified. No whole-method or
full-compatibility credit follows. Fixed YOLO is ordinary launch setup; no
security, credential, authentication, authorization, permission or approval
tests/audits, broad suite or hosted workflow run. A11, unavailable emitters,
external/OS/full-goal and release gates remain incomplete. No runtime, database,
publication or deployment change. Rollback reverts this test/fixture/evidence
unit. Next ordinary gap is V3 public-summary context relay.

Final **53 files / 89 ordinary real-binary cases at both seeds 501432/987654**,
three selected neutral WebSocket cases at each of 455834/501432/987654, outside
consumer **1/0**, warning-strict compile, format, inventory consistency, strict
Credo, forced Dialyzer and assets all pass. All **14** reviewed steps complete;
all **1,668** guarded before/after source hashes agree. Exact commands/logs:
`/tmp/samgita-ordinary-v485/`; `results.json` SHA256
`c2a60f4ba8643833948096c66e0978dfcc2e51fa0b509e308a0a41b2172be900`,
`source.json` SHA256
`87a262b7202035555257c9871827845fc73a91631981ee105e92b8d45e89ef4a`.
Reviewed fingerprint:
`75313634635a40df2f5d880cf7f51bda622ceb267d527bec55ab01b153f21634`.
The corrected focused log is `/tmp/samgita-v485-delegation-corrected.log`,
SHA256 `aecb7bc7289ebd7f18949d9b5831aea27b2f085148a6be7e98ac3ce519e09d41`.
The seven-node/final-test/source binding checks **35** complete producer files
against the immutable archive binding:
`/tmp/samgita-v485-delegation-binding/source.json`, SHA256
`9dd2dbb4a065cca84a4e027930aa33e794693bbf07a6dff78b5641673eda698e`.
Counts are **5,441 implemented / 1,064 missing / 116 blocked** contracts and
unchanged **462 implemented / 12 missing / 11 blocked** requirements, with zero
verified. This reviewed functional matrix does not replace prohibited or
otherwise incomplete full-compatibility and release checks.
