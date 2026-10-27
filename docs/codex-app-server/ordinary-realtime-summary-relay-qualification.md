# Ordinary native V3 public-summary relay

V486 (2026-10-28) adds one genuine public-summary relay through official
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
Linux x86_64 musl/stdio. It extends the separately qualified
[V3 delegation journey](ordinary-realtime-delegation-qualification.md), whose
exact baseline counts, original-wire checks, history and cleanup remain intact.
The local finite provider supplies only fixed public summary and assistant
content. Actual Codex handles the app-server protocol, runs the backing turn,
relays the status and persists all native items. No client `turn/start` is sent.

The new original start RPC explicitly adds `backendReasoningStatus: true`.
After genuine backend delegation, the provider first sends `response.created`
and this actual `response.output_item.done` item:

```json
{"type":"reasoning","id":"owned-v486-public-summary","summary":[{"type":"summary_text","text":"  Owned quiet progress λ  "}],"content":[]}
```

It sends the remaining assistant/completion SSE bytes only after the live peer
has received exactly:

```json
{"type":"delegation.context.append","delegation_item_id":"owned-handoff-1","channel":"commentary","content":[{"type":"input_text","text":"[STATUS] Owned quiet progress λ"}]}
```

The genuine handoff ID and trimmed public text must match; provider and native
persisted summary strings retain their two leading/trailing spaces. This quiet
status remains separate from the later prefixed assistant `session.context.append`
and from task completion/acceptance. The existing provider deadline and release
event coordinate the actual protocol observations; there is no sleep, extra
HTTP control endpoint, increased deadline or weakened stale-handler check.
Existing teardown sets stopping/release before closing sockets and joining
handlers, so a failed journey cannot strand the provider wait.

Original request/response bytes, IDs, model-body base64/length/SHA256 and real
thread/turn metadata remain required. Captured original SSE segments are parsed
and compared to exact prefix/suffix event lists. The resulting native completed
items are exactly user, reasoning, assistant. The loaded persistence barrier
precedes full turn and seven-row timeline reads; each row maps to its actual
canonical ordinal. Exact raw `Reasoning` with snake_case fields and public
`reasoning` with `summary`/`content` are checked independently. The provider ID
is preserved in the original notice and both histories. Warm/cold repeated reads
perform no inference, create no realtime session and preserve rollout, peer
journal, config, catalog and workspace. Requested-stop EOF precedes teardown;
all V485 count/buffer/handler/body/frame/process ownership bounds remain unchanged.

The source path is concrete: `codex-api/src/sse/responses.rs:351–359` parses
the provider item; `core/src/event_mapping.rs:201–227` and
`stream_events_utils.rs:346–389` retain its public summary and ID.
`session/turn.rs:2179–2190`, `session/mod.rs:2610–2612` and
`realtime_conversation.rs:911–937` choose the last nonempty trimmed summary and
queue a status for the active handoff. The frameless writer at
`realtime_conversation.rs:2417–2430` retains the active-handoff check before
sending quiet commentary via `methods_common.rs:56–70` and
`methods_frameless_bidi.rs:14–23`. Turn completion clears the active handoff;
the fixture's real status observation therefore provides a deterministic
barrier before final completion. Protocol raw/public item definitions are in
`protocol/src/items.rs:43–52,191–198` and
`app-server-protocol/src/protocol/v2/item.rs:232–236,282–287,916–920`.

The first focused ordinary realtime execution passes **11/0**, retaining all
ten previous cases. Log `/tmp/samgita-v486-quiet-status-focused.log`, SHA256
`77731860f46d05916c90c40a5d4fa9d239d6ec207a08712c3e4cb1a119830ffe`.
Only physical owner **5950** gains scoped implemented evidence. Other values,
defaults/nulls/omission, empty/multiple/truncated summaries, interrupted/stale
handoffs, providers, versions and transports remain unverified. This is no
full-compatibility or real model-service claim. Fixed YOLO is ordinary launch
setup; no security, credential, authentication, authorization, permission or
approval tests/audits, broad suite or hosted workflow run. A11, unavailable
emitters, external/OS/full-goal and release gates remain incomplete. No runtime,
database, publication or deployment change. Rollback reverts this test/fixture/
evidence unit. Continue custom BEM channel-prefix behavior.

Final **53 files / 90 ordinary real-binary cases at both seeds 501432/987654**,
three selected WebSocket cases at each of 455834/501432/987654, outside consumer
**1/0**, warning-strict compile, format, inventory consistency, strict Credo,
forced Dialyzer and assets all pass. All **14** reviewed steps complete; all
**1,668** before/after guarded source hashes agree. Logs and exact commands:
`/tmp/samgita-ordinary-v486/`; `results.json` SHA256
`784403fc47d349b00488d7125e38ff58465b08704801adc5f93456d211c58cf1`,
`source.json` SHA256
`8cf0ef5827cc07eef3f85e2ee23de8319d82a97fb8d18c5e4b3f59888c7ab25a`.
Reviewed fingerprint:
`70c6969ac8e1e2ea6ec067223608db52931d94fac2ca50c3f1bcceee597ab201`.
The final one-node/test/source binding checks **36** complete producer files
against the immutable archive binding:
`/tmp/samgita-v486-summary-relay-binding/source.json`, SHA256
`3c7ad9db31c7922d0c0644b21d481c91cc32bc00fa1a680a33ba63dd778f0f6b`.
Counts are **5,442 implemented / 1,063 missing / 116 blocked** contracts and
unchanged **462 implemented / 12 missing / 11 blocked** requirements, zero
verified. The reviewed selection does not replace incomplete full-compatibility
or release gates.
