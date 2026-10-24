# Native non-latest fork, revert and ephemeral boundaries

Stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
passes **6 tests / zero failures** at both qualification seeds, 12.7 seconds each.
Every parent turn is created by the real native process. A loopback provider
returns fixed assistant text; it never supplies app-server messages or rollout
history. The test uses only disposable owned files and no real service or task.

## Boundaries actually exercised

For both legacy and paginated history, before-third is exclusive and through-
second lastTurnId is inclusive, while two later completed parent turns already
exist. Exact turn/item IDs and complete input/assistant content must survive in
the independent children. excludeTurns changes inline payloads, without dropping
the persisted prefix. Before-first creates an empty persistent child whose hot
and cold history remains readable. Omitted/null boundaries retain latest history.
Invalid, unrelated and mutually exclusive IDs produce exact native errors and
preserve source histories and model request counts.

Explicit parent and child continuations then diverge. The child's actual model
input includes only its retained prefix and new input, excluding later parent
text. Different-process cold reads/resume preserve both histories without
inference. Exact workspace sentinel bytes remain unchanged.

The paginated revert case replaces a non-latest parent prefix while an existing
child retains its inherited third turn plus its own turn. Reverted hydration
cursors include the retained anchor; the removed turn cannot select another
parent revert. Only an explicit new turn continues the parent. Invalid revert
may reload a runtime, so the invariant is stable durable identity, exact history
and no replay, rather than unchanged runtime identity.

A separate legacy-source ephemeral:true case retains the exact inline prefix,
returns true/path:null and permits two actual child continuations. includeTurns
fails explicitly; it does not fabricate durable history. Exact model prefixes
exclude later parent text, no child-named rollout is created, and persistent
parent history remains intact. After confirmed shutdown and a different process,
read returns `thread not loaded` and resume returns `no rollout found` for that
child. Persistent false and ephemeral true are distinct observed branches.

## Immutable source and validation

The exported mutation is thread/revert. This pin has no exported thread/rollback
request, params, result or dispatcher; old internal decoding does not create an
API. References below are relative to the pinned `codex-rs/`:

- `app-server-protocol/src/protocol/v2/thread.rs:556-567,1281-1311` defines inclusive
  lastTurnId versus exclusive beforeTurnId and paginated revert without file undo.
- `app-server/src/request_processors/thread_processor.rs:5191-5234,5412-5422`
  selects the exact fork boundary. `core/src/thread_rollout_truncation.rs:102-193`
  and `thread-store/src/local/paginated_fork.rs:108-154` resolve canonical source
  turns; an unrelated ID cannot select a boundary.
- `core/src/session/mod.rs:1729-1784` materializes copied/referenced persistent
  forks even with no retained turns. `thread_processor.rs:5593-5638` reads the
  child's actual stored history before replying. An ordinary unmaterialized
  zero-turn start is a different path.
- `thread_processor.rs:2149-2460` may stop/reload even on invalid revert;
  `thread-store/src/local/revert_thread.rs:105-153` writes an immutable replacement
  pointing to the exclusive prefix. It retains the existing thread identity and
  prior rollout rather than deleting parent/child history.
- `core/src/session/session.rs:1038-1041` omits LiveThread creation for ephemeral
  work. `thread_processor.rs:3131-3134` rejects its includeTurns request. Exact
  cold read/resume errors are asserted against native output.

From the independent driver in verified Devenv, with `MIX_ENV=test` and the exact
hash-checked `CODEX_BINARY`:

```sh
mix test test/native_fork_boundary_fields_test.exs --seed 501432
mix test test/native_fork_boundary_fields_test.exs --seed 987654
mix compile --warnings-as-errors
mix format --check-formatted test/native_fork_boundary_fields_test.exs
```

Namespace and scoped strict Credo pass. Logs:
`/tmp/samgita-fork-boundary-initial-*-20261024.log`. Three missing fork fields gain
scoped implemented evidence; six existing fields gain non-latest boundary
evidence. No row is verified. Active/incomplete turns, concurrent mutations,
tool history, storage failures/retention, paginated ephemeral:true, other
transports/OSes, real providers and A11 remain unqualified at that checkpoint. The default native CI
suite includes this file; publication and deployment remain separate gates.

## Paginated ephemeral, active and prediction continuation

