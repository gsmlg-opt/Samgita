# Native skills lifecycle qualification

This unit targets immutable Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`, through the existing Linux stdio
driver. It expands earlier skills smoke checks into durable settings, runtime
roots, ordered discovery, local plugin reload and filesystem boundaries. It
changes no production code or shared fixture.

Current status: all eight actual-binary cases pass with seeds `501432` and
`987654`. Compilation with warnings as errors, formatting, strict Credo in the
verified test environment and scoped whitespace checks pass. This qualifies only
the selected Linux stdio/local synthetic behavior; full compatibility remains
incomplete.

## Pinned source contract

Paths below are relative to the pinned upstream `codex-rs/` directory:

- `app-server-protocol/src/protocol/common.rs:894–903,1042–1046` declares all
  three skills methods stable. `skills/list` uses
  `global_shared_read("config")`; both mutations use `global("config")`.
  There is no public skills revision, expected-version field or CAS response.
- `app-server-protocol/src/protocol/v2/plugin.rs:21–47,934–948` defines default
  cwd discovery, force reload, absolute extra roots, optional path/name selectors
  and the required enabled boolean. `v2/tests.rs:3928–3935` explicitly rejects
  relative extra roots.
- `app-server/src/request_processors/catalog_processor.rs:21–68,110–123`
  projects disabled-path membership into `enabled`, preserves plugin identity
  and maps per-file loading errors into list entries.
- `catalog_processor.rs:515–592` defaults an empty cwd vector to the server cwd,
  resolves each cwd configuration, loads at most five entries concurrently and
  restores requested order. Force reload clears both plugin and skills caches.
  A malformed cwd configuration becomes an entry error rather than failing the
  entire request; this unit directly exercises per-skill parse errors instead.
- `catalog_processor.rs:595–614` replaces process runtime roots, registers their
  watcher paths, clears skills caches through the service, and awaits a broadcast
  `skills/changed` notification with empty params before returning success.
- `catalog_processor.rs:681–724` requires exactly one path/name selector and
  rejects an empty trimmed name with native `-32602` and the exact message
  `skills/config/write requires exactly one of path or name`. The write is to
  user configuration, then clears both caches. `effectiveEnabled` echoes the
  requested action; it is not a freshly resolved list snapshot after other rules.
- `core/src/config/edit.rs:499–606,704–708` trims names, canonicalizes existing
  paths, upserts a matching disable override, removes only the matching selector
  when enabling and prunes empty skills tables. Unrelated configuration remains.
- `config/src/skills_config.rs:103–132,165–207` applies ordered rules and limits
  skill enablement rules to user/session layers. Path and exact-name selectors
  can independently disable the same skill. A selector can precede its skill.
- `ext/skills/src/host_service.rs:154–163,300–372` replaces runtime roots and
  clears cached snapshots, then resolves enablement against the loaded catalogue.
- `ext/skills/src/host_roots.rs:58–140` combines user, plugin, runtime and
  repository roots, deduplicating paths. User/runtime roots use host-local file
  authority; repository roots require an environment filesystem.
  `loader/host.rs:67–78` assigns plugin skills user scope with separate plugin
  identity. `exec-server/src/environment.rs:88–100` documents
  `CODEX_EXEC_SERVER_URL=none` as explicitly disabling the default/local
  environment.
- `ext/skills/src/loader/host_merge_tests.rs:433–509` preserves partial skill
  loading and the exact `missing YAML frontmatter delimited by ---` error.
- `core-plugins/src/manager.rs:821–825` returns no plugin catalogue when plugins
  are disabled. Upstream native reference journeys are in
  `app-server/tests/suite/v2/skills_list.rs:731–935,1024–1336`.

The pre-existing `method_families_test.exs` checks user-skill enable/disable and
runtime-root add/clear. `plugin_selection_test.exs` incidentally checks installed
skill discovery while qualifying explicit turn selection. Neither establishes
the complete lifecycle below.

## Eight verified scoped cases

`apps/samgita_codex_driver/test/native_skills_lifecycle_test.exs` owns:

1. Default and empty cwd discovery, requested order across more than five cwd
   entries including repeats and a relative cwd, valid metadata alongside exact
   malformed-frontmatter errors, and repaired metadata after explicit reload.
2. Canonical path selection through an owned symlink, repeated disable without
   duplicate overrides, ordinary-list cache invalidation, native restart
   persistence, and enabling that removes only its override and restores the
   original synthetic configuration.
3. Trimmed exact-name selectors, independent name/path rules and requested
   `effectiveEnabled` distinct from resolved list state; preconfiguring a name
   before its synthetic skill appears does not affect unrelated skills.
4. Concurrent independent path writes against one native server, retaining both
   settings across restart, followed by concurrent removal of both overrides.
   This tests native global serialization without inventing cross-process CAS.
5. Runtime-root replacement, duplicate-path deduplication, missing roots, empty
   clear, matching empty change notices, unchanged configuration and loss of an
   uncleared runtime root on native restart.
6. Installation from an owned local marketplace, namespaced skill/plugin identity
   and installed path, manifest root replacement plus force reload, refreshed
   discovery from another cwd, and feature/plugin disablement removing skills.
7. Explicitly disabled execution environment excludes repository skills while
   owned user/runtime skills remain available. Every source/root stays inside
   the test's disposable scratch tree; no remote authority is exercised.
8. All three stable methods work with absent/false experimental negotiation.
   Invalid selectors, missing/wrong-type fields and relative extra roots retain
   native errors while preserving configuration and existing runtime roots.

## Fixture and validation boundaries

The test reuses `TurnFixture`, `ModelFixture` and `StdioSessionFixture` unchanged.
Each case owns temporary HOME, CODEX_HOME, workspace, skill/plugin roots, loopback
provider, native process and cleanup. Cleanup is registered immediately after
native startup. The existing loopback provider stays unused: every case requires
an empty model-request journal. No turn, real credential, remote plugin, paid
model, platform database, external service or production task is used.

Prepared at repository baseline
`f5fc91555e2b4a3fe171fa418ffdd24737b5c955` and qualified after parent integration
at `1f1dc5ec27f4cfb07efb4502eb1152968b81c98e` on 2026-10-24. The draft remained
at `/tmp/samgita-native-skills-lifecycle-test.exs` outside discovery until the
coordinating agent granted the exclusive validation slot. The complete command
below exited `0` on its first run, with **8 tests, 0 failures** for each seed
(`501432`: 5.1 seconds; `987654`: 5.1 seconds):

```sh
devenv shell --no-tui -- bash -c 'cd apps/samgita_codex_driver &&
  MIX_ENV=test mix format test/native_skills_lifecycle_test.exs &&
  MIX_ENV=test mix compile --warnings-as-errors &&
  MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_skills_lifecycle_test.exs --include real_codex --seed 501432 &&
  MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_skills_lifecycle_test.exs --include real_codex --seed 987654 &&
  MIX_ENV=test mix format --check-formatted test/native_skills_lifecycle_test.exs'
