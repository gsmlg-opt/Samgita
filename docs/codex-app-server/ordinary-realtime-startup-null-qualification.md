# Ordinary native V3 startup nulls

V490 (2026-10-28) exercises three independent explicit-null startup options with
official `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
binary SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
Linux x86_64 musl/stdio. The finite loopback peer/provider implements backend
WebSocket and Responses messages, never app-server requests. Actual Codex
receives a genuine delegation and starts its native backing turn. No case sends
client `turn/start`. This extends the [delegation profile](ordinary-realtime-delegation-qualification.md)
and preserves all earlier [mode-routing checks](ordinary-realtime-mode-routing-qualification.md).

Each case starts from the same explicit V3/WebSocket/Cove, commentary-mode
request and original response prefix. Only one selected field becomes actual
JSON `null`; the other two remain explicit:

| Original request field | Required actual behavior |
| --- | --- |
| `transport: null` | WebSocket connection at `/v1/live?model=owned-v432-realtime-model` |
| `version: null` | V3 from the exact frozen `[realtime]` configuration table |
| `voice: null` | Cove from the V3 builtin `default_v1`, with no configured voice |

Full original request/JSON/Wire/schema/correlation assertions retain the
selected key and its null value. The version case inspects the frozen exact V3
table. The voice case requires that unique table to end immediately at
`[analytics]`, so a configured voice cannot hide elsewhere in that table. Input
snapshots also require the frozen configuration to match the final file.
The independent peer oracle requires this exact session update in every case:

```json
{"type":"session.update","session":{"instructions":"Owned local realtime start","audio":{"output":{"voice":"cove"}},"delegation":{"type":"client"}}}
```

The native public started notification must report V3. Exactly one Responses
request and one backing turn produce the original enriched handoff transcript,
wrapped model input and literal assistant result. The backend must receive:

```json
{"type":"session.context.append","channel":"commentary","content":[{"type":"input_text","text":"Owned delegate result λ\n\nOwned bounded assistant result 🙂"}]}
```

Each case retains two completed native items, three provider SSE events and all
six canonical timeline rows. Original body base64/size/SHA256, native IDs,
correlated RPC lists, original notification bytes and schema checks remain.
Loaded `thread/read(includeTurns:true)` is the persistence barrier. Repeated
warm/cold reads require identical full history/timeline and no new realtime
session or inference. Every timeline row binds its original canonical ordinal;
raw snake_case realtime records remain distinct from public camelCase items.
Requested-stop EOF must precede teardown. All original frame/body/request,
capture/journal/rollout, socket/handler and deadline caps, plus owned native
process/Port/PID/listener cleanup, remain unchanged. No timeout increase,
sleep, assertion removal or runtime change is introduced.

The source normalization chain is pinned to the complete files in the final
binding. `app-server-protocol/.../v2/realtime.rs:260–266` declares the three
optional fields; `app-server/.../turn_processor.rs:1286–1302` forwards them.
`core/src/realtime_conversation.rs:1371–1374` selects WebSocket for absent
transport; `:1397–1401` selects configured version; `:1427–1432` enables
configured voice use for WebSocket. `config/src/config_toml.rs:669–686` and
`core/src/config/mod.rs:4573–4584` preserve the supplied V3 table and absent
voice. `realtime_conversation.rs:1596–1600,1613–1646` selects FramelessBidi and
the builtin V1 voice default for V3. `protocol/src/protocol.rs:349–403` defines
that default as Cove, while V2 uses Marin. The frameless writer serializes the
resolved voice into the actual session update. The existing real delegation,
enrichment, model, persistence and timeline production chains are retained.

These observations qualify only owners **5972/5975/5978**, the exact null
variants of transport/version/voice. Upstream Option normalization makes each
selected null observationally equal to omission afterward. Original null
acceptance and resulting behavior receive scoped evidence; omission/default
recognition does not. Alternate configured versions/voices, other transports,
null combinations, other fields, streaming, repeated delegations, remote media
semantics and whole-method completeness remain unverified.

The focused module passes **17/0**, retaining all fourteen prior cases, seed
501432. Log `/tmp/samgita-v490-startup-null-focused.log`, SHA256
`42642564689dd321e9eabae37b09e52d69c6c17be1566bd9d809ca841fe7cf4e`.
Final **53 files / 96 ordinary real-binary cases at both seeds 501432/987654**,
three selected neutral WebSocket cases at each of 455834/501432/987654, outside
consumer **1/0**, warning-strict compile, format, inventory consistency, strict
Credo, forced Dialyzer and assets all pass. All **14** reviewed steps complete;
all **1,668** before/after guarded source hashes agree. Exact commands/logs are
under `/tmp/samgita-ordinary-v490/`; `results.json` SHA256
`85c025c79dbf6fe3f57fc16ae9a3e7a1dbeb1bc05d1f3788dfa40ade850a4973`,
`source.json` SHA256
`eaa7cd483e022f747fef35bbcc66d97eafd41ea269d1cab5a15aa26e24fce97f`.
Reviewed fingerprint:
`c9a70c1db29d96480e6e8e5ddc9cc9a5e11fd190871dbb4f26a5b222da1a0d7b`.
The final three-node/test/source binding checks **39** complete producer files
against the immutable archive binding:
`/tmp/samgita-v490-startup-null-binding/source.json`, SHA256
`fb1b668131400034a8470c04eddcfab19cb3b70de9a2fabb4177e91ab081dac5`.
Counts are **5,451 implemented / 1,054 missing / 116 blocked** contracts and
unchanged **462 implemented / 12 missing / 11 blocked** requirements, zero
verified. Next scoped work is genuine delegation filler=true, null prefix and
response-items=false output branches; pinned source is reviewed, runtime unrun.

Fixed YOLO is ordinary launch setup. No security, credential, authentication,
authorization, permission or approval test/audit, broad suite or hosted workflow
is run. A11, unavailable emitters, external/OS/full-goal and release gates remain
incomplete. There is no real model-service, full-compatibility, database,
publication or deployment claim. Rollback reverts this test/fixture/evidence
unit without touching persisted data.
