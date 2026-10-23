# Native fuzzy file search qualification

This unit targets the immutable Codex `rust-v0.163.0` executable at commit
`83086188ae0614bd882818ff1aa23f3194962012` through the existing Linux stdio
driver. It covers the stable `fuzzyFileSearch` request and experimental
`fuzzyFileSearch/sessionStart`, `/sessionUpdate`, and `/sessionStop`, including
their native notifications. It introduces no production implementation, model
provider, listener, database, or external service.

Current status: all nine actual-binary cases pass with seeds `501432` and
`987654`. Compilation with warnings as errors and formatting checks pass.
This qualifies the selected Linux stdio/local synthetic behaviors below;
external services and other profiles remain unqualified.

## Pinned source contract

Paths below are relative to the pinned upstream `codex-rs/` directory:

- `app-server-protocol/src/protocol/common.rs:1497–1523,1869–1947` declares
  stable one-shot search, experimental session methods, camelCase request and
  notification fields, snake_case match fields, and file/directory match types.
  `sessionCompleted` contains only `sessionId`, without query identity.
- `app-server/src/request_processors/search.rs:39–78` accepts nullable
  cancellation tokens, sets the previous same-token cancellation flag and
  returns search results without a distinct cancellation error. The methods are
  intentionally unserialized so overlapping same-token requests can cancel.
- `app-server/src/request_processors/search.rs:81–134` rejects an empty session
  ID, wraps session construction errors, replaces an existing same-ID session,
  rejects updates for absent sessions and treats stop as idempotent removal.
- `app-server/src/fuzzy_file_search.rs:1–97` limits results to 50, computes
  indices, and orders by descending score then ascending path. Independent roots
  have no extra root ordering guarantee. Empty roots and search failures yield
  empty one-shot results.
- `app-server/src/fuzzy_file_search.rs:98–219` cancels a dropped session,
  suppresses canceled and stale-query snapshots, forces an empty snapshot for
  an empty query, and spawns update/completion notification delivery tasks.
  An already-spawned task can outlive the stop response.
- `file-search/src/lib.rs:44–58,116–166,169–216` defines sorted unique character
  highlight indices, default gitignore handling, query completion callbacks,
  shutdown behavior and the empty-root construction error.
- `file-search/src/lib.rs:413–452,515–587` allows hidden files, requires Git
  context for gitignore handling, uses case-insensitive matching and smart
  normalization, and emits completion when the matcher is idle after walking.
- `app-server/tests/suite/fuzzy_file_search.rs:220–300` fixes the exact
  `abe` fixture score/order/indices asserted here. Lines 355–619 cover stream
  updates, case matching, idle completion, stop, separate roots and clear query.
  Its 250 ms stop grace and 500 ms short observation windows define the bounded
  cessation check used here.
- `app-server/src/message_processor.rs:112–116,974–980` defines malformed-native
  request errors and experimental-capability enforcement.

## Verified behavior checks

`apps/samgita_codex_driver/test/native_fuzzy_search_test.exs` contains nine cases:

1. Exact upstream one-shot ranking, scores, relative paths and indices.
2. Multiple-root identities, file/directory metadata, preserved Unicode filename
   and character-based highlighting, without inventing ordering between roots.
3. Git context honors `.gitignore`; hidden files remain searchable; a plain
   non-Git directory does not apply Git-only ignore rules.
4. Empty query, no roots, nonexistent roots, no matches, and omitted/null/reused
   cancellation tokens return their native one-shot results.
5. A session first reaches idle, then supports uppercase, no-match, changed and
   cleared queries. Each result correlates its session and query, and completion
   remains distinct from stop. Bounded idle observation precedes a later update.
6. Independent session IDs retain separate roots. Replacing an ID moves its
   root selection while preserving the other session.
7. A populated 512-file session yields a bounded snapshot, stop succeeds, a
   subsequent update produces the exact missing-session error, and bounded
   observation checks for later update/completion notifications. Repeated and
   missing-session stops succeed.
8. Empty session ID, empty session roots, unknown session, malformed types and
   missing required fields produce native errors; malformed cases also reject
   under local schema validation.
9. With absent or false experimental negotiation, stable search remains usable;
   all three session methods reject locally and at the actual native server.

The fixture owns temporary HOME, CODEX_HOME and search roots. All configured
provider/account origins point at inert loopback port 9, and no turn/thread or
model request is issued. Each explicitly started stdio session registers native
transport cleanup before initialization. No Python fixture is needed.

## Verification and limits

Prepared from baseline `d74672f0a23633fa96c3f66836de8082a370b3e2` on
2026-10-24. Runtime qualification began at
`a8852e9feff8d8a2f3524b10f1f79b46d2347add`, after the parent granted the
exclusive build/process slot. The following command completed with exit `0`:

```sh
devenv shell --no-tui -- bash -c 'cd apps/samgita_codex_driver &&
  MIX_ENV=test mix format test/native_fuzzy_search_test.exs &&
  MIX_ENV=test mix compile --warnings-as-errors &&
  MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_fuzzy_search_test.exs --include real_codex --seed 501432 &&
  MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_fuzzy_search_test.exs --include real_codex --seed 987654 &&
  MIX_ENV=test mix format --check-formatted test/native_fuzzy_search_test.exs'
```

- Seed `501432`: **9 tests, 0 failures**, 5.6 seconds.
- Seed `987654`: **9 tests, 0 failures**, 5.7 seconds.
- Compile with warnings as errors and changed-file formatting checks passed.
- Initial implementation passed; no repair round was needed.
- Command log: `/tmp/samgita-native-fuzzy-initial.log`.
- The coordinator reran these nine cases with the native Apps catalog and
  history regressions: **23 passed** at each seed, with strict Credo and
  independent format/compile checks passing. Log:
  `/tmp/samgita-codex-followup-final-integration-3.log`.
- Post-command process inspection found no pinned Codex app-server or fuzzy
  test command remaining. All disposable sessions registered owned transport
  cleanup; no background model provider/listener was created.
- Scoped whitespace checks produced no diagnostics.

The notification helper accumulates messages through a monotonic deadline and
checks native session readiness/gaps. It waits for the startup idle completion
before associating completion with subsequent query edits. Stop checking uses
the stop response and an exact missing-session error as native barriers, allows
the upstream 250 ms grace, and then observes a separate 500 ms absence window.
This is bounded evidence, not proof of an absolute notification fence.

Sequential cancellation-token reuse does not prove cancellation of an overlapping
one-shot search. That behavior needs a reproducible in-flight barrier, which
this fixture does not provide. Stop proves session removal, rejected reuse and
bounded observable cessation; it does not prove that work was still in flight
at the moment of cancellation. External/platform profiles, other operating
systems, symlink edge cases, arbitrary Unicode normalization, paid/provider
execution and full product compatibility remain outside this unit.
