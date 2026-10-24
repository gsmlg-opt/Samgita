# Native thread attribution and projection boundaries

Six new cases run stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, with executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The combined attribution/managed-policy block passes **24/0** at seeds `501432`
and `987654`, 46.6 and 48.1 seconds. These are actual native responses; the
loopback Responses fixture supplies only the three search conversations.

`native_thread_source_test.exs` demonstrates omitted, explicit null, `user`,
Unicode custom and empty-string attribution for both legacy and paginated
history. Native `thread/started`, read-by-ID and the owned canonical SessionMeta
retain the exact value. The canonical file omits an absent source; the public
response explicitly includes null. A fork resets omitted/null child attribution
instead of inheriting its parent. Explicit child labels survive confirmed owned
shutdown and cold read/resume without changing the parent's metadata.

Metadata-only threads are deliberately absent from ordinary discovery, under
both default filters and explicit `sourceKinds:[vscode], modelProviders:[]`.
Each still reads by ID with zero turns, exact metadata and source. This is the
native preview requirement, not lost persistence. The search case completes
exactly three conversations and asserts the complete expected ID set and exact
snippets. Search and loaded post-turn reads project `threadSource:null`; the
canonical file and cold includeTurns/read/resume retain original attribution.
The driver preserves the native null instead of reconstructing a value.

Stable negotiation accepts this field. Malformed integer, boolean, array and
object values return native invalid-request errors without changing loaded IDs,
metadata or model request counts. Metadata-only cases make zero model requests;
the search case makes exactly three. Every case retains pending-request,
unexpected-interaction, native process ownership and cleanup checks.

## Failed draft and exact upstream semantics

The initial combined seed `501432` run had **24 tests, seven failures** in 42.3
seconds. Six belonged here: five expected named metadata-only threads in lists;
one expected a loaded post-turn read to return the original source. The seventh
was the independent managed-default expectation documented in
[managed model defaults](managed-model-defaults-qualification.md). The complete
failed log remains under
`/tmp/samgita-native-attribution-policy-20261024/attempt-01/`.

The correction follows these pinned `codex-rs/` paths:

- `state/src/runtime/threads.rs:1412-1450` excludes empty previews;
  `rollout/src/list.rs:775-816` separately enforces the same condition. Naming
  a zero-turn thread does not supply a preview; no general public include-empty
  switch exists. Explicit source/provider filters retain the exclusion.
- `app-server/src/request_processors/thread_processor.rs:2974-2990` selects
  persisted metadata for loaded reads. With a preview,
  `thread-store/src/local/read_thread.rs:60-94` replaces its display metadata
  with a rollout summary. `thread-store/src/local/helpers.rs:184` assigns
  `thread_source:None`. This explains the null projection.
- Cold history reads use `read_thread.rs:46-55,376-428` and preserve the state
  metadata. Resume explicitly restores `config_snapshot.thread_source` at
  `thread_processor.rs:4316-4320`. Fork explicitly replaces the source, including
  None, at `:5406,5476-5480`.
- `protocol/src/protocol.rs:3007-3017` supports open custom strings, including
  empty strings. `:3276-3278` omits absent source in canonical SessionMeta.
  Public start/fork source fields at `app-server-protocol/src/protocol/v2/thread.rs:122-124,620-622`
  have no experimental gate.

No deadline, retry, cleanup guard or production code changed. The corrected
block passes both seeds, warnings-as-errors compilation, namespace preflight,
scoped formatting and root strict Credo. Commands and complete results remain
under `/tmp/samgita-native-attribution-policy-20261024/attempt-02/`:

```sh
mix test test/native_managed_requirements_test.exs test/native_managed_provider_requirements_test.exs test/native_managed_feature_requirements_test.exs test/native_managed_model_defaults_test.exs test/native_thread_source_test.exs --seed 501432
mix test test/native_managed_requirements_test.exs test/native_managed_provider_requirements_test.exs test/native_managed_feature_requirements_test.exs test/native_managed_model_defaults_test.exs test/native_thread_source_test.exs --seed 987654
```

Only ten exact source-field contracts gain scoped implemented evidence: both
start/fork nullable-string fields and branches, native thread/started's source
field and branches, and the search null branch. The entire search source field,
its string-success branch, other stores/transports/OS and fully verified status
remain incomplete. Full source, aggregate and hosted qualification are separate
gates. No release, deployment or external integration is inferred.
