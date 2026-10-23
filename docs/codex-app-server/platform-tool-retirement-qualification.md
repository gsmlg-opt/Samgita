# Durable retirement of unanswered dynamic tools

An interrupted pinned Codex dynamic tool emits terminal item/turn evidence without
`serverRequest/resolved`. The native driver regression is documented in
[tool-interactions-qualification.md](tool-interactions-qualification.md). Its
local-handle repair alone did not close the platform boundary: the PostgreSQL
journal still marked the request `pending` or `reply_prepared`, permitting a late
reply intent or a dispatch ticket for an already prepared response. The driver
would reject that response, after the platform had already issued a ticket and
created an uncertain operation.

The context regression reproduced the durable gap using the actual PostgreSQL
context and validated pinned wire fixtures: after a matching terminal dynamic
item, the request remained `pending` instead of becoming unanswerable. These are
context tests with deterministic native-message fixtures. They complement the
separate actual-native driver profile; they do not claim a combined live native
server/database journey or real model/provider qualification.

`Journal.append!` now retires only proved-unsent dynamic interactions when the
same authenticated runtime reports a validated terminal dynamic item or terminal
turn. Matching requires the current runtime, process instance, driver generation,
thread, turn and, for item evidence, native call ID. Nonterminal notifications,
another thread/turn/call, user-input requests and earlier generations do not
qualify. The existing Project/Task/Attempt/runtime lock order serializes event
ingestion, reply preparation and ticket issuance; no socket state grants durable
authority.

The event becomes `terminal_observed`, distinct from native request resolution
or operator cessation attestation. Only a response still in `prepared` may be
cancelled. A request with an associated `in_flight`, `sent_unconfirmed`, `uncertain`
or any other non-prepared/non-cancelled operation is excluded. Terminal evidence
never settles, clears or rewrites such an operation, and does not fabricate an
acknowledgement. Already-cancelled unsent operations retain their versions. A
cancelled prepared intent cannot dispatch, including through an old idempotent
reply receipt: that historical receipt cannot bypass current database state and
optimistic versions.

The encrypted request payload remains authoritative for turn/call matching. A
current-runtime/generation/method/state/thread-digest query streams candidates in
128-row batches, then decrypts only those protected payloads inside the existing
transaction. This handles historical records without schema changes, plaintext
identity columns or a backfill. Terminal notification persistence and retirement
commit atomically. Repeated terminal evidence does not increment retired-record
versions again. There is no job, listener, new credential, native retry or command
execution.

A second context red case showed reconnect converting `terminal_observed` back
to `stale`. Reconnect now preserves this proved-unsent terminal state alongside
explicit native resolution. It still marks unanswered old-generation interactions
stale, converts dispatched/unconfirmed operations to uncertainty, cancels unsent
prepared operations, records a notification gap and enforces the existing owner,
lease, fence and generation checks. Previously ambiguous work remains ambiguous.

`terminal_observed` removes only that known-unsent request from the waiting
interaction guard. Task state, acceptance policy and effect declarations do not
change. Other unresolved operations, interactions, active native links and
notification gaps still block an effects-resolved report. Native completion does
not accept a Task or confer review permission. Explicit `serverRequest/resolved`
keeps its existing separate semantics; this change does not relabel terminal
evidence as native response acceptance.

Ten context cases cover pending retirement, prepared-response cancellation and
historical receipt replay, exact identity/type/status mismatches, user-input and
other-turn isolation, preservation of all dispatched/ambiguous states, already
cancelled operations, duplicate event identity/version behavior, generation
isolation, reconnect preservation, and 129 encrypted candidates crossing the
128-row streaming boundary. The existing Codex runtime, notification, concurrency
and Attempt suites remain part of the scoped verification. Existing independent
transaction tests retain their PostgreSQL backend-PID assertions; the new context
cases do not claim new independent-transaction race coverage.

Verification uses the retained populated isolated database
`samgita_redesign_recovery_repair_test` through the existing local PostgreSQL socket.
No reset, database recreation, production migration, historical-record deletion
or unrelated-row remapping is performed. Fixtures roll back through the existing
test sandbox. The source baseline for this unit is `6502325b78f16fbd54d07f8d190af553a09da8a3`.

Run serially from the repository root through `devenv shell --no-tui --`:

```sh
export PGHOST=/tmp/samgita-p3-pg/socket POSTGRES_PORT=55443 POSTGRES_USER=gao
export MIX_ENV=test SAMGITA_TEST_DATABASE=samgita_redesign_recovery_repair_test
mix test apps/samgita/test/samgita/codex_runtime_tool_retirement_test.exs \
  --only retirement_regression --seed 501432
# Before repair: durable request stayed pending.
mix test apps/samgita/test/samgita/codex_runtime_tool_retirement_test.exs \
  --only retirement_reconnect_regression --seed 501432
# Before reconnect repair: known terminal request became stale.
mix compile --warnings-as-errors
mix test apps/samgita/test/samgita/codex_runtime_tool_retirement_test.exs \
  apps/samgita/test/samgita/codex_runtime_test.exs \
  apps/samgita/test/samgita/codex_runtime_notification_test.exs \
  apps/samgita/test/samgita/codex_runtime_race_test.exs \
  apps/samgita/test/samgita/attempts_test.exs --seed 501432
# Repeat the same five files with --seed 987654.
mix format --check-formatted apps/samgita/lib/samgita/codex_runtime.ex \
  apps/samgita/lib/samgita/codex_runtime/journal.ex \
  apps/samgita/test/samgita/codex_runtime_tool_retirement_test.exs
mix credo --strict
git diff --check
```

Final compile-with-warnings-as-errors and scoped format checks passed. Both
expanded runs passed **53 tests, 0 failures, 1 existing E2E exclusion** (52
executed), seeds `501432` and `987654`, taking 4.2 seconds each after the final
refactor. Strict Credo checked 314 source files and found no issues. The query
construction and iteration were separated without changing matching, state or
transaction semantics; no lint threshold or test was weakened. `git diff --check`
passed. Final verification observed HEAD
`23c25a7aa8a828e1678829e97f31283d1860b1f0`; intervening parent commits belong to
independent qualification units. No command remains running.

The initial new-test compile encountered a helper named `dynamic/2` colliding
with the imported Ecto query macro; renaming it to `dynamic_request` allowed the
required behavior red. One later bounded repair split the new helper after the
strict complexity failure. The two deliberate behavior reds preceded their
respective runtime edits. There are no unresolved validation failures for this
unit.

Preserved evidence:

- `/tmp/samgita-platform-tool-retirement-red.log`: initial durable behavior red.
- `/tmp/samgita-platform-tool-retirement-green.log`: initial 38-test runtime guard
  run passed, with one explicit existing E2E exclusion.
- `/tmp/samgita-platform-tool-retirement-reconnect-red.log`: reconnect behavior red.
- `/tmp/samgita-platform-tool-retirement-final.log`: both expanded test seeds
  passed; strict Credo then identified one over-complex new query/iteration helper.
- `/tmp/samgita-platform-tool-retirement-repair-final.log`: final passing tests,
  compile/format and strict Credo results.

There are no migrations to apply or reverse. For rollback, fence native reply
dispatch before using an older binary. Retain terminal evidence and cancelled
operations; do not turn them back into pending work, replay responses or clear
uncertain operations. Older readers may conservatively treat `terminal_observed`
as unresolved; a compatible binary is needed to retain the improved behavior.
Operator reconciliation remains required for ambiguous sends. This unit neither
publishes a package nor deploys services, and does not close A11 or establish full
Codex compatibility.
