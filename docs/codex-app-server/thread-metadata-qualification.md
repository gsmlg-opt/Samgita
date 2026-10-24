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

## Background-plugin fixture repair

Hosted conformance [40063234384](https://github.com/gsmlg-opt/Samgita/actions/runs/40063234384)
at `6dcd341` failed the origin-credential case during its complete recursive
scan: an owned `.tmp/plugins-clone-*/plugins/cloudflare/...` file disappeared
between discovery and `File.read!`. The second driver partition finished
**254 tests / one failure**. It was not a credential-content assertion failure,
but it prevents a passing confidentiality-test claim.

The pinned [plugin default](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/features/src/lib.rs#L1620-L1623)
is enabled. [App-server startup](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/message_processor.rs#L544-L560)
launches plugin warmups; the [plugin gate](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/manager.rs#L2824-L2831)
controls those tasks. Curated startup sync clones into a temporary directory
and renames that checkout. The metadata fixture had not disabled this unrelated
background behavior. This is a fixture-isolation repair, not an upstream defect.

Only this test module's setup now appends supported `plugins = false` and
`recommended_plugins = false` feature settings before any native startup. Shared
fixtures and explicitly enabled plugin profiles are unchanged. Complete response,
rollout, cold-read and recursive file-content assertions remain intact, as do
`File.read!`, process guardians and zero-provider-request checks. No disappearing
file is ignored, no scan path is excluded and no sleep/deadline is changed.

Serial warnings-as-errors compile, formatting, both complete metadata/prediction
repeats and strict Credo pass. Each repeat reports **13/0** (seven metadata plus
six prediction cases), seeds `501432`/`987654`, 33.3/33.2s. Full commands, exits
and logs: `/tmp/samgita-native-metadata-repair-20261024/`. The next final-source
hosted partition must validate the repair there. No schema entry or verified
status is promoted, and this does not audit all other fixtures' background
activity or close platform A11.
