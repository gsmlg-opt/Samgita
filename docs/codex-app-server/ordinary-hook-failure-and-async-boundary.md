# Ordinary PostToolUse failure and upstream async suppression

V500 follows `611aa50` on the existing `main`, with unchanged official Codex
`rust-v0.163.0` source `83086188ae0614bd882818ff1aa23f3194962012` and binary
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The client runtime and pinned upstream sources are unchanged. The local model
peer supplies Responses items; only stock Codex emits app-server notifications.

## Real observer failure after successful execution

`native_tool_hook_test.exs` retains its original successful journey and adds a
second explicitly tagged case. Both use the same one finite native printf
command, two real hook processes, two ordinary turns and three finite model
responses. PreToolUse remains inert success. The new PostToolUse observer
verifies the actual command's independent output/file and exact native stdin,
writes its exclusive record, returns `{}` and exits7. Its CLI permits only0/7.
It emits no decision or control output and never exercises an exit2 branch.

The full original post completion must contain `status: "failed"` and exactly
one entry `{kind: "error", text: "hook exited with code 7"}`. The actual tool
still exits0 with the exact Unicode effect/stdout. Both turns, exact provider
consumption, complete native envelopes, final assistant summary, distinct exited
PIDs, unchanged invocation records and original input/config bytes must satisfy
the original successful oracles. The independent watcher completion is still
positively observed with the supported partial orders. No reply or receipt
substitutes for physical effects or process exit.

The immutable producer explicitly maps this ordinary handler failure:

