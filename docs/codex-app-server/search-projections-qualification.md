# Native search organization projections

Two new real-native cases qualify selected metadata in the exact
`v2/ThreadSearchResponse.json` owner, adding **26 implemented physical contracts**.
No other Thread schema owner, whole method or verified promotion is inferred.
The target remains Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Every selected physical node/hash was independently checked before indexing.

The retained timeline/search suite already exercises snippets, IDs, filters,
cursors and archive behavior. `native_search_projections_test.exs` adds the
previously absent current section/project mutations and independent metadata
oracles, using two distinct owned histories containing the same Unicode query:

- A section move changes only its selected member. Search returns the known
  ID/name/appearance and a bounded positive entry timestamp; a cold process
  retains them. Renaming/recoloring updates the same search result without
  changing entry time. Deleting the section explicitly clears both fields,
  with the control member remaining unsectioned throughout.
- Two project imports classify different histories. Search preserves each
  project ID through changed-payload idempotency replay and cold reads. Deleting
  the selected project clears only its member, including another cold restart.

Every query also checks the independently assigned name/cwd/history mode,
correlated path/session/provider, explicit ephemeral false and exact loaded-idle
versus cold-notLoaded maps. Search is metadata-only with empty turns, while
separate full reads retain the original completed turn. The original rollout
bytes and two local synthetic provider requests remain unchanged through all
organization mutations. This does not qualify transcript item fields, legacy
history mode, ephemeral true, other statuses or appearance-null behavior.

The harness hashes the official binary, inherits no credential environment,
disables unrelated plugin/app startup and adds only the explicitly discovered
ripgrep executable to its private PATH. No command/tool is requested. Native
read barriers establish persistence; there is no search polling or frame
synthesis. Owned processes use the retained cleanup guards.

The host must supply `rg` on PATH before this test starts. Install the `ripgrep`
distribution package for local Debian/Ubuntu runs. The selected conformance CI
job installs it explicitly before its required driver partitions; the fixture
then adds the discovered executable to its owned bin directory. A missing tool
fails setup with `BLOCKED_ENV: ripgrep required`, rather than skipping content
assertions or inheriting an unrestricted child environment. Provisioning this
prerequisite does not itself establish a passing hosted run.

Pinned producers are `protocol/common.rs:840-845`,
`protocol/v2/thread.rs:1581-1602`,
`thread_processor.rs:2765-2815,2858-2884,6396-6445`,
`thread_enrichment.rs:38-59` and `thread-store/src/local/search_threads.rs:69-141`.
These identify the method-specific stored/live metadata join, not runtime proof
by themselves.

With `CODEX_BINARY` set to the pinned executable, from the driver directory:

```sh
mix test test/native_search_projections_test.exs --seed 501432
mix test test/native_search_projections_test.exs --seed 987654
```

Both passed **2/0**, 3.1s each. Compile with warnings-as-errors, package format,
root strict Credo and the focused source guard passed. Exact commands, test
hashes, exits and complete logs:
`/tmp/samgita-native-search-projections-v1-20261024/`.
Final-source aggregate/hosted qualification, A11, immutable non-emitting paths
and real external/OS success remain separate and incomplete. No publication or
deployment occurred.
