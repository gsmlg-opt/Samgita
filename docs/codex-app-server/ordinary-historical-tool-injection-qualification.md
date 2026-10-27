# Historical tool evidence without execution replay

V512 extends the idle injection module after `778e9b8` on existing `main`.
Official target: `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The unchanged local assistant peer supplies only model output. Real stock
Codex owns injection, history, callbacks and persistence. Production runtime,
fixtures, shared helpers and the preceding idle case remain unchanged.

## Evidence flow

The new case registers the known synthetic `fixture_lookup` dynamic tool and
injects one complete historical `function_call` plus its matching
`function_call_output`. Independent literal maps define request, durable and
provider representations. Both item IDs, call association, nonempty JSON
argument bytes, Unicode output and source turn provenance are explicit.
The output supplies a fixed numeric `create_time`; native preserves it rather
than generating an unpredictable value. These variants do not acquire the
Message-only `content_item_kinds` annotation.

Immediately after the original native injection ACK, before another RPC or
closure can cause a checkpoint, the actual rollout must contain the complete
pair exactly once and in order. Selection by IDs, call ID, arguments and output
independently detects duplication or changed association. There must be zero
model requests, callbacks, dynamic-tool execution items or started turns.
Known tool registration does not make imported call syntax executable.

Confirmed warm shutdown precedes a distinct cold native process. Explicit
resume uses the same thread UUID and returned rollout path. It preserves both
full original durable rows, including timestamps/metadata, with zero inference
or tool execution. The whole original warm wire prefix also remains unchanged.

Exactly one explicit fresh user turn then makes exactly one real provider
request. Its input must contain both complete historical items once, followed
by the new user message. Only internal metadata is removed by the fixture
provider projection; prefixed IDs, exact argument string and exact output remain.
The genuine native answer completes that one turn without a dynamic callback
or execution item. Disk rows and original capture stay identical after final
shutdown. Workspace files remain empty.

This distinguishes historical tool evidence from newly generated executable
model output. It does not establish external tool/provider success or permit
automatic replay after an ambiguous mutation.

## Immutable source

The [idle injection path](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/inject.rs#L74-L103)
records annotated conversation items and does not invoke ToolRouter. Executable
dispatch belongs to [new model output](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/stream_events_utils.rs#L315-L361).
`session/mod.rs:3481–3558,3610–3638,3720–3752` and the local live writer await
prepared history append. Existing turn/create-time values are preserved.

`protocol/src/models.rs` defines omitted optional fields and the plain-string
output serialization, without an invented success wrapper. Image preparation
does not classify plain FunctionCall/string-output values as Messages.
History normalization keeps the matched pair; it need not synthesize an
`aborted` output for this call. `client.rs:1007–1025,1092–1102` removes internal
metadata and preserves these explicitly prefixed item IDs in provider input.

Fourteen complete upstream source files match the official immutable archive.
Evidence `/tmp/samgita-v512-source-evidence.json`, SHA256
`e929de20b7a97a8e7dcf640d4d407a63263091677d77af16fb3dde651b952b50`.
The original additions-only patch reconstructs the unchanged V508 base by
removing precisely the three new attribute/test/helper sections. Independent
review checks source-defined field omission, stamping, ID projection, matched
call normalization and the absence of an injection-side execution path.

## Qualification and limits

The exact owning module passes **2/0** at seed501432 in3.5s, including the
retained idle-message case:

```sh
mix test test/native_injected_history_lifecycle_test.exs --warnings-as-errors --seed 501432
```

Original log `/tmp/samgita-v512-focus-501432.log`, SHA256
`7f39420030a2930336778f4350e2ddd9d0533e4410ae5cb2c09454d9e6c12b79`.
Final formatted module SHA256
`c6761c0fab50b41099b0cd2fd7ae2fe6a7200243d3c15d6ab9759db54ea0003a`.
Combined-source results and repeated seeds are recorded below.

Existing bounds stay30s per case,5s per operation/wait,128 frames/events and
1MiB total/rollout,64KiB inbound/4KiB outbound,128 rollout rows and two sequential
owned native processes. Cleanup proves owner completion, closed Port and
absent native PID. No sleep, polling, private-state mutation, retry, manufactured
history or weakened assertion is used. Rollback removes only the new pair's
attributes/test/helpers and linked supplemental records; it retains V508,
V510, runtime, persisted platform records and process-cleanup fixes.

This adds behavior evidence to the existing five request owners, with no new
physical-node credit. Counts remain **5,482 implemented / 1,009 missing /
130 blocked** contracts and **462 implemented / 12 missing / 11 blocked**
requirements, zero verified. Other raw-item/default/error/transport/deployment
variants remain incomplete. Fixed yolo is ordinary launch setup. No security,
credential, authentication, authorization, approval or permission test/audit,
broad suite or hosted workflow runs. A11, source-unreachable emitter paths,
external/OS success, complete compatibility and release remain incomplete.
Nothing is published, deployed or migrated in production.

## Final combined-source functional qualification

All **14 reviewed steps** in `scripts/codex/check_ordinary.py` pass on the
combined V510/V512 executable source:

| Check | Result |
| --- | --- |
| Explicit 63-file ordinary native selection, seeds501432/987654 | **124/0 each**,211.901s/212.357s command time |
| Selected WebSocket overflow/replay cases, seeds455834/501432/987654 | **3/0 each**,13 other mixed-file cases excluded |
| Outside-umbrella actual-native consumer | **1/0**; no Repo/Phoenix/umbrella available |
| Driver/root warning-free compile and format | Pass |
| Inventory consistency, strict Credo, Dialyzer, assets build | Pass |

All **1,682** guarded source hashes remain identical before/after and match the
delivered executable source. Fingerprint:
`a35c55d8dfa094e894ecefaa973db0a6b581601b5e927ef2f6ee79b67ef7b779`.
The final binding rechecks22 complete immutable producer files, five existing
physical schema nodes, retained helper/fixture/runtime hashes and the pinned
binary. The older idle module's40 original AST declarations remain unchanged
and in order; active helper extraction retains exactly the original162
assertions. The first temporary AST comparator retained remote-call line
metadata; correcting that comparator changes no repository source or test.

| Artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-v510-v512-qualified/results.json` | `4da886f7c03e865253081241f5749ee5aa5e9c375359973d6ed7d6c10da441f7` |
| `/tmp/samgita-ordinary-v510-v512-qualified/source.json` | `ee9dac6066384ef4379afff0850eadf6e0c3882208688f88b7e850e013195e28` |
| `/tmp/samgita-v510-v512-final-binding/source.json` | `3d4479df06c7cbf1389917d87891c5294a4be120265f682d4a8329113d4b30ca` |
| `/tmp/samgita-v510-v512-static-binding.json` | `328bdfb3fe365ebe9dcc9be740e4ab873e7e0cb6edd0fa69c5dd32a86ba6bcee` |

These results qualify the named ordinary selection. They do not replace the
prohibited broad/security/permission/hosted checks, final full-compatibility
gate, A11 or external/OS prerequisites. Existing tests and gates stay intact;
automatic CI is suppressed on delivery. No release or deployment follows.
