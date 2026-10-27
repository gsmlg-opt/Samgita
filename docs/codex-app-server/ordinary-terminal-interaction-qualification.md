# Ordinary native terminal-interaction envelopes

V476 adds one finite actual-native stdin interaction against stock Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, binary
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The local Responses backend supplies three model-side exchanges, never
app-server frames. No external service, paid task, platform database or
security/credential/authentication/authorization/permission/approval test runs.
The native launch uses the fixed ordinary YOLO helper.

The first backend exchange requests real `exec_command` for an owned raw-TTY
stdin reader. The reader records its own PID and writes a ready marker.
The next backend request contains the actual running native session ID and
ready output; it remains held until the test has queried the live terminal and
explicitly released one local control request. The backend then requests
`write_stdin` with the known nonempty Unicode input `owned-terminal-input λ🙂`
and newline. The reader independently records the exact UTF-8 bytes, writes the
prescribed output, records completion and exits. The third exchange requires
the actual successful tool output before supplying final assistant text.
Unexpected requests, extra tool calls, incorrect bytes or backend errors fail.

Codex must emit exactly one original
`item/commandExecution/terminalInteraction` notification. Its independent
complete envelope binds the original exec item ID, current thread/turn, native
process ID and literal stdin. Original captured bytes, decoded driver event,
bounded emission timestamp, current generation and ordered unique sequences
must agree. The raw original follows the explicit release boundary.

The [write handler][write] supplies `WriteStdinInteractionEvent` with the
current session and turn. The [process manager][manager] holds the per-process
interaction lock through the nonempty-input interaction event at 1119–1133.
The [exit watcher][watcher] takes that same lock before completed publication.
This supports the retained `start < interaction < completion` notification
order. Core `completedAtMs` and app-server `emittedAtMs` come from different
tasks; each is independently bracketed by observed operation times. The case
does not assert an invented cross-task timestamp order.

Actual output, zero exit, gone reader PID and the live-to-empty terminal listing
are required. Native read/turns/items queries form persistence barriers. Exact
command content/times and exactly one persisted command item survive repeated
warm reads and a distinct cold native process. Direct cold item reads do not
load a thread or re-emit an interaction. The finite backend journal stays
unchanged across cold reads. Config, catalog, shell and reader bytes remain
exact, as do the frozen warm capture and original interaction bytes. Warm/cold
RPC method inventories and correlated original request/reply pairs are finite
and explicit. Owned native/peer owners, Ports, PIDs, reader, listener, sockets
and handler/server threads must finish before temporary-file removal.

Capture stays at 128 frames, 8 KiB outgoing, 64 KiB incoming and 2 MiB total.
RPC and observation bounds stay five seconds, with a sixty-second case limit
and twenty-five-second active scenario deadline. Source-only cross-review
supports the lock and timestamp distinction; runtime credit comes from the
actual checks below.

## Projection corrections and focused qualification

Two failed initial focused runs are preserved. The first **1/1**, 2.6 seconds,
incorrectly expected the terminal-list `osPid` to equal the reader PID. The
pinned [list projection][list] explicitly supplies `None` for OS PID, CPU and
RSS. The test now requires all three exact nulls and retains the independently
observed actual live/gone reader PID and byte/output/exit checks.

The next **1/1**, 2.6 seconds, exposed a separate command-text projection:
the [live process list][live] returns the original tool `hook_command`, while
the [item presentation][presentation] formats the complete shell argv.
The test now checks each against its independently prescribed value. Neither
runtime path nor source is changed. No assertion is skipped, no warning is
ignored and no deadline is increased. Paginated reads use supported
`includeTurns: false` plus explicit turns/items queries.

The first passing focused command, from the independent driver directory in Devenv
Elixir 1.18.5/OTP 27 with `MIX_ENV=test`, `ERL_FLAGS='+S 2:2'` and the pinned
`CODEX_BINARY`, passes **1/0**, 3.5 seconds:

```sh
mix test test/native_terminal_interaction_envelope_test.exs --warnings-as-errors --seed 501432
```

Original logs are `/tmp/samgita-v476-terminal-501432.log`,
`/tmp/samgita-v476-terminal-projection-501432.log` and
`/tmp/samgita-v476-terminal-final-501432.log`. The Python fixture passes AST
parsing. No mixed background-terminal or approval profile is imported.

