# Operator-reply authority regressions

Eleven context cases pass at both seeds `501432` and `987654`, 0.5 seconds per
run, on the retained populated `samgita_redesign_recovery_repair_test` database.
Warnings-as-errors compilation, formatting and scoped strict Credo pass. No
database was reset and no implementation defect is claimed or repaired.

Executed test:
`apps/samgita/test/samgita/codex_runtime_operator_authority_test.exs`.
It contains **11 explicit tests**, each with two identical rejected submissions.
All use the existing `Samgita.DataCase` sandbox and `DomainFixtures` contracts
from `apps/samgita/test/samgita/codex_runtime_test.exs:18-76,351-499,769-838`.
No native Session, driver, process, fake transport, model provider or Agent
service is started. The native approval envelope is deterministic context input,
not a claim that Codex emitted it. No protocol manifest entry is promoted here.

## Individual cases

Every case first registers an ordinary Codex runtime Agent, grants its worker
membership, connects with a synthetic credential, opens a session, claims and
starts a Task Attempt, binds an inert runtime and records a schema-valid pending
command-approval event. Only then does the test directly change one authority
fact using Ecto fixture updates:

| Case | Exact fixture change | Expected reply result |
| --- | --- | --- |
| Credential revoked | Owning credential `revoked_at` set | `ownership_lost` |
| Credential expired | Owning credential `expires_at` in past | `ownership_lost` |
| Membership disabled | Existing member `enabled: false` | `ownership_lost` |
| Worker role removed | Same member retains observer only | `ownership_lost` |
| Task hold | `execution_hold: true` | `ownership_lost` |
| Task state | `in_progress` becomes `blocked` | `ownership_lost` |
| Task fence | Task fence increments; Attempt remains old | `ownership_lost` |
| Session closed | Same execution session `state: closed` | `ownership_lost` |
| Connection expired | Same connection expiry in past | `ownership_lost` |
| Connection generation | Connection increments; Agent/Attempt/binding remain old | `ownership_lost` |
| Native registration removed | Agent `runtime_driver` and `runtime_version` both null | `ownership_lost` |

The native registration database constraint permits only the exact
`codex/0.163.0` pair or two null values
(`20261023000003_add_native_runtime_journal.exs:10-12`). Independent invalid
driver/version mutations would fail the fixture's database update rather than
exercise operator authorization. The fixture clears both metadata fields
together; it does not disable constraints or invent an unsupported registration.

Direct fixture changes deliberately isolate the checked fact. Production APIs
may update multiple records, revoke connections or audit the administrative
change, masking the individual reply branch. These tests qualify neither those
administrative APIs nor the consistency of every hypothetical direct DB edit.

## Exact rollback and repeated-submission assertions

The baseline is captured **after** intentional invalidation. Each submission
requires the exact returned tuple `{:error, Samgita.Error.new(:ownership_lost)}`,
including the stable message and empty details. The same command UUID and event
version are submitted twice, so a rejected command must not become a successful
receipt replay.

After each rejection, exact snapshots must remain unchanged for the owning
Agent/credential/membership/connection/session, Task/Attempt, runtime binding,
pending original interaction, every native operation/event/link in that runtime,
and every Project domain event. The operation list begins and remains empty;
therefore no prepared response, dispatch-token digest, dispatch deadline or
ticket-bearing row can exist. The Project's native-dispatched audit-event count
begins and remains zero. Global receipt/job counts remain unchanged, and the
rejected command UUID has no receipt. This covers transactional persisted
effects and durable enqueue effects on the serial test sandbox.

There is no started driver or endpoint and no call to dispatch/execute. The
absence of an executable intent and dispatched audit record is the asserted
dispatch boundary. This is not an instrumented wire-level negative proof or
native transport test; an uninstalled fake transport's empty mailbox would be
vacuous evidence and is not used.

## Source boundary and limits

`CodexRuntime.reply/5` prepares an explicit response only after the generic
native authorization callback (`codex_runtime.ex:117-162,537-557`).
`Commands.run` runs that callback inside ordered locks and before receipt replay
(`commands.ex:19-35`). `CodexRuntime.Authorization.owner!` and
`valid_operator_connection!` validate the current owning credential, member,
session and connection for operator replies (`authorization.ex:84-110`).
`context` validates the driver registration and `current_task!` checks Task
state/hold/fence (`authorization.ex:34-49,77-82`). All selected invalidations
therefore have the source-expected error `ownership_lost`, rather than the
operator principal's ordinary API-role `forbidden`/`unauthorized` errors.

