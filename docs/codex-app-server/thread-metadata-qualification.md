# Native thread metadata qualification

Target: immutable Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`. The executable is the pinned Linux
musl binary with SHA-256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

Seven cases in `apps/samgita_codex_driver/test/native_metadata_test.exs` passed
actual-binary validation at seeds `501432` and `987654`. Each case uses an
isolated temporary Codex home
and local synthetic ModelFixture, and requires zero model requests. No Git remote
is contacted and no real credentials are used.

## Contract and ownership

`thread/metadata/update` changes Codex's stored thread metadata. It grants no
Samgita Project membership or Task authority. Persistent Git metadata is a patch:
omitted fields preserve values, explicit null clears them, and strings replace
them after trimming. Nonempty Git patches may operate without experimental API
negotiation. `projectId` and `daybreakEnabled` require experimental negotiation
when nonnull. Null outer Git/project/Daybreak options do not constitute an update.

An existing nonempty project ID assigns a thread; an empty string clears its
assignment. `thread/project/updated` is emitted only for an actual membership
change. Daybreak records a persistent client preference; it does not choose a
turn's `cyberAccessProgram` or grant access. The handler permits archived-thread
updates. Ephemeral threads reject metadata mutations.

## Verified selected behavior

| Case | Assertions |
| --- | --- |
| Git patch semantics | Full/partial updates, trimming, omitted fields, null clearing, response association and cold updates before any model turn. |
| Origin sanitization | HTTPS/SSH credentials and nonstandard SCP user names are removed; conventional SSH `git` identity survives. Response, rollout and cold read preserve sanitized origins; synthetic credential markers are absent from owned persisted files. |
| Presence and validation | Omitted/null outer patches and empty objects have distinct behavior. Empty strings, malformed Git remotes and wrong types reject without modifying prior Git metadata. |
| Project membership | Assign, null/omitted preservation, clear and repeated no-op notifications; project changes survive cold reads and updates. |
| Experimental fields | Absent and false capability negotiation reject nonnull project/Daybreak fields locally and in the real server; stable Git and null field options remain usable. |
| Daybreak and archives | True/false and null preservation, cold restart, archived updates and persisted archived reads without executing a turn. |
| Atomic failure boundaries | Nonexistent project/thread, invalid identity, empty/invalid Git paired with assignment and ephemeral-thread rejection preserve unrelated persistent state and emit no membership change. |

The Session drains notifications separately from RPC results. Notification
assertions establish association and no-op behavior; they do not establish wire
ordering relative to RPC responses.

## Pinned source

Paths are relative to `codex-rs/` at the source commit above.

- `app-server-protocol/src/protocol/common.rs:666-670`: stable method dispatch
  with experimental field inspection.
- `app-server-protocol/src/protocol/v2/thread.rs:1033-1094`: request, double-option
  Git patches, experimental project/Daybreak fields and response.
- `app-server/src/request_processors/thread_processor.rs:1940-2089`: project
  existence, patch validation, sanitization, clearable membership, archived
  updates and conditional project notification.
- `app-server/src/request_processors/thread_processor.rs:2092-2108`: trimming
  and empty-string rejection.
- `core/src/thread_manager.rs:979-1018`: loaded/cold routing and ephemeral
  rejection.
- `protocol/src/sanitized_git_url.rs:26-108`: Git remote parsing and credential
  removal without remote contact.
- `app-server/tests/suite/v2/thread_metadata_update.rs:596,697,781,832,1130`:
  upstream patch, sanitization, empty-patch, ephemeral and null-clear examples.

## Verification and limits

From the repository root, validation ran inside `devenv shell --no-tui --` and
then `apps/samgita_codex_driver`:

```sh
MIX_ENV=test mix format test/native_metadata_test.exs
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_metadata_test.exs --include real_codex --seed 501432
MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_metadata_test.exs --include real_codex --seed 987654
MIX_ENV=test mix format --check-formatted test/native_metadata_test.exs
```

The combined command exited zero. Both seed runs passed **7 tests, 0 failures**
(29.9 and 29.4 seconds respectively). The local combined log is
`/tmp/samgita-codex-native-metadata.log`; the initial failed expectation is retained
in `/tmp/samgita-codex-native-metadata-initial.log`.

The first run passed six cases. Its remaining assertion incorrectly expected a
generic missing-thread message for a cold Git metadata update. This path requires
rollout compatibility and reads the cold thread first. The actual error is
`no rollout found for thread id <uuid>`, with code `-32600`, from
`thread-store/src/local/update_thread_metadata.rs:78-91` and
`thread-store/src/local/read_thread.rs:91-102`.
`core/src/thread_manager.rs:2564-2568` and
`app-server/src/request_processors/thread_processor.rs:6343-6350` preserve that
InvalidRequest message. One source-backed fixture repair corrected only the
expected literal; exact error-code/message and unchanged-state assertions remain.
There is no runtime implementation change or manufactured failing implementation
test.

Other transports and operating systems, remote/enterprise thread stores,
concurrent writers, missing-row repair, every Git URL form and Daybreak access
or execution remain unqualified. This unit does not establish full Codex
compatibility, production readiness, publication or deployment.
