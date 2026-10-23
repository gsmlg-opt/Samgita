# Native thread queue lifecycle qualification

This unit targets immutable Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`, through the existing Linux stdio
driver. It expands the earlier held-approval queue CRUD checks into durable
unloaded management, automatic dispatch, interruption and explicit restart.
It changes no production code or shared test fixtures.

Current status: all eight actual-binary cases pass with seeds `501432` and
`987654`. Compilation with warnings as errors, formatting and Python static
validation pass. This qualifies the selected Linux stdio/local synthetic
behaviors below; external services and other profiles remain unqualified.

## Pinned source and ownership

Paths below are relative to the pinned upstream `codex-rs/` directory:

- `app-server-protocol/src/protocol/common.rs:630–665` marks all six
  `thread/queue/*` methods experimental and serializes requests by thread ID.
- `app-server-protocol/src/protocol/v2/thread.rs:926–1028,2164–2166` defines
  queued submissions as `id`, `input`, and `clientUserMessageId`, list cursors,
  mutations, optional selected-start ID, and thread-only change notifications.
- `app-server/src/request_processors/thread_queue_processor.rs` validates
  thread existence, persisted/nonarchived state, direct-input authority, input
  shape, pagination and selected-start preconditions. CRUD does not resume an
  unloaded thread. Starting one requires an explicit thread resume first.
- `thread-store/src/local/read_thread.rs:90–102` returns a storage
  `InvalidRequest` when an unknown valid UUID has no rollout. The queue processor
  maps that storage variant to internal error `-32603`, with the exact
  `failed to read thread: invalid thread-store request: no rollout found for
  thread id …` message. Its separate `ThreadNotFound` mapping does not describe
  this reachable local missing-rollout path.
- `ext/queue/src/service.rs:97–245,263–453,478–599` implements per-thread
  dispatch locking, durable mutation, stable client ID on update, queue change
  events, selected/head starts, FIFO dispatch and lifecycle wakeups. Interrupted
  idle causes preserve the queue. A normal idle/completed lifecycle dispatches
  it. The external-change watcher polls every 10 seconds; the test does not
  substitute elapsed time for a completion barrier.
- `thread-store/src/queue_store.rs:14–50,97–165` exposes storage-only
  `change_version` and changed-thread revisions, capacity errors and storage
  reorder errors. These revisions are not public client fields or CAS tokens.
- `state/src/runtime/queued_items.rs:164–185` rejects a reorder that omits,
  duplicates or substitutes any queued identity before changing durable order.
- `app-server/src/extensions.rs:166–199` routes a lightweight queue change
  event through the thread listener/subscribed connections. The notification
  contains `threadId`; callers re-list for authoritative queue contents.
- `app-server/tests/suite/v2/thread_queue.rs:67–365` covers capability gates,
  CRUD, notification shape, pagination and capacity. Lines 369–950 cover idle
  dispatch, client IDs, native `x-codex-turn-metadata`, cold resume, interruption,
  explicit selected/head start and active-turn preservation.
- `ext/queue/tests/queue_service.rs:249–568,828–1035` separately covers service
  drain, stable identity, FIFO, local attachment snapshots and input limits.

The public API has no queue version, expected-version field or compare-and-swap
conflict response. This unit qualifies its actual reorder/start/missing-identity
errors; it does not invent a wire concurrency contract. Duplicate client message
IDs are provenance supplied by the client; enqueue allocates distinct queue IDs.

## Verified cases

`apps/samgita_codex_driver/test/native_queue_lifecycle_test.exs` contains eight
cases:

1. Materialize a thread, close its owned native process, then add/update/reorder/
   delete and paginate while unloaded. Duplicate client IDs retain separate
   queue identities. A second native restart preserves the edited ordered queue.
   Reads/CRUD keep the thread unloaded and make no extra provider requests.
2. Omitted, duplicate and foreign reorder identities, missing update/delete,
   empty input and bad pagination preserve the durable queue. Zero limit follows
   the native clamp-to-one behavior; an out-of-range cursor returns an empty page.
3. Adding to an idle loaded thread starts a queued turn automatically. Native
   item content/client ID, completed turn, queue removal and provider metadata
   agree on the thread, turn and `queue` trigger.
4. An owned provider holds the active response at an observed request barrier.
   Add/update/reorder/delete remain usable, and explicit start returns the exact
   busy error without removal. Stdin release permits the active turn to complete
   and the retained queue to drain in the edited FIFO order. Thread-only change
   notices and actual turn/provider correlation are checked.
5. Interrupting a held native turn preserves pending messages. Cold restart,
   resume and another add keep the interrupted queue paused. An explicit nonhead
   start selects that item, then normal completion drains the remaining FIFO.
6. An omitted selected-start ID chooses the preserved head after interruption;
   a missing selected ID preserves state and an empty queue returns its native
   error after dispatch finishes.
7. A persisted noninterrupted thread remains unloaded while its queue is managed;
   explicit cold resume dispatches the queued content and original client ID.
8. All six methods enforce absent/false experimental negotiation locally and at
   the native server. Ephemeral, missing, invalid and archived threads, malformed
   request fields and required-field omissions preserve native error boundaries.

## Fixture and validation boundaries

`scripts/codex/queued_model_fixture.py` subclasses the existing deterministic
Responses peer without modifying it. It journals only synthetic requests and
native turn metadata. Selected first requests wait on an explicit Event; a JSON
stdin command releases the exact request index. The hold has a failure deadline,
not an automatic successful response. Native interruption can close the HTTP
request before release; this is distinct from queue dispatch. Closing the owned
fixture releases waiting handlers and shuts down the loopback server.

The native driver owns each disposable stdio Codex process; shared helpers
register its cleanup immediately after start. Temporary HOME, CODEX_HOME,
workspace, provider requests and journals belong to the case. All configured
provider/account origins point at its loopback fixture. No real credentials,
paid model, remote service, platform database or production task is used.

Prepared and qualified at repository baseline
`4171dfe0a6dcf3b5e85fb5eca08da6d56431aefb` on 2026-10-24. Python AST parsing
passed without module import, socket, listener or subprocess startup. The Elixir
draft remained outside the repository formatter glob until the parent granted
the exclusive build/process slot.

The initial run recorded **8 tests, 1 failure** at seed `501432`; log:
`/tmp/samgita-native-queue-initial.log`. Seven behavior cases passed. The error
case initially assumed the queue processor's `ThreadNotFound` mapping applied
to an absent valid UUID. Actual wire evidence and the storage implementation
above established the reachable `InvalidRequest` path instead. One assertion
repair retained the exact native `-32603` code/message. No runtime change or
weakened assertion was made.

The following complete validation command then exited `0`:

```sh
devenv shell --no-tui -- bash -c 'cd apps/samgita_codex_driver &&
  MIX_ENV=test mix format test/native_queue_lifecycle_test.exs &&
  MIX_ENV=test mix compile --warnings-as-errors &&
  MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_queue_lifecycle_test.exs --include real_codex --seed 501432 &&
  MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_queue_lifecycle_test.exs --include real_codex --seed 987654 &&
  MIX_ENV=test mix format --check-formatted test/native_queue_lifecycle_test.exs'
```

- Seed `501432`: **8 tests, 0 failures**, 7.8 seconds.
- Seed `987654`: **8 tests, 0 failures**, 7.7 seconds.
- Compile with warnings as errors and changed-file formatting checks passed.
- Final log: `/tmp/samgita-native-queue-repair-1.log`.
- Sol repair rounds: one successful assertion correction, no unsuccessful repair.
- Post-command process inspection found no owned pinned Codex app-server,
  queued provider fixture or queue test command remaining. The parent received
  the explicit execution-slot release before documentation finalization.

This unit does not qualify external queue writers, capacity/oversized snapshots,
local attachment handling, hooks rejecting queued input, cross-process revision
polling, subagent authority restrictions, alternate operating systems or external
platform integration. Passing this scope will not establish full compatibility
or production readiness; wider qualification gates remain separate.
