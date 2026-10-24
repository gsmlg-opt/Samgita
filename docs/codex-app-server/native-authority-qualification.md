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
