# Native command approval loss and reconciliation

Three new command cases extend the retained file/permission approval loss suite.
The complete owning block, including command replay cancellation, passes **10/0**
at both fixed seeds against stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The broad approval lifecycle remains missing. This is selected actual-native
behavior with deterministic transport faults, not a universal exactly-once claim.

## Native execution and uncertainty

The existing authenticated native WebSocket listener, model-only peer,
`ApprovalLossTransport` and process guardians are retained. Every app-server
frame, approval, execution item and persisted history comes from the real binary.
The fixed model response requests only this literal owned private-shell command:

```sh
echo 'owned recovered command' >> loss-command.txt; printf samgita_loss_command
```

No arbitrary command, external service, paid task or platform record is involved.
The peer never writes the marker. The tests independently require the exact
private-shell argv/cwd, native request/turn/item association, started timestamp,
reason and proposal. Before approval the workspace remains empty and model call
count is one. Successful execution must append exactly one prescribed line and
return the exact stdout, completed status and exit0. Live completion and durable
history each contain the original command item; no extra execution is accepted.

Each command case checks a separate outcome:

- An unanswered callback replays only after explicit warm resume, unchanged in
  wire ID, parameters and creation time. A new local generation/reference is
  required; the stale handle cannot reply. Reconnection alone executes nothing.
- The test transport drops one reply before native receipt while reporting local
  write success. The driver preserves sent-unconfirmed then uncertain outcome.
  Only a fresh explicit response after actual native replay causes execution;
  the two explicit reply digests match. The old uncertainty remains visible.
- A reply reaches Codex while the transport suppresses actual resolved/completed
  notifications. Bounded discarded metadata proves both native notices arrived.
  Exact marker bytes and persisted command/history reconcile completion without
  resending the response or turn. Only explicit caller acknowledgement clears
  local uncertainty after that evidence is available.

All cases assert one turn/start, one explicit resume, two model calls, no policy
file and no automatic approval or execution retry. Borrowed reconnect/close
retains the native owner; final cleanup still confirms owned-process shutdown.
The existing six file/permission cases and command cancellation control retain
their original assertions and deadlines. No app-server frame is synthesized,
and transport injection is not claimed as observed TCP packet loss.

## Retained draft failure and correction

The first runner `/tmp/samgita-native-command-approval-loss-20261024/` passed
compile/format/strict Credo, then failed **three of ten** cases at seed501432,
all before sending an approval response. Its fixed printf script contained a
backslash. Native approval display uses `shlex_join` at
[`bespoke_event_handling.rs:752`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/bespoke_event_handling.rs#L752),
delegating to pinned shlex1.3.0 through
[`shell-command/src/parse_command.rs:10`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/shell-command/src/parse_command.rs#L10).
That display doubles the backslash inside double quotes; the test's
`OptionParser.split` does not collapse that pair. It was a display-oracle mismatch,
not evidence of a native command mutation or a repaired driver defect.

Both independently specified fixture/test inputs now use the simpler literal
above, with no backslash to escape. Exact argv, newline/append bytes, stdout and
all loss/replay/history assertions remain; no deadline changes or shape fallback
is introduced. The first failed logs remain and no failed case is removed.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-command-approval-loss-v2-20261024.py
```

The matching directory records full commands, exits and source snapshot.
Warning-free driver compile, scoped format, Python AST and root strict Credo
(416 files) pass. Native seeds501432 and987654 each pass **10/0**, no exclusions,
13.6/13.8s. The final source guard matches.

| File | Final SHA256 |
| --- | --- |
| `native_approval_loss_test.exs` | 478d76e1a78355fec6539836e5a130484b3acb2bc421341ae989a3e5c569955e |
| `approval_loss_fixture.py` | 9bbef9334f6e2a30ed970589f71c77b818be9b9cbf8dbbddce07aa583aca3039 |

Only supplemental scoped evidence is added to `lifecycle:approval-decisions`;
no missing field/variant or full requirement becomes verified. Cold pending
callback restoration, every decision/cache/environment/OS/backend variant,
upstream-unreachable legacy emitters and A11 remain incomplete. Complete
final-source package, preserved-database and hosted checks remain required.
No publication, release, production migration or deployment occurs.
