# Real native approvals and current platform authority

Three new platform integration cases extend the existing two-Agent native
journey. The owning integration module passes **4/0** at seeds `501432` and
`987654`, 5.3 and 5.2 seconds, on the retained
`samgita_redesign_recovery_repair_test` database. No reset, record cleanup or
activation bypass is used. The stock Codex pin and executable hash are checked
before startup; a loopback Responses fixture supplies the synthetic command.

Each new case initializes an owned native process through persisted platform
operations, starts a turn and journals its actual
`item/commandExecution/requestApproval`, including exact thread/turn, cwd and
command. The test deliberately leaves this real interaction pending.

- Disabling the owning Project membership through the operator API makes two
  identical operator reply submissions return exact `ownership_lost` errors.
- Explicit management transitions `in_progress -> blocked -> open` cancel the
  Attempt, set execution hold and advance its fencing token once. Two identical
  operator reply submissions then return `ownership_lost`. This management
  change preserves the outstanding native effect as unresolved.
- Preparing an operator reply while authorized does not send it. Replacing the
  owning worker role with observer still allows metadata reading but makes both
  `Driver.execute` attempts return `forbidden` before issuing a dispatch ticket.
  The operation remains prepared with no token digest and the interaction stays
  `reply_prepared`.

After every rejection, exact snapshots of Task, Attempt, membership, binding,
native event/operation/link journals, audit events, receipt counts and durable
jobs remain unchanged. The real driver still has one pending interaction, no
pending client request or uncertain local operation, and exactly one provider
request. There is no resolution/completion notification or task review/acceptance.
Confirmed owned native shutdown leaves the durable uncertain effect unresolved;
shutdown is not recorded as remote completion. Failure cleanup retains the
captured Stdio connection and closes it before the fixture and root directory.

In verified Devenv with the pinned CODEX_BINARY and the retained isolated DB:

```sh
mix test apps/samgita_web/test/samgita_web/integration/codex_runtime_test.exs --include e2e --seed 501432
mix test apps/samgita_web/test/samgita_web/integration/codex_runtime_test.exs --include e2e --seed 987654
```

Warnings-as-errors compilation, scoped formatting, namespace preflight and root
strict Credo also pass. Complete commands and logs:
`/tmp/samgita-native-platform-authority-20261024/attempt-01/`.
These cases are already included by the required hosted platform command; no
scenario, assertion or workflow gate is removed.

This joins actual native emission to persisted predispatch rejection, extending
the earlier context-only authority evidence. It does not prove every API/race,
instantaneous revocation after an already committed one-use ticket, other
interaction/OS/transport/backend profiles or A11. Dispatch commits its ticket
before network I/O; remaining post-ticket instance/generation/deadline checks do
not imply synchronous database revocation across that interval. The broad
`lifecycle:samgita-authorization` stays missing. No production code, credential,
deployment or external repository changes are made.

## Successful operator receipt replay after worker-role removal

An additive actual-native case now uses the existing REST operator boundary,
synthetic API key and the same real pending command approval. Its first reply
returns201 and creates exactly one prepared response plus a successful command
receipt. An identical authorized replay returns the exact original projection
without changing domain/journal state. This positive control distinguishes
replaying a successful receipt from repeatedly rejecting a new command.

The existing membership API then changes only the enabled membership to observer,
using the current Project version. Twice resubmitting the original successful
reply command returns the complete409 `ownership_lost` error, before old receipt
replay or stale event-version validation. Both explicit `Driver.execute` calls
return exact `forbidden`; no dispatch token is minted and the response remains
prepared. No membership permission is inferred from advertised capabilities.

After each rejected action, full snapshots of Project, Agent, credential,
connection, execution session, Task/Attempt, membership and every selected native
binding/event/operation/link/audit record remain exact. The original successful
receipt, global receipt/job counts and full provider requests are preserved. The
same real Session retains one interaction, no pending client requests or local
uncertainty, and one provider request; no resolution/completion or Task review/
acceptance occurs. Checked-owned shutdown leaves the durable effect unresolved.
No test clears history or marks that pending command completed.

`Commands.run` authorizes before receipt lookup under the existing ordered locks;
`CodexRuntime.Authorization` checks current owning membership for operator replies.
`Driver.execute` acquires a ticket before native transmission. This case qualifies
revocation **before** that ticket; it adds no instantaneous revocation guarantee
after a ticket has committed. It is sequential native/API evidence, not a new
independent-backend concurrent race. The broad authorization requirement remains
missing. Exact combined validation is recorded in the repair ledger.

The complete two-file authority owning block passes **17 core +7 web/0 twice**,
seeds501432/987654, on the same retained database. Root/driver warning-free
compile, formatting and root strict Credo433 files pass. The surrounding
21-file native block also passes **127/0 twice**, including eight genuine hook
cases and the retained rate-limit, permission, goal, environment and process
regressions. The executable/config/workflow source guard matches. Commands/logs
are `/tmp/samgita-native-repair-continuation-v6-20261025/`; results SHA256
`35a9a2fa9de9df3839b92464f1d396488b2341a3c6a5439b1b9347fb19e94e28`,
source SHA256 `472fffa65eca4866ca6df9319aa149b2339c69348febdcd21c2b6e7590f07b5f`.
Full final-source matrices, hosted checks and remaining deployment/authorization
profiles are separate required gates; no requirement state changes here.
