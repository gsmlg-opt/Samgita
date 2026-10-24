# Native edited execpolicy decisions

Three actual-binary cases in `native_approval_edits_test.exs` use stock
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
They reuse the existing fixed `command_repeat` provider transcript. The provider
supplies only `printf samgita_interaction` and tool-free final responses; it
does not emit an app-server approval or result. No unrelated command is run.

| Explicit response | Actual native effects |
| --- | --- |
| Narrower `["printf", "samgita_interaction"]` | Exact edited rule persists, the current command emits its exact output, and the later identical command runs without a prompt. |
| Unrelated safe `["printf", "samgita_other_owned_marker"]` | Exact unrelated rule persists while the current original command still runs once. The next original command prompts again and is explicitly declined, with no output. The unrelated command is never executed. |
| Empty `[]` | The original approved action executes, a thread-scoped native persistence warning reports `prefix rule requires at least one token`, and no rule file is created. The next identical command prompts and is explicitly declined. |

The pin forwards the supplied prefix without comparing it with the suggestion:
`app-server/src/bespoke_event_handling.rs:1989-2043` and
`core/src/exec_policy.rs:464-509`. `core/src/session/handlers.rs:174-208` warns
on persistence failure and still sends the approved decision. In
`execpolicy/src/amend.rs:69-70`, empty-prefix validation happens before opening
the rule file. The tests assert the exact suggested `["printf"]` request,
edited response, comma-space rule serialization, warning, effects and second
prompt behavior. These are native semantics, not a claim that Codex constrains
all reply edits to the original suggestion.

Every request is associated with its real thread/turn/item and generation-bound
handle. Old responses fail explicitly as stale. Unexpected new server requests
fail immediately rather than being automatically approved. All turns have
exact persisted history, four provider requests, no workspace-file changes and
zero pending/interactions/uncertainty. Existing owned-process/provider cleanup
and deadlines remain intact.

## Commands and outcomes, 2026-10-24

From the independent driver package, in Devenv with the immutable CODEX_BINARY:

```sh
mix test test/native_approval_edits_test.exs --seed 501432
mix test test/native_approval_edits_test.exs --seed 987654
```

Both passed **3 tests / 0 failures**, 3.5 and 3.6 seconds. Python fixture AST,
namespace prerequisite, warnings-as-errors compile, formatting and scoped strict
Credo passed. Logs are `/tmp/samgita-approval-edits-*-20261024.log`.
This ordinary `_test.exs` file is included in the required default native driver
CI suite, not an opt-in success replacement.

No schema contract is newly promoted by these cases; existing decision rows
gain stronger selected behavior evidence. Full approval lifecycle remains
missing: pending-response loss/interruption, file-session matching, effective
permission lifetimes, other transports/OS/backends and legacy success still
require separate evidence. Network amendments have their own
[native qualification](network-amendment-qualification.md).
These replies cannot grant project roles or accept Samgita Tasks. A11, full
compatibility, final aggregate/hosted evidence and production readiness remain
separate incomplete gates. No publication or deployment is claimed.
