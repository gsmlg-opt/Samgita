# Ordinary native V3 handoff mode routing

V487/V488/V489 (2026-10-28) add three real Codex scenarios for exact handoff mode
values. The immutable target is official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
Linux x86_64 musl/stdio. The finite loopback backend/provider does not implement
app-server messages. Actual Codex receives the genuine backend delegation,
starts a native backing turn, constructs the model request, forwards results
and persists original events. No scenario sends client `turn/start`.
The separately qualified [delegation](ordinary-realtime-delegation-qualification.md)
and [public-summary relay](ordinary-realtime-summary-relay-qualification.md)
retain their exact assertions in the shared journey.

The BEM scenario explicitly requests `codexResponseHandoffMode: "bemTags"` and
`codexResponseHandoffChannelPrefixes: {"commentary": ["[OWNED_PROGRESS]"]}`,
omitting the extra response-item prefix. One finite Responses request supplies
two phase-less assistant items, preserving fixed provider/native IDs and exact
texts. The independent live-backend oracle requires these two frames in order:

```json
{"type":"session.context.append","channel":"commentary","content":[{"type":"input_text","text":"[OWNED_PROGRESS]Owned bounded progress λ"}]}
{"type":"session.context.append","channel":"speakable","content":[{"type":"input_text","text":"[FINAL]Owned bounded final 🙂"}]}
```

The custom commentary tag provides the distinguishing effect: unrecognized
phase-less text would take the speakable fallback. Header bytes remain in
provider output, native items, backend frames and durable history. The
second literal final result is preserved, but its output is observationally
identical to fallback. It earns no default `[FINAL]` recognition credit.
Backend BEM classification does not imply that public native items gain a
derived phase. All three native completed items (user, progress, final) and the
complete seven-row canonical timeline are required, including the extra
progress item's exact ID, position and original public payload.

The Thinking scenario explicitly requests `codexResponseHandoffMode: "thinking"`
and retains the original V485 prefix and assistant result. Its exact backend
frame is:

```json
{"type":"session.context.append","content":[{"type":"input_text","text":"Owned delegate result λ\n\nOwned bounded assistant result 🙂"}]}
```

This full-map assertion requires the `channel` key to be absent. The original
explicit RPC and correlated success response remain captured. V485's unchanged
commentary case is the same-text positive control with an explicit channel.
Thinking intentionally equals omitted/null mode after upstream normalization;
the scenario cannot distinguish explicit selection from that default. It gives
only explicit-literal and resulting-wire evidence, no default/null/omission
recognition or remote provider interpretation credit. Exactly two native items
and the full six-row canonical history remain required for this scenario.

A third independent scenario keeps the original RPC's
`codexResponseHandoffMode` key explicitly present with actual JSON `null`.
Pinned `Option` normalization selects Thinking and produces the same exact
no-channel backend map. It earns only explicit-null branch evidence; omission,
default recognition and other nullable parameters remain unverified. Its one
turn, two native items and full six-row timeline retain all existing checks.

All cases preserve the real enriched handoff transcript and exact wrapped
model user text, original raw-body base64/length/SHA256 and actual thread/turn
metadata. All original native notices and RPCs undergo Wire/schema checks.
Loaded full history supplies the persistence barrier before full ascending
turn/timeline reads. Every row maps to a canonical rollout ordinal; raw/public
realtime representations remain separate. Repeated warm/cold reads create no
inference or realtime session and preserve rollout, peer journal and frozen
fixture inputs. Requested-stop EOF precedes teardown. Existing count, socket,
handler, HTTP, frame/body, capture/journal and deadline bounds and owned
Port/PID/process/listener cleanup are unchanged; each scenario requires one
model request and two HTTP requests.

Pinned source: `protocol/src/protocol.rs:1830–1842` declares the mode enum;
`app-server/.../turn_processor.rs:1253–1270` passes mode and map into core.
`core/src/realtime_conversation.rs:959–993` applies BEM routing only locally;
`core/src/realtime_conversation/bem.rs:5–27` matches the selected exact custom
prefix. Original provider IDs survive `core/src/event_mapping.rs:149–201`.
`realtime_conversation.rs:2343–2363,2483–2493` chooses the writer/channel and
forwards completed conversation items. Thinking keeps the original None channel
from `codex-api/.../methods.rs:318–327`; frameless writer methods and
`protocol.rs:70–75` omit it with `skip_serializing_if`. V3's internal V1 session
kind exits the separate completion-ACK branch. The real delegation/enrichment,
native turn creation, persistence and timeline chains remain source-bound to
the preceding profiles.

Pre-execution review corrected an overly broad draft claim about default final
tag recognition and extracted the provider-item assertions without changing
old expectations. The first focused run passes **13/0**, retaining all eleven
prior cases. Adding the explicit-null case passes **14/0**. Final reviewed
matrix and source binding follow below.

Focused logs: `/tmp/samgita-v487-mode-routing-focused.log`, SHA256
`3c9382eb8c376bda5a3257d20247a63fd1292208e396a46140fc4ea42c84efdf`,
and `/tmp/samgita-v489-mode-null-focused.log`, SHA256
`d54ab0da262e0e0a3e9f7ae4adc64882721c0e94c4c1b5f4c17d3bb2db5baf09`.

Only physical owners **93/5931/5952** (BEM literal/custom map), **91/5929**
(Thinking literal) and **5955** (explicit-null mode) gain scoped implemented
evidence. Other prefix maps, headers,
phases, nullable/default branches, flags, streamed/chunked output, multiple or
steered delegations, providers, versions and transports remain unverified.
This is no real model-service or complete compatibility claim. Fixed YOLO is
ordinary launch setup; no security, credential, authentication, authorization,
permission or approval tests/audits, broad suite or hosted workflow run. A11,
unavailable emitters, external/OS/full-goal and release gates remain incomplete.
No runtime, database, publication or deployment change. Rollback reverts this
test/fixture/evidence unit.

Final **53 files / 93 ordinary real-binary cases at both seeds 501432/987654**,
three selected WebSocket cases at each of 455834/501432/987654, outside consumer
**1/0**, warning-strict compile, format, inventory consistency, strict Credo,
forced Dialyzer and assets all pass. All **14** reviewed steps complete; all
**1,668** before/after guarded source hashes agree. Exact commands/logs:
`/tmp/samgita-ordinary-v489/`; `results.json` SHA256
`62b1d6a42308380c32e9b05ffc0459e5077da0340a1e55f4f8ef0de3ff6f9597`,
`source.json` SHA256
`7b7ef39135f7beb1fc139645e374bea64ca33f90c6d908bfb34ab363b1d93ccd`.
Reviewed fingerprint:
`5cc3d2a9e84cf16aba7735a8fa52dae2af86b96becdc26b4a678e92e509720bb`.
The six-node/final-test/source binding checks **37** complete producer files
against the immutable archive binding:
`/tmp/samgita-v489-mode-routing-binding/source.json`, SHA256
`7e9ce34e0aeeaf4cc42d7924cb96277ca756dc308bf4ab269ae8d165c035d197`.
Counts are **5,448 implemented / 1,057 missing / 116 blocked** contracts and
unchanged **462 implemented / 12 missing / 11 blocked** requirements, zero
verified. The reviewed selection does not replace incomplete full-compatibility
or release gates. Next source-confirmed ordinary candidates are independent
explicit-null transport, version and voice startup branches; runtime is unrun.
