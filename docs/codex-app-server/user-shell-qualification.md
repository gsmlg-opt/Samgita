# Native user-shell lifecycle

This bounded profile targets Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The real executable produces all app-server responses/events in this profile;
only the Responses backend and executed program are synthetic. This qualifies
the scoped native behavior below, rather than live provider integration.

`thread/shellCommand` differs from standalone `command/exec`. Its immediate empty
response acknowledges submission. Completion arrives through `userShell`
command-execution items and turn notifications. It evaluates shell syntax on the
app-server host with full access, explicitly bypassing the thread sandbox and
managed proxy. It defaults to one hour for omitted/null timeout; zero means
immediate timeout. Timeout is a failed item with exit -1, while its independent
turn can still complete normally. An active turn receives an auxiliary item
without a second turn lifecycle. A borrowed client disconnect removes
subscriptions and does not terminate the native thread's shell command.
The native item conversion represents empty aggregated output as null, including
successful commands whose output was redirected; it does not return an empty
string for that case.

All native commands in this profile are fixed synthetic effects in disposable
directories. The controller enters a private user/network namespace with only
loopback and no default route; every command independently verifies that same
namespace before writing its marker. The actual binary is hash-checked by both
the test and controller. Environment/home/config/tmp/model catalog are isolated
and allowlisted; the only model peer is a synthetic loopback Responses server.
Missing namespace permission or required tools fails explicitly. There is no
host-network fallback, external credential, paid task or real Agent integration.

Eight passing native cases cover:

1. An immediate ACK while an owned command remains held, exact item/output/turn
   correlation, explicit release, and preserved safe pipeline/redirection syntax.
2. A failed nonzero shell item inside a successfully completed standalone turn.
3. Omitted/null/large/zero/bounded timeout semantics and owned process exit.
4. Native blank/negative/missing-thread errors and driver type validation before
   execution, with no unexpected turn or model call.
5. Auxiliary shell success while the original native approval remains unresolved,
   followed by explicit decline; no duplicate turn lifecycle.
6. Auxiliary shell timeout preserving the active turn and pending approval.
7. Persisted contextual shell output across explicit native restart, filtered
   command-execution history in read/list/fork, and no reexecution or model call.
8. Borrowed UDS reconnect after ACK retaining the running command, reattachment
   without replay, explicit release and a shared server surviving client closure.

The only agent-command approval is deliberately declined. The profile never
automatically approves an operation. A settled submission RPC leaves no pending
request to classify as uncertain, but that does not establish command completion
or idempotency. Command markers and native lifecycle events supply the evidence;
reconnect does not repeat the mutation. Native execution results never confer
Samgita Task review or acceptance.

Pinned sources relative to `codex-rs/`:

| Contract | Source |
| --- | --- |
| User-shell request fields and unsandboxed/timeout semantics | `app-server-protocol/src/protocol/v2/thread.rs:1185-1203` |
| Validation, direct-input fence, local environment and immediate submission | `app-server/src/request_processors/thread_processor.rs:2544-2599` |
| Loaded-thread requirement | `app-server/src/request_processors/thread_processor.rs:974-990` |
| Standalone versus active-turn selection | `core/src/session/handlers.rs:97-135` |
| Shell/cwd, item events, sandbox bypass, cancellation and results | `core/src/tasks/user_shell.rs:105-354` |
| Contextual output persistence and rollout materialization | `core/src/tasks/user_shell.rs:440-468` |
| Empty aggregated output becomes null on the wire | `app-server-protocol/src/protocol/v2/item.rs:920-945` |
| Persisted shell contextual record | `core/src/context/user_shell_command.rs:30-49` |
| Disconnect removes subscriptions rather than terminating threads | `app-server/src/request_processors/thread_processor.rs:3746-3761`, `app-server/src/thread_state.rs:651-676` |
| Native upstream examples for history, active turns and timeouts | `app-server/tests/suite/v2/thread_shell_command.rs:42-535` |

Validation on 2026-10-24 began at `main` checkpoint
`a5f01d985842ba819c06d51055aa2452d0def4cc` plus the three owned files; final
tests completed with HEAD `f5fc91555e2b4a3fe171fa418ffdd24737b5c955`. The
intervening organization/read-state qualification is independent of this profile.
Commands ran serially from `apps/samgita_codex_driver` through the verified
`devenv shell --no-tui --` environment:

```sh
mix format test/native_user_shell_profile.exs
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl \
  mix test test/native_user_shell_profile.exs --seed 501432
MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl \
  mix test test/native_user_shell_profile.exs --seed 987654
mix format --check-formatted
```

The initial run passed seven cases and failed the pipeline's empty-output
expectation. A bounded diagnostic recorded successful native exit 0 and
`aggregatedOutput: null`. The pinned conversion explicitly filters empty strings
to null (`v2/item.rs:939-941`), so repair 1 corrected that exact assertion and
retained the redirect's file-content and lifecycle checks. No production code,
timeout, namespace protection or behavioral assertion was removed. The fixture
also suppresses Python bytecode writes outside its disposable directories.

After that correction, compile with warnings as errors and format check passed.
Both full native runs passed **8 tests, 0 failures**, without warnings or skips:
seed `501432` took 16.3 seconds and seed `987654` took 17.3 seconds. Python AST
parsing and `git diff --check` passed. Tests checked command/controller/native/
namespace-owner process reaping, including the prior native generation after
explicit restart. No owned fixture directories remain. One repair round
succeeded; there were no failed repair rounds.

Preserved logs:

- `/tmp/samgita-native-user-shell-501432-initial.log`
- `/tmp/samgita-native-user-shell-pipeline-diagnostic.log`
- `/tmp/samgita-native-user-shell-repair1.log`

No Samgita platform, Repo or PostgreSQL instance was required. Native contextual
history uses only the fixture's disposable Codex storage.

This profile does not qualify live models, remote executors, other operating
systems, sandbox enforcement, all shell implementations or complete app-server
compatibility. Multi-agent-v2 direct-input rejection and disabled local executor
variants remain outside this unit. A11 remains separately blocked. No package
publication, deployment or production migration is performed.