This adds selected missing branch coverage around a **new operator prepare
reply**, before a dispatch ticket exists. It does not alter or qualify revocation
of an already issued ticket, immediate cross-process transmission revocation,
concurrent administrative races, per-method human-only policy, lease/deadline
expiry, authority epoch, disabled Agent, missing membership, disconnected
connection, altered Attempt connection generation or session connection ID.
Some of those have existing separate tests; none is inferred from these 11.
It does not qualify all of `lifecycle:samgita-authorization`, real Codex approval
behavior, every transport or external/platform success profiles.

## Executed checks

In the verified Devenv at repository root, with `MIX_ENV=test`,
`PGHOST=/tmp/samgita-p3-pg/socket`, `POSTGRES_PORT=55443`, `POSTGRES_USER=gao` and
`SAMGITA_TEST_DATABASE=samgita_redesign_recovery_repair_test`:

```sh
mix format apps/samgita/test/samgita/codex_runtime_operator_authority_test.exs
mix compile --warnings-as-errors
mix test apps/samgita/test/samgita/codex_runtime_operator_authority_test.exs --seed 501432
mix test apps/samgita/test/samgita/codex_runtime_operator_authority_test.exs --seed 987654
mix format --check-formatted apps/samgita/test/samgita/codex_runtime_operator_authority_test.exs
mix credo apps/samgita/test/samgita/codex_runtime_operator_authority_test.exs --strict
```

Both runs pass **11 tests / zero failures**. Exact snapshots/error assertions
were retained without retries or deadline changes. Logs are
`/tmp/samgita-operator-authority-{501432,987654,credo}-20261024.log` and the
validation command/result record is
`/tmp/samgita-operator-authority-validation-20261024.log`.
Hosted platform qualification explicitly selects this file; final hosted and
aggregate results remain separate, pending checks.

This context-only evidence is attached to `lifecycle:samgita-authorization`
without changing its `missing` status. Full native/API/race evidence and the
remaining authorization branches are required before that broad rule can be
qualified. These tests do not demonstrate instantaneous revocation of an
already issued dispatch ticket before native transmission; that stronger
guarantee is not inferred from later-command rejection or database serialization.

## Remaining time and connection predispatch branches

Six additive context cases reject operator replies after disabling the owning
Agent, disconnecting its connection, expiring the Attempt lease or execution
deadline, changing the Attempt connection generation, or moving the execution
session to another real connection. The last case creates a separately owned
Agent/connection through existing fixtures, preserving foreign-key constraints
and isolating the intended session-binding mismatch. Snapshots are taken after
invalidation; two identical submissions must return exact `ownership_lost` and
leave all selected domain/journal/events, receipt and job counts unchanged.

Two additional genuine native pending-approval cases exercise lease and deadline
expiry. The pinned executable emits the original command approval. Both repeated
operator replies reject while its same native interaction remains pending,
exactly one model-dependency request exists, no response/resolution/completion
or command dispatch occurs, no ticket exists and Task acceptance does not occur.
Explicit checked-owned shutdown retains unresolved durable effects. This adds
real emission plus the time-authority boundary, rather than counting a synthetic
pending event as native success. No production guard, lease or timeout changes.

The full two-file owning block passes **17 core + 6 web tests, zero failures** at
each seed501432/987654 against the same retained
`samgita_redesign_recovery_repair_test` database, without reset, data deletion,
mapping substitution or activation bypass. Exact commands/results are in
`/tmp/samgita-operator-authority-time-v1-20261025/`. Compile/format pass. Its last
command fails before analysis because the runner supplied unsupported Credo
`--files`; that exit130 is an invocation error, not a passing static check or
signal diagnosis. The separate unchanged-source static-v2 runner uses the
supported positional file argument for each file; both strict checks and format
pass. Runtime tests were not rerun merely to replace that CLI failure.

| Evidence | SHA256 |
| --- | --- |
| v1 results | a7ba7dfc15aba7e4fcf0cd7c4321fe878bcf0db59bfb05fc767e6684145d0797 |
| owning source snapshot | 3a414358ddf67d20c5f87a481b969115496992ce27aff05f3243b22708e245bc |
| static-v2 results | 4ed4ee827a8e4bd13803d23f4e4128ab86e0977aaa2eb75b82860e46fba50c5b |

The existing explicit hosted platform selection includes both files; complete
final-source local/hosted checks remain required. The broad authorization rule
stays missing; no schema count, already-issued-ticket revocation guarantee,
full API/race/transport qualification or A11 closure is inferred.
