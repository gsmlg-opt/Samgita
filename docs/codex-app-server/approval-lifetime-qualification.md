# Native file approval lifetime and pending interruption

The stock `rust-v0.163.0` executable, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
passes **five tests / zero failures** at seeds `501432` and `987654`, 5.9 seconds
each. These are selected native behavior cases; the complete approval lifecycle
and compatibility goal remain incomplete.

## Exercised behavior

`native_approval_lifetime_test.exs` uses the independent Session and owned native
stdio processes. `approval_lifetime_fixture.py` supplies only fixed synthetic
model responses for files inside its disposable workspace. The real executable
emits every approval, performs patches, records history and interrupts work.
The fixture does not generate or proxy app-server messages.

| Native case | Required result |
| --- | --- |
| Session file acceptance | A matching-path update completes without another approval; another path prompts and is explicitly declined |
| One-shot file acceptance | The same path prompts again; declining preserves exact first contents |
| Explicit native restart and cold resume | The first process is confirmed stopped; a distinct process resumes persisted history, without model inference, and asks again for the previously accepted path |
| Interrupt pending file approval | The exact turn is interrupted, the request resolves, no file is applied, and the old handle is stale |
| Interrupt pending safe command approval | The exact turn/request retire without executing the fixed printf command, producing command output, or storing a rule |

Every case asserts exact effects, provider call counts, request/thread/turn/item
association, no pending or uncertain requests after completion, and stale reply
rejection. Normal terminal waits reject an unexpected second approval. The cold
resume checks the original port is closed, owner cleanup is complete and the
new instance/port differs. Completed-turn history remains intact; no database,
platform or live account is needed. Existing production process cleanup is
unchanged.

File requests explicitly contain `reason: null` and `grantRoot: null`, using
`Map.fetch` assertions rather than treating omission as null. This is only the
explicit-null branch. A pending request may resolve before or after the terminal
turn notification; the interruption tests require both under the same bounded
deadline and never assume an unsupported order. Interrupting is a separate
`turn/interrupt` command, not the approval response's `cancel` decision.

## Immutable source rationale

Paths are relative to the pinned `codex-rs/` source tree:

- `core/src/tools/approvals.rs:221-258` and
  `core/src/tools/runtimes/apply_patch.rs:40-44` key file approvals by environment
  and path. `core/src/tools/sandboxing.rs:75-120` caches only
  `ApprovedForSession`; every key must match to suppress a prompt.
- `core/src/tools/approvals.rs:725-763` bypasses that cache for retry reasons;
  ordinary patch approval supplies no reason or grant root.
  `core/src/session/session.rs:1744` creates a new ApprovalStore, rather than
  restoring cached decisions from history.
- `app-server-protocol/src/protocol/v2/item.rs:1636-1652` serializes the nullable
  file fields without omission. Its upstream comment describes the nonnull
  grant-root behavior as unstable; the null test does not qualify it.
- `app-server/src/bespoke_event_handling.rs:1921-1969,1987-2040` maps file/command
  decisions and avoids submitting stale approvals on cancellation with
  `turnTransition`. Lines `1208-1226` handle turn abortion and pending requests.
- `app-server/src/request_processors/thread_lifecycle.rs:1019-1044` emits exact
  request resolution IDs. `app-server/src/thread_state.rs:231-266` queues that
  notification independently of terminal turn output.

## Commands, indexing and remaining work

From `apps/samgita_codex_driver` in verified Devenv, with `MIX_ENV=test` and
`CODEX_BINARY` set to the exact hash-checked executable:

```sh
mix compile --warnings-as-errors
mix test test/native_approval_lifetime_test.exs --seed 501432
mix test test/native_approval_lifetime_test.exs --seed 987654
mix format --check-formatted test/native_approval_lifetime_test.exs
```

The Python fixture passes AST parsing; the namespace prerequisite, formatting,
warnings-as-errors compile and scoped strict Credo pass. Logs:
`/tmp/samgita-approval-lifetime-initial-*-20261024.log`. Both native runs pass
without timeout changes, skipped assertions or product behavior changes. The
file belongs to the default driver suite selected explicitly in conformance CI.

Only the two previously missing nullable file fields newly advance to scoped
implemented. Existing file/command/interrupt/resume/resolution rows gain precise
evidence. No row becomes fully verified; `lifecycle:approval-decisions` stays
missing. Nonnull reason/grantRoot, multi-file cache, environment changes,
permission lifetime, lost replies, borrowed-connection replay, other OS/service
profiles, A11 and final aggregate/hosted checks remain incomplete. There is no
legacy runtime emission claim, publication or deployment.