The first combined fourteen-step run passed both **79/0** ordinary seeds and
the outside consumer before strict Credo failed on capture-handler nesting and
the backend assertion's complexity. Its original twelve completed results and
all 1,667 unchanged source hashes remain in `/tmp/samgita-ordinary-v476/`;
`results.json` SHA256
`f74a66e058937aca3cc068090473bc93abbbf7a19e9fcbc2575c473bb91508b3`,
`source.json` SHA256
`d3fc31a26d032935990d705f56c9d5e3be3bf374366cc7667feb5b72307301bf`.
Extracting `record_event` and `assert_backend_exchange` preserves every oracle,
deadline and bound without suppressing a rule or changing configuration. The
refactored focused case passes **1/0**, 3.4 seconds, in
`/tmp/samgita-v476-terminal-refactored-501432.log`, SHA256
`e191813b606d702c58c18e13b3e4a6eea5b5c9d90ef033d9c96f8f9ea25bebfe`;
strict Credo then passes on 586 files. Final combined evidence follows below.

## Exact binding and remaining scope

Fourteen complete producer/projection files match the
[official full-source binding](legacy-file-output-boundary.md), covering all
5,259 immutable Rust files. Both generated and vendored stable/experimental
schemas independently match each canonical node. Binding
`/tmp/samgita-v476-terminal-refactored-binding/source.json`, SHA256
`91ed89ed3526456884bf08d81e8f9fae0cf9068700378165517b876fa5bc7ba9`,
preserves the previous binding's hash and all focused failures/passes. Final
owning test SHA256 is
`9df3b4b6dde80dd1e5e0f375a5ba8b9c42b2515fa7151be57e1d1ab9f136999c`;
the unchanged Python fixture SHA256 is
`f0750739ee76f66023e95dac447579b77e462e6271b799536f52d82a4bff86fd`.

Only four physical `ServerNotification.json` owners gain scoped implemented
evidence: **2939–2942**, `/oneOf/39` and its method, method literal and params
reference. No nested alias/default/variant, entire method/schema, other
stdin/TTY variant, transport/OS/backend or external profile gains credit.
Separately, [four legacy file-output owners](legacy-file-output-boundary.md)
become source-blocked, with no native-success, test or transport credit.

The final reviewed matrix completes **14/14** steps in
`/tmp/samgita-ordinary-v476-final/`. Ordinary real-binary checks pass **79/0**
at seeds 501432 and 987654, in 135.642 and 133.223 seconds. All three selected
WebSocket cases pass at 455834, 501432 and 987654. The isolated consumer passes
**1/0**. Driver/root format, driver/umbrella warning-strict compilation,
inventory consistency, strict Credo, forced Dialyzer and assets build all pass.

All **1,667** guarded before/after source hashes are identical; reviewed
fingerprint
`7eb94d90c9ae11863d141f61e97be6cfa2433e837eef478bf5151c4cf04116aa`.
`results.json` SHA256
`31d380d1e43cb421443b993c35d7632ddfbd2b8646d4c0238db426e59fd509e1`;
`source.json` SHA256
`f7935d0a20d47b9386d30df1219bfd27f4a0d891ed87bfd0459bd3fbf7688dc9`.
The unchanged official binary/schema pin and actual reviewed commands are
recorded in those files. No prohibited profile or automatic workflow is run.

Current counts are **5,364 implemented / 1,141 missing / 116 blocked** contracts and
unchanged **462 implemented / 12 missing / 11 blocked** requirements, with zero
verified in both. Full compatibility remains active. Prohibited checks/audits,
broad/hosted workflows, A11, unavailable emitters, external/other OS/backend
success and release remain incomplete. No publication, deployment or production
migration.

[write]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/unified_exec/write_stdin.rs#L99-L119
[manager]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/unified_exec/process_manager.rs#L917-L918
[watcher]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/unified_exec/async_watcher.rs#L177-L240
[list]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L2496-L2522
[live]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/unified_exec/process_manager.rs#L1850-L1867
[presentation]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/item_builders.rs#L47-L62
