# Native command execution lifecycle

This unit targets immutable Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The real executable handles `command/exec`, `command/exec/write`,
`command/exec/resize`, `command/exec/terminate` and streamed
`command/exec/outputDelta`. The executed program is an owned synthetic Python
fixture, with no model turns, credentials or external services.

The native server starts explicitly in a disposable private user/network
namespace and accepts WebSocket connections over its private Unix socket.
Its environment is allowlisted, its home/config/tmp are disposable, and its
model/provider configuration points to an unavailable loopback port. The
synthetic command verifies that its network namespace differs from the caller,
contains only loopback interfaces/routes and has no default route. Missing
Linux namespace support, `unshare`, `ip`, Python or the pinned executable fails
explicitly; there is no skip or host-network fallback. Native `dangerFullAccess`
is used only inside this isolated fixture so that command semantics are tested
without claiming qualification of Codex sandbox enforcement.

Eight native cases pass:

| Case | Observable behavior |
| --- | --- |
| Buffered execution | Exact stdout/stderr, nonzero exit, cwd, environment override/unset and native parameter errors before execution. |
| Pipe streaming | Correlated binary output, binary stdin chunks, explicit EOF, separate final response and rejected late write. |
| Output caps | Independent per-stream caps, `capReached`, continued active process and empty streamed final output. |
| PTY | Implied stdin/output streaming, merged stderr, initial dimensions, invalid/valid resize and input after resize. |
| Active controls | Duplicate active ID rejected without another process, invalid write/resize/missing IDs, terminate acknowledgement separate from final execution result. |
| Native timeout | Native timeout yields exit 124 and actual process exit, rather than driver-side unknown outcome. |
| Local abandonment | Driver abandonment leaves the command running and records uncertainty; explicit remote termination produces a late response without clearing uncertainty automatically. |
| Connection ownership/reconnect | Same IDs are scoped to connections, foreign controls reject, reconnect terminates only the old connection's command, no replay occurs, and borrowed clients do not stop the shared native server. |

Tests use explicit output and process markers as barriers. Fixture cleanup must
confirm command/native process reaping through the existing owned-process
guardian before deleting the workspace. Client connections borrow the socket;
only fixture ownership authorizes stopping the native server.

Pinned source references relative to `codex-rs/`:

| Contract | Source |
| --- | --- |
| Parameters, environment, timeout and profile validation | `app-server/src/request_processors/command_exec_processor.rs:105-185` |
| Method dispatch and connection cleanup | `app-server/src/request_processors/command_exec_processor.rs:35-83` |
| Process identity, streaming requirements and duplicate rejection | `app-server/src/command_exec.rs:142-315` |
| Connection-scoped write/resize/terminate and disconnect | `app-server/src/command_exec.rs:317-453` |
| Execution, timeout, streams and final outcome | `app-server/src/command_exec.rs:456-654` |
| Write and terminal-size validation | `app-server/src/command_exec.rs:656-711` |
| Native wire types | `app-server-protocol/src/protocol/v2/command_exec.rs` |
| Upstream buffered/env/validation/cap/pipe/PTY/ownership examples | `app-server/tests/suite/v2/command_exec.rs:42-201,616-1248` |

The explicit profile filename is `test/native_command_lifecycle_profile.exs`.
It requires the declared Linux namespace environment and is run as a mandatory
isolated CI step; it does not enter default test discovery on environments
without that prerequisite.

Validation on 2026-10-24 used `main` at
`8331b9977d50ffd7615c962c3b2cd79e6eb5e3f2` plus the new owned profile/document.
Commands ran serially from `apps/samgita_codex_driver` through
`devenv shell --no-tui --` with the canonical absolute pinned executable:

```sh
mix format test/native_command_lifecycle_profile.exs
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl \
  mix test test/native_command_lifecycle_profile.exs --seed 501432
MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl \
  mix test test/native_command_lifecycle_profile.exs --seed 987654
mix format --check-formatted
```

Warnings-as-errors compile and format check passed. Both final native runs
passed **8 tests, 0 failures**, with no skips or warnings (3.8 and 3.7 seconds).
The initial seed 501432 run also passed all eight cases; it emitted one unused
default-argument warning. Removing that unused helper default changed no test
behavior, and both seeds were rerun afterward. The initial log is
`/tmp/samgita-native-command-lifecycle-501432-initial.log`; final commands and
both seeds are in `/tmp/samgita-native-command-lifecycle-final.log`. No failed
behavioral repair round occurred. Python AST parsing of the embedded command,
the local binary SHA256 and `git diff --check` passed. Test teardown confirmed
owned command/native process reaping, and no owned fixture directories remain.
No Samgita platform, Repo or database was required.

These cases do not establish live provider integration, Windows/sandbox/remote
environment behavior, every native transport, or full app-server compatibility.
Command completion is an execution result and never Samgita Task acceptance.
Reconnect and local request IDs confer no upstream idempotency guarantee. A11
remains a separate platform blocker. No publication or deployment is performed.
