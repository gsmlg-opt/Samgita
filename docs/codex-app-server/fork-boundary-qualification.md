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
transports/OSes, real providers and A11 remain unqualified. The default native CI
suite includes this file; publication and deployment remain separate gates.