```

Full output is retained at `/tmp/samgita-native-skills-initial.log`. No assertion,
runtime, schema or timeout repairs were needed. Cumulative Sol repair rounds: 0;
Astra repair rounds: 0.

The first root lint invocation accidentally used the default development
environment and failed before analysis while compiling unrelated
`telemetry_metrics`: `found error while checking types for
Telemetry.Metrics.ConsoleReporter.terminate/2`, with a `beam_lib` atom-decoding
`badarg`/`MatchError`. The failure is preserved at
`/tmp/samgita-native-skills-credo-initial.log`. No dependency or build-artifact
repair was attempted. Using the already established test environment, this
command exited `0`:

```sh
devenv shell --no-tui -- bash -c 'MIX_ENV=test mix credo --strict --files-included apps/samgita_codex_driver/test/native_skills_lifecycle_test.exs'
```

Credo analyzed 310 files with 69 checks and found no issues; output is retained
at `/tmp/samgita-native-skills-credo-test.log`. Scoped `git diff --check` passed.
All owned pinned-native and provider processes were reaped; shared host
processes were left untouched and the exclusive validation slot was released.
The default development-environment dependency compilation remains unqualified.

The native binary was independently SHA256-checked as
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215` at
`tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl`.

Only selected Linux stdio/local synthetic behavior is in scope. Remote plugin
catalogues, remote/executor filesystem authority, cross-process writes, watcher
delivery latency/exact counts, all bundled-skill/session-rule combinations,
per-cwd invalid-configuration recovery, external/platform success and A11 remain
unqualified. Empty change notices carry no mutation ID or revision; this unit
uses awaited request barriers and does not infer a stronger notification contract.
These checks cannot establish full compatibility, publication or production
readiness.

The manifest associates this selected evidence with seven skills request,
response and notification entries and 22 directly asserted fields/variants.
They advance only to `implemented`; dependency/interface projections, null
selector branches and the remaining profiles retain their unqualified status.