- [post_tool_use.rs](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/hooks/src/events/post_tool_use.rs#L178-L187)
  initializes empty continuation data; its generic nonzero branch at276–305
  supplies the exact failed/error outcome.
- `hooks/src/engine/command_runner.rs:214–309` records the actual exit code;
  `core/src/tools/registry.rs:811–880` runs the observer after successful
  execution and preserves its result when continuation data is empty.
- `core/src/hook_runtime.rs:297–328,875–927`, app-server
  `bespoke_event_handling.rs:1147–1165` and protocol `v2/hook.rs:69–157` own
  the real event and full wire conversion.

Physical owners2231 (HookOutputEntryKind/error) and2236 (HookRunStatus/failed)
were already implemented through a historical mixed profile. This adds separate
ordinary native evidence; it promotes no new implemented or verified owner.
The historical mixed profile remains preserved and unrun under the current
restriction. No nonexistent `PostToolUseFailure` event is introduced: the entire
pinned Rust tree has zero such identifiers, and PostToolUse itself requires a
successful tool result.

## Async lifecycle notifications have no stock producer

Exact physical owner2220 is
`ServerNotification.json#/definitions/HookExecutionMode/enum/1`, value `async`,
canonical SHA256
`bf4b3fff6944a7ce4f1371b095bc9b88545cd3effd59e955b8701c4fd015fd8b`.
It becomes **blocked**, with native success still incomplete.

The shared production gate is explicit:

```rust
!run.builtin && run.execution_mode == HookExecutionMode::Sync
```

[hook_runtime.rs:875–927](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/hook_runtime.rs#L875-L927)
applies it to both HookStarted and HookCompleted after preserving metrics. The
[upstream test at1141–1236](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/hook_runtime.rs#L1141-L1236)
explicitly documents that async and builtin lifecycle notifications are hidden.
That test is source evidence; it was not executed as acceptance here.

`hooks/src/engine/mod.rs:144–158` derives Async; dispatcher134–143 and
command_runner116–169 schedule the actual internal completion. Core
hook_runtime775–817 drains it, then the same Sync gate prevents public emission.
The app-server's sole conversion path is bespoke_event_handling1147–1165;
the complete reference scan finds no alternate production emitter.

All **5,259** Rust files match the immutable source archive byte-for-byte;
the full `HookExecutionMode|HookStarted|HookCompleted` scan contains177 references
in47 complete files. Source records retain all47 reference-file hashes and51
complete producer/reference hashes. The archive SHA256 is
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
An independent review reproduced the file set, references and hashes.
Artifacts: `/tmp/samgita-v500-source-integrity.json`,
`/tmp/samgita-v500-async-reference-hashes.json` and
`/tmp/samgita-v500-async-rust-reference-scan.txt`.

The separate `hooks/list` command metadata boolean `async:true` is reachable
through discovery683–690 and catalog_processor72–89. That is implemented
owner4151, whose response cannot qualify notification owner2220. SessionEnd
normalizes its configured async handler to Sync, so it provides no bypass.
No mock event, changed upstream process or alternate version supplies missing
native evidence. The original required contract remains present and blocked.

## Qualification and remaining gates

Focused independent-driver command:

```sh
mix test test/native_tool_hook_test.exs --warnings-as-errors --seed 501432
mix test test/native_tool_hook_test.exs --warnings-as-errors --seed 987654
```

Both original success and new failure pass **2/0** at each seed,4.0s each, in
`/tmp/samgita-v500-ordinary-failure-focus.log`. Python AST validation passes;
the fixture SHA256 is
`b3448710bdfe713247ed3390ffc9ab0bd5d3f2d0ef850df682ddbc1e9c4ac88e`.
An extra root `mix credo --strict` invocation omitted `MIX_ENV=test`; its
default dev build failed before Credo in dependency BEAM type checking
(`Telemetry.Metrics.ConsoleReporter.terminate/2`, `beam_lib` badarg). Original
log: `/tmp/samgita-v500-strict-credo.log`. No dependency source or cache was
removed or repaired. The exact intended test-environment command
`devenv shell --no-tui -- env MIX_ENV=test ERL_FLAGS='+S 2:2' mix credo --strict`
passes across591 source files; log
`/tmp/samgita-v500-strict-credo-test-env.log`. The default-dev error is separate
from this passing environment; no broader environment-repair claim follows.
The final command
`devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v500-qualified`
passes **14/14** reviewed checks: **59 files / 110 actual-native cases at both
seeds501432/987654** (188.6/188.7s), selected WebSocket cases at all three seeds,
outside consumer **1/0**, inventory, warning-free driver/umbrella compilation,
format, strict Credo, Dialyzer and assets. All **1,676** guarded sources remain
identical; fingerprint
`a5a7e6d16d1f42081d18333f64072b8f933b4170d82eb852a698cc2f6bc33d16`.
This functional selection executes none of the prohibited or hosted gates.

| Final record | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-v500-qualified/results.json` | `464ae88539a0dadd50190fcb59f85b3105daac7634469cd8850d548e4026e853` |
| `/tmp/samgita-ordinary-v500-qualified/source.json` | `d3b605d6e34c9bd3a1b8c03574fabd04998bcbd86097c68148e84c1323aaa2d8` |
| `/tmp/samgita-v500-binding/source.json` | `df53806af9606a0df9dd236d986951c4522d09d61c6d4a35a87025ffa520adf9` |

The binding checks51 complete producer/reference files against the immutable
archive index, all four precise canonical nodes (including the separate catalog
boundary), and final owning test/fixture/helper bytes against the passing source.
No final-source or native-emission claim is inferred from the earlier matrix.

Per-case bounds stay60s/20s/5s/1s for test/journey/observation/hook; capture,
request, journal, invocation, process and owned stdio cleanup limits are the
same as the [preceding unit](ordinary-hooks-and-control-qualification.md).
No assertion, deadline, ordering rule, retry behavior or cleanup is weakened.
The original success case still requires completed/empty-entry post output.

Only the exact async node changes missing→blocked. Counts become **5,464
implemented / 1,040 missing / 117 blocked contracts**, with unchanged **462
implemented / 12 missing / 11 blocked requirements**, zero verified. Fixed YOLO
is setup only; no security, credential, authentication, authorization,
permission or approval test/audit, broad suite or hosted workflow runs.
Those retained gates, A11, upstream-unreachable legacy behavior, external/OS
profiles, full compatibility and release remain incomplete. No publication,
deployment, database or credential change occurs. Rollback removes this test/
fixture/evidence extension without changing persisted data.
