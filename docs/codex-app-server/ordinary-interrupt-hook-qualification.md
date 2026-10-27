# Ordinary root Interrupt Hook lifecycle

V428 is delivered after the separate V431 status unit on `main`
`0189a6dad3c644fc6ff1c631910989604681912e`. Its actual combined execution base
is `df0e9a2ae7820799a823f87430d30d45c40c1c02`; all411 final executable-source
hashes retain the tested bytes. Only physical owner2210 becomes scoped
implemented: `schema:ServerNotification.json#/definitions/HookEventName/enum/11`
with literal `interrupt`, canonical SHA256
`08f6e16aed9ba0770632629567abd32d518e1eb41c4ead48e80735cc734f089b`.

The new [ordinary case][test] launches the official pinned native executable
with fixed YOLO. The [local fixture][fixture] configures one predeclared harmless
Interrupt command, synchronous with timeout1s and a fixed Unicode status message.
Public hooks/list plus config/batchWrite prepare only that exact handler as
positive fixture setup. No trust-state assertion, alternate policy, permission
decision or negative authorization behavior is tested. The historical mixed
Hook profile is not imported or run.

One actual root thread and turn reach both the native turn/started event and a
deterministic held-HTTP-request barrier. Exactly one explicit turn/interrupt
returns the original correlated `{}` result. Codex itself invokes the hook and
emits the complete ordered lifecycle:

```text
turn/started -> hook/started -> hook/completed -> turn/completed(interrupted)
```

Each complete independent HookRunSummary requires the exact ID
`interrupt:0:<owned config path>`, eventName interrupt, handlerType command,
executionMode sync, scope turn, source user, exact sourcePath/displayOrder0 and
`Owned ordinary Interrupt λ🙂`. Started requires running and explicit null
completion/duration; completed requires completed and bounded numeric times.
Both require empty entries. Full independent Turn maps, original native thread/
turn IDs, rootTurnId, error:null, Unix-second times/duration, native emission
milliseconds, current generation and canonical schemas are checked. Started/
completed Hook timestamps are independently bracketed; no equality assumption
or interrupt-ACK/terminal arrival ordering is invented.

Original incoming JSON before Session decoding must equal every selected
notification in order. Every RPC joins complete original outgoing/incoming
bytes/maps by its actual request ID. A native thread/read barrier followed by
drain checks the final observation without treating a sleep as proof of silence.
Pending interactions, uncertain operations and gaps remain empty.

The hook receives genuine native stdin and writes exactly one exclusive record
containing only event/session/turn/cwd, its PID and the fixed marker. It bounds
stdin at64KiB and the record at4KiB; full input and permission fields are neither
inspected nor retained. The actual handler PID must be gone. The provider
records only allowlisted functional request facts, with exactly one request for
the actual thread/turn and zero response events. It sends no HTTP headers,
model completion, tool call or app-server frame. Native cancellation supplies
the outcome. Provider shutdown releases the held handler before joining it,
including failure teardown; final handler count is exactly one with no errors.
Frozen configuration/catalog/script, empty workspace and checked native/provider
owner completion, closed Ports and vanished owned PIDs remain required.

Official target: `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Ten complete upstream files match the immutable source archive. The public
interrupt handler (`request_processors/turn_processor.rs:1619–1663`) submits
native interruption; `core/src/tasks/mod.rs:829–843,977–999` runs Interrupt
hooks before abort notification. `core/src/hook_runtime.rs:502–541` emits the
actual pair; `hooks/src/events/interrupt.rs:43–138` executes the command and
maps exit0/`{}` to completed with empty entries. The native dispatcher supplies
timings/order/IDs; `bespoke_event_handling.rs:1147–1165` preserves the pair on
the public wire. No mock emitter substitutes for these producers.
`/tmp/samgita-v428-source/evidence.json` SHA256:
`2a1d8f6dc898bdcf4a140ff482e57c84c12c3f558e74c869d909d5cc22b52dff`.

Initial and final focused actual-native checks pass **1/0**. The final combined
27-module ordinary block passes **45/0** at501432/987654,74.137/74.289 command
seconds. Ten Python syntax checks, scoped format, driver compile with warnings
as errors, root strict Credo and inventory consistency pass. All411 sources
stay stable:408 prior paths unchanged, one separately owned status test changes
and these two files are new. Limits remain128 combined raw frames/events/2MiB,
64KiB inbound/8KiB outbound,5s startup/RPC,20s active/60s case; provider request/
journal limits1MiB/2MiB. Hook timeout remains1s.

Final test/fixture SHA256:
`840a112019e37a016283e541d47a888e43aed2d1066335b951191e592cf6d40a` /
`f44e7ccfd880b076090ece70735582fa7512fc71541c5ec66f2721590c2cc2d4`.
Exact commands/logs/source guard:
`/tmp/samgita-v428-v431-functional-checks/final/{results,source}.json`, SHA256
`66a2f7b93305dfed837c9c89f6e1eb27201076f4d8e40e9573c7243dc9aadc70` /
`805aaec99ddafc1dbc225042d03ef338af3ef868ba52300bf40d29bc7f69dd89`.
Binder `/tmp/samgita-v428-v431-bind.py --unit hook`; evidence
`/tmp/samgita-v428-binding/evidence.json` SHA256:
`7079053691633a963addb21a58fe0bcb020cb82b9d9267e5b49612b30418704d`.

Only2210 gains evidence. Other HookRunSummary fields were already implemented;
other events/sources, prompt/agent handlers, trust/permission decisions and other
OS/transports/backends are not qualified. Contracts become **5,197 implemented
/1,358 missing /66 blocked**; requirements remain **462 implemented /12 missing
/11 blocked**, zero verified. Prohibited security/credential/authentication/
authorization/permission/approval checks and audits, broad suites and hosted
workflows remain unrun. Existing gates, A11, unreachable producers and external/
platform/full-goal/release acceptance stay incomplete. Pushes suppress CI; no
publication or deployment. Rollback removes these two files and the single
binding while retaining runtime/history. Continue the genuine persistent-fork
Git notification profile; direct-start null metadata is not positive evidence.

[test]: ../../apps/samgita_codex_driver/test/native_interrupt_hook_test.exs
[fixture]: ../../scripts/codex/interrupt_hook_fixture.py
