# Unanswered approval across hard native restart

Two cases run stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Both fixed seeds pass **2/0**, covering `legacy` and `paginated` history.
The controller SIGKILLs and reaps only its held, checked-live native child while
a genuine command approval remains unanswered. It restarts that owned binary
explicitly. A loopback-only model peer supplies fixed tool/assistant data; Codex
produces every app-server envelope, callback, execution and history record.

Before termination, the original user input must already exist in the owned
native persistence artifact, with one pending callback and no command effect.
The driver then disconnects, removes the unanswered interaction and rejects its
old opaque handle. No response had been sent, so no sent-unconfirmed outcome is
invented. Cold startup/read/resume produces no inference, callback, execution or
completion event. The original turn projects as `interrupted`, with nil
completion time/duration; that read projection is not a durable abort receipt.

A fresh explicit same-command turn prompts again. The native numeric callback ID
is reused after process restart, but the driver instance and opaque handle are
different. Repeated old-handle replies cannot settle the new callback. Only
explicit acceptance of its new handle executes this fixed command:

```sh
echo 'owned cold command' >> cold-command.txt; printf samgita_cold_command
```

The test requires exactly one append line, exact argv/cwd/stdout/exit, one live
completed command and turn, three model calls total and unchanged abandoned
history. In `paginated` mode the successful command also persists; `legacy`
history contains no command item. Both modes retain the assistant and original
turn identity. No policy rule, auth file, realtime use or external route exists.
Every owned native/controller/namespace process must be confirmed reaped.

## Source-backed initial fixture corrections

The first runner failed its exact argv assertion before termination. Immutable
[`shell_detect.rs:343`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/shell-command/src/shell_detect.rs#L343)
uses the model path only to select a shell type, then discovers its executable
on PATH. The fixture now prepends its copied private shell directory, as the
retained approval tests already do; its exact argv oracle is unchanged.

The second runner reached successful cold recovery and explicit execution but
failed its assumed legacy persisted-command assertion. Immutable
[`rollout policy`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/rollout/src/policy.rs#L240)
omits command items in legacy mode and persists them in paginated mode. The final
profile tests both modes and their exact distinct outcomes. It neither invents
a legacy command record nor removes the positive persisted-command check.
Both failed runner directories are retained:
`/tmp/samgita-native-approval-cold-restart-20261024/` and
`/tmp/samgita-native-approval-cold-restart-v2-20261024/`.

The process-local callback map/ID counter are defined in
[`outgoing_message.rs`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/outgoing_message.rs#L250).
Cold history loading does not start a turn
([session](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/mod.rs#L1643));
[`thread_lifecycle.rs:1074`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_lifecycle.rs#L1074)
changes only stale returned turn status. This evidence establishes loss of cold
approval authority, not callback restoration or crash-safe exactly-once work.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-approval-cold-restart-v3-20261024.py
```

Python AST, driver warning-free compile, scoped format and root strict Credo
pass. Seeds `501432`/`987654` pass **2/0**, no exclusions, 6.6/5.9s (runner
7.075/6.453s); executable-source guard matches. A required explicit hosted
profile step is added. Final combined-source and hosted checks remain pending.

| File | SHA256 |
| --- | --- |
| `native_approval_cold_restart_profile.exs` | a085fe288d35d818441640a8adb0332c4bc2d63e5495a733e4a835cdb253128f |
| `isolated_approval_cold_restart_fixture.py` | c5ff807c6a970bd066e4c962a87fedf7e3f90296be7841c36297e69abc6749f2 |

Only supplemental `lifecycle:approval-decisions` evidence is added; it stays
**missing** and counts do not change. Sent-but-unconfirmed crash outcomes, other
interaction kinds/transports/OS/backends, full lifecycle acceptance, unreachable
legacy emitters and A11 remain incomplete. No automatic retry, deadline change,
real credential, paid task, publication, production migration or deployment.
