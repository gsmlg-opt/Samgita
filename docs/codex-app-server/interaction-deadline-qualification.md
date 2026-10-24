# Native interaction deadline and explicit acceptance control

Two cases extend the command/file/permission approval-loss block against stock
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, Linux musl
binary SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The complete block, including command replay cancellation, passes **12/0** at
both fixed seeds. This adds selected actual-native lifecycle evidence; the broad
approval requirement stays **missing** and no manifest counts change.

Only the expiry case configures `interaction_timeout_ms: 2000`. Every retained
case and the independent acceptance control retain the 60,000ms default. No
collector deadline, assertion, process guardian or transport behavior changes.
The same prescribed private-shell command is used in both new cases:

```sh
echo 'owned recovered command' >> loss-command.txt; printf samgita_loss_command
```

The expiry case captures a genuine native command-approval request and sends no
manual reply. It requires one local `interaction_expired`, the matching native
`serverRequest/resolved` and completed turn, and exactly one forwarded reply digest
for the original request ID/generation:

```json
{"error":{"code":-32000,"message":"Client interaction deadline expired"}}
```

A late acceptance fails as stale without another frame. The real live command
item is `failed`, with exact command/cwd and null output, exit, process and
duration fields; no output delta, physical append or policy rule exists. Native
durable history contains the completed turn and **no command item**. The control
explicitly accepts the same owned command, requires exactly one append, exact
stdout/exit/argv and live/durable item, and rejects a second reply. Both cases
require two model calls, one turn/start, no reconnect/resume, no pending state or
uncertainty, and confirmed owned-process cleanup. The model-only peer never
executes the command or synthesizes app-server traffic.

The live/durable difference follows immutable upstream behavior. The driver
[`Session` deadline handler](../../apps/samgita_codex_driver/lib/samgita_codex_driver/session.ex#L320)
sends the error and removes the handle. Native
[`bespoke_event_handling.rs:1986`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/bespoke_event_handling.rs#L1986)
maps that client error to denial and failed completion; its
[`command completion handler`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/bespoke_event_handling.rs#L1453)
emits the live item. Core
[`approvals.rs:425`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/approvals.rs#L425)
and [`orchestrator.rs:206`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/orchestrator.rs#L206)
reject before launch, so the history reconstruction's
[`ExecCommandBegin/End`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/thread_history.rs#L371)
events do not exist. The test asserts that absence rather than inventing a
persisted failed command.

## Verification

The first runner stopped at strict Credo on a new `Enum.count(...) == 0`
expression, before native tests. The equivalent `refute Enum.any?(...)` fixes
that style issue without changing the oracle. Both runner directories remain:
`/tmp/samgita-native-interaction-deadline-20261024/` and
`/tmp/samgita-native-interaction-deadline-v2-20261024/`.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-interaction-deadline-v2-20261024.py
```

The final runner passes warning-free compile, scoped format, root strict Credo
(416 files), and the complete owning test block at seeds `501432` and `987654`:
**12/0**, no exclusions, 17.6/17.8s (runner 18.109/18.309s). Its executable-source
guard matches. Final SHA256 values:

| File | SHA256 |
| --- | --- |
| `native_approval_loss_test.exs` | 1f63c84c9e8e0dcd886cb9da1eac3c5948844cdab348ce4a22540d2a18e00ff7 |
| unchanged `approval_loss_fixture.py` | 9bbef9334f6e2a30ed970589f71c77b818be9b9cbf8dbbddce07aa583aca3039 |

This is a v2 callback's client deadline error, **not** a real legacy `TimedOut`
decision or proof of an upstream legacy emitter. Cold pending restoration,
remaining decisions/transports/OS/backends, A11 and full compatibility stay
incomplete. Final-source complete local and hosted checks remain required.
No release, publication, production migration or deployment occurs.
