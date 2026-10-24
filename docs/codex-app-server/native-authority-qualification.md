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

## Management-wins dispatch with independent PostgreSQL transactions

The explicit `codex_runtime_authority_profile.exs` now qualifies one pre-ticket
ordering with a genuine native pending approval. It runs **only** against
`samgita_redesign_codex_authority_repair_test` locally or
`samgita_redesign_codex_authority_ci_test` in CI, and checks `current_database()`
at each checkout. It rejects the shared recovery database before creating its
fixture. The profile intentionally retains unresolved native history and does
not match default `*_test.exs` discovery; its dedicated two-seed CI step is
required. Omission of that step is not acceptance.

The test first prepares an authorized response without sending it. Management A
then performs the legal `in_progress -> blocked -> open` commands inside an outer
transaction, retaining normal ordered locks. Dispatch B calls the actual
`CodexRuntime.dispatch` on another connection. A third observer must find A in
`pg_blocking_pids(B)` before A can commit. All three distinct PostgreSQL backend
PIDs and exact database name are recorded after this positive observation. A
sleep or process-ready message cannot satisfy that barrier.

After the management commit, B must return exact `ownership_lost`. A repeated
dispatch and explicit real `Driver.execute` must return the same error. No ticket,
token, deadline, send, receipt replay, response consumption, Task review or Task
acceptance is inferred. This tests **management before ticket issuance**; a
ticket-first execution is outside this case and instantaneous database revocation
after a committed ticket is still not promised.

The legal management delta is exact: Task open/version+2/held/fence+1; Attempt
cancelled/version+1/terminal timestamp while effects stay unresolved; Project
event sequence+3; two successful command receipts; two task-transition and one
attempt-closed audit events with exact command IDs/sequences. Other selected
Agent/credential/membership/connection/session and native records, original reply
receipt, native pending interaction, provider request and job counts stay exact.
Checked-owned shutdown preserves the unresolved journal. On consecutive runs,
every previously retained Project/Agent/credential/connection/session/membership/
Task/Attempt/native/audit/receipt/job record remains byte-equivalent as its Ecto
struct. No deletion, false effect resolution, queue reset or authority bypass is
used.

This isolation is necessary: `Platform.unresolved_state?/0` correctly rejects
activation when any Task is held or any Attempt is unresolved. Leaving this
fixture in the shared recovery DB would poison later global activation tests.
The seven existing fixture/helper bodies moved unchanged into test-only
`SamgitaWeb.CodexRuntimeFixture`; existing integration cases import them. Their
guarded ModelFixture load defines test modules and starts no provider/process.
No production interface, authority rule, lock order or shared configuration
changes. Workers and native resources have bounded owner-specific cleanup;
their durable unresolved evidence stays in the separate scratch DB.

The tested platform source boundaries are `commands.ex:131-182` (ordered locks),
`tasks.ex:121-130,171-246,567-587` (owning Agents and management fence),
`codex_runtime.ex:158-195` (reauthorize before ticket) and
`codex_runtime/authorization.ex:34-48,64-81` (current owning aggregate). Rejection
can occur at the cancelled Attempt before the numeric fence check; this is
aggregate-authority evidence, not an isolated numeric-fence branch.

Initial v1 failed **before tests** because the local cluster's `template1` is
SQL_ASCII and Mix requested UTF8. The explicitly named absent scratch DB was
created using `TEMPLATE template0 ENCODING 'UTF8'`; no existing database was reset
or changed. Its additive migrations then ran through the normal test alias.
The hosted PostgreSQL service has its own default UTF8 template; no product
configuration workaround is introduced. Initial diagnostics remain in
`/tmp/samgita-native-authority-lock-v1-20261025/`.

After provisioning, the new profile passes **1/0 at each seed501432/987654** on
the same retained scratch DB. The complete existing authority/race/integration
owning block passes **21 core +7 web/0 twice** on the separate preserved recovery
DB, followed by **4 core +1 web/0 twice** for recovery/restart. Compile, formatting,
strict Credo435 files and the executable/config/workflow source guard pass.
Exact commands/database selection/logs are
`/tmp/samgita-native-authority-lock-v2-20261025/`;
results SHA256 `3469c545a4242990066f56251474e9c9402a2994f14b5641331c43cd94bd3c07`,
source SHA256 `109df93b98e453039768346c53b807187b0777d32f2d32e4a0ecfbb0b0cbf839`.

This strengthens the still-missing `lifecycle:samgita-authorization`; counts and
verified states do not change. Full API/race/interaction/transport/OS/backend,
final-source matrices, A11 and publication gates remain separate requirements.