The later complete seven-file native owning block passes **43/0 twice**, seeds
501432 and 987654, 81.1/80.2 seconds. Root and standalone driver warnings-as-errors
compile, format, namespace preflight and strict Credo438 files pass. The
manifest-inclusive 1,490-file source guard matches at terminal before subsequent
evidence edits. The real binary and immutable source pins above are unchanged.

- Paginated ephemeral fork rejects omitted/false excludeTurns without changing
  the source. Explicit true with before-third returns a pathless live child;
  durable hydration APIs reject. Two real child continuations retain only the
  exclusive prefix and exclude later parent divergence. Exactly six provider
  requests, absent child rollout/list entry, cold read/resume failures and intact
  parent durable history distinguish live state from fabricated persistence.
- A genuine pending dynamic callback holds a paginated turn active. Inclusive
  lastTurnId rejects without allocating a child; exclusive beforeTurnId creates
  an empty persistent idle child and leaves the original callback pending. Exact
  live start, completed user history and absent pending dynamic history are
  asserted separately. Only an explicit success:false reply settles the original
  callback; its failed item and model-visible output are exact. No child turn,
  tool implementation, workspace change or automatic reply occurs.
- Legacy and paginated experimentalPredictionMode forks actually continue with
  inherited base/developer/collaboration instructions and dynamic function
  schema. Five independent provider requests distinguish child, parent and
  separately configured sibling histories. Pathless child absence after confirmed
  shutdown, source/sibling rollout bytes and exact request counts are checked.
  ThreadForkResponse has no collaborationMode field; real child model input
  proves inheritance. This does not qualify the separate blocked prediction API.

Pinned source explains the first failed oracles rather than relaxing them:
`rollout/src/policy.rs:132,142,171-172,212,228-282` persists ItemCompleted, not
transient ItemStarted; `app-server-protocol/src/protocol/thread_history_projection.rs:22-33,78-101`
projects canonical paginated items. The initial active case failed once because
it expected a durable pending dynamic item. Its exact live start, callback,
completed failure and user content remain fully checked after correction.
The initial prediction draft failed twice before startup because it omitted the
required dynamic function type. Adding type:function follows the pinned schema;
the next complete block failed twice on an invented collaborationMode response
field. `app-server-protocol/src/protocol/v2/thread.rs:641-674` and
`thread_processor.rs:5673-5697` omit that field, while
`core/src/thread_manager.rs:1485-1513` inherits live settings. The corrected tests
check absence and the independently expected actual provider instructions/tools.
No timeout, skip, assertion removal, fabricated rollout or native emitter is used.

Upstream `app-server/tests/suite/v2/thread_fork.rs:2353-2442,2715-2844` separately
exercises paginated ephemeral and prediction inheritance. Source-only drafts and
failed logs remain under `/tmp/samgita-native-active-turn-fork-v1-20261025/`,
`/tmp/samgita-native-prediction-fork-inheritance-v1-20261025/` and
`/tmp/samgita-native-cold-process-queue-v10-fork-lifecycles-attempt1-20261025/`.

The terminal runner is
`/tmp/samgita-native-cold-process-queue-v11-fork-lifecycles-attempt2-20261025.py`;
its same-named directory retains exact commands, logs, source and results.
`/tmp/samgita-native-fork-lifecycles-v11-terminal-20261025.json` has SHA256
`666274aed7cfaa722e07ab44eb67c6a7d3a5552c2b477e2e19b40250e9d114cb`.
From the standalone driver, both fixed seeds run:

```sh
mix test test/native_image_view_items_test.exs test/native_thread_fork_settings_test.exs test/image_preparation_test.exs test/native_fork_boundary_fields_test.exs test/native_thread_resume_settings_test.exs test/native_thread_future_settings_test.exs test/native_thread_response_metadata_test.exs --warnings-as-errors --seed 501432
```

Five already implemented ThreadForkParams properties gain bounded behavioral
depth; no new count or verified promotion follows. Concurrent competing fork
mutations, storage failures/retention, complete tool-history combinations,
nonnull reasoning/tier inheritance, cache-hit/full provider-envelope equivalence,
remote stores, other transports/OSes, external services and A11 remain
unqualified. Complete final-source local/hosted qualification remains required.
