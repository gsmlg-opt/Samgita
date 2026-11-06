# Dependency modernization

Date: 2026-11-05. The user approved documentation and code migration on the
existing branch. This changes infrastructure libraries, not domain ownership,
Agent authority, Task acceptance or external execution policy. Implementation
and verification results are recorded below separately from the target.

## Target and package boundaries

| Responsibility | Previous library | Target |
| --- | --- | --- |
| JS/TS, CSS, package installation and asset manifests | Bun and Tailwind CLI | `duskmoon_bundler` / `duskmoon_bundler_runtime` / `duskmoon_npm` |
| Phoenix endpoint and standalone fake-Agent listener | Bandit | `gaoxy_http`, backed by Gaoxy, with `gaoxy_websock_adapter` |
| Durable queues, maintenance and periodic wakeups | Oban | Styx on the authoritative PostgreSQL Repo |
| Outbound GitHub HTTP | Mint | `http_fetch` |
| Neutral protocol and Codex driver WebSocket clients | Mint / `mint_web_socket` | Companion `http_web_socket`, subject to preservation of the existing transport contract |

The package-source review used published `duskmoon_bundler` 10.0.9,
`gaoxy_http` 0.14.1, `styx` 0.1.1 and `http_fetch` 0.21.19. These are
source/API evidence, not successful runtime qualification. Resolved versions
belong in the relevant lockfiles. Each standalone package retains its own
build, dependencies and configuration; the umbrella still contains core/web only.

Core never depends on web. The pure protocol and native schema packages acquire
no HTTP listener, asset pipeline, database dependency or automatic execution.
Servers and clients retain explicit ownership and startup. Existing Sigma and
Synapsis endpoints stay in their services.

## Assets and inbound HTTP

DuskmoonBundler owns the named `samgita_web` profile, development watcher,
production manifest and asset runtime helpers. Package installation moves to
Mix npm tasks and a root workspace lockfile. Build/release aliases, frozen
installation helper, Docker and CI asset preparation must use the same path.
The build toolchain stays available for production compilation but is not
started in the release. The runtime helper remains available in production.
The workspace uses `package-lock.json`. The runtime profile uses a release-relative
`priv/static/assets` path rather than a build-host absolute path.

This replaces the independent Tailwind executable. Existing utility classes,
Tailwind v4 CSS directives, DuskMoon themes/components, Heroicons and LiveView
variants remain supported by the bundler's integrated CSS pipeline. This is not
a component-library or UI redesign. Verify both ordinary and production asset
builds and the actual emitted manifest, scripts, styles and icons.

The existing Phoenix Endpoint owns its Gaoxy listener through
`Gaoxy.PhoenixAdapter`; do not add a duplicate server child. The optional
standalone protocol server explicitly owns `Gaoxy.HTTP`. Both use the
Gaoxy-compatible WebSock adapter, including independent consumer dependency
resolution. Keep listener addresses/ports, routing and application controls.
Replacing Bandit alone does not close the recorded A11 telemetry boundary.

## Durable jobs and preservation

Styx uses new `styx_jobs` storage installed by an additive migration. Keep all
old migration sources byte-for-byte, and keep Oban as a non-runtime dependency
because historical migrations invoke `Oban.Migration` / `Oban.Migrations`.
No Oban supervisor, queues or plugins run in the new application.
The release explicitly includes `oban: :load` so historical migration modules
remain available without starting the old engine.

Keep the four queues and concurrency limits: `hub_events: 10`,
`hub_schedules: 1`, `hub_maintenance: 1`, `hub_github: 2`. The three minute
Cron wakeups remain schedule scanning, coordination maintenance and GitHub
maintenance. Explicitly disable pruning, automatic orphan-job rescue and
reindexing. Manual test mode disables autonomous queue execution.

Domain events, receipts and job insertion still share a Repo transaction;
enqueue failure must roll back the originating command. Transaction-owned
insertion uses `Styx.insert/2` with `retry: false`, as required
by Styx's nested-transaction contract. Job uniqueness and
snooze/cancel/retry results retain their meanings. Domain delivery and sync
rows, not queue attempt counters, own retry eligibility, uncertainty and
reconciliation. The schedule cursor, UTC occurrence identity, DST behavior
and bounded catch-up remain in `Samgita.Schedules`; only its Cron parser changes.

Old `oban_jobs` rows are neither copied, renamed, replayed, pruned nor deleted.
Legacy-job admission checks read both stores and report a `store` discriminator,
so new quarantined jobs remain visible alongside old jobs. New legacy hook
notifications enter the disabled Styx `legacy_webhooks` queue and propagate
enqueue errors; no historical executor returns. Job IDs are scoped to their
storage table and are not translated between engines.

Before any real cutover, inventory and stop old producers/consumers, reconcile
executing effects and establish a single runtime owner. A code change is not
proof of a drained deployment. A rollback switches binaries and disables the
new consumers; it preserves both job stores and requires reconciliation before
old consumers resume. The additive migration's down operation retains history.
This task authorizes isolated local rehearsal only, not production migration.

## Outbound transport

Preserve the injectable GitHub HTTP contract and its status/headers/body result.
Use the validated literal destination as `connect_address`, preserve URL host
identity, disable redirects and automatic replay, and retain the existing
response byte and request deadline limits. Capture the original Fetch promise's
completion handle; body availability is not proof of socket cleanup. On timeout
or a size-limit failure, cancel and await resource completion within a bounded
cleanup budget. Cleanup that cannot be confirmed must not be reported as clean.

The WebSocket migration must preserve address pinning, failed-upgrade status
and Retry-After classification, negotiated response metadata, frame/message
bounds, initialization, correlation, ACK handling, cancellation and explicit
owned/borrowed resource retirement. Do not replace a transport merely because a
new API can connect. A confirmed missing upstream capability blocks that slice;
route it through an upstream issue and keep the existing working transport
until the published fix can be adopted and functionally verified.

## Implementation ownership and verification

1. Asset/server owner: web manifests/assets/layout/Endpoint, root asset aliases,
   package workspace, installation helper, Docker/devenv/workflow preparation.
2. Client owner: GitHub HTTP, optional protocol server, independent WebSocket
   transports and their package manifests. No shared root build mutations.
3. Integrator: Styx workers/enqueue/Cron, additive migration, shared config,
   dependency resolution, documentation and final integrated checks.

Shared Mix/dependency/build state is serialized. Preserve unrelated untracked
files. Do not create branches/worktrees, publish, release, restart shared
services, deploy or use real credentials/services.

Review functional test names before execution. Verify transaction rollback,
durable insertion/deduplication, worker scheduling and retained job history with
an explicitly named `samgita_redesign_*_test` database. Compile the umbrella and
standalone packages, build assets and check the final diff. Preserve existing
tests when adapting engine types. Security/permission tests, audits, mixed broad
suites and automatic hosted workflows remain prohibited. Their gates are
unrun/incomplete, not waived. Full Codex compatibility, A11 and production
cutover retain their existing separate boundaries.

## Result

Implemented DuskmoonBundler 10.0.9, Gaoxy HTTP 0.14.1, Styx 0.1.1 and GitHub
HTTP via http_fetch 0.21.19. Bandit remains a test-only dependency for retained
historical telemetry evidence; production listeners and the release use Gaoxy.
Oban remains available only for historical migration code and fixtures.

The WebSocket client slice is blocked by
[http_fetch #152](https://github.com/gsmlg-dev/http_fetch/issues/152). Reviewed
http_web_socket 0.21.19, 1.0.0-rc.0 and upstream main `3eee470f` lack the existing
address-pinning, bounded handshake metadata and independent frame/read-limit
contracts. Both Mint WebSocket clients remain intact with upstream TODOs. Resume
only after a published fix can preserve and verify those contracts.

Permitted local verification passed 22 distinct functional cases:

- 11 file-selected cases: Styx insertion/deduplication/configuration, HTTP response
  streaming/limits/failure, schedule worker, core status and populated-history
  migration down/up preservation.
- Five line-selected cases: normal schedule occurrences, bounded catch-up, DST,
  durable lost-wakeup/duplicate delivery and atomic enqueue rollback.
- Three dashboard LiveView cases.
- Three standalone WebSocket wire/lifecycle cases; approval interactions excluded.

The umbrella and standalone WebSocket package compiled with warnings as errors.
Changed Elixir files passed formatting checks. Frozen workspace installation
passed both normally and in an isolated copy. Historical migration sources are
unchanged. The supported Ubuntu 26.04 Docker build completed asset deployment,
application compilation, release archive and runtime image assembly. Inspection
confirmed Oban is loaded rather than started; Bandit and build-only tooling are
absent from the release.

The host asset build failed because glibc 2.42 cannot load Vize's published GNU
artifact, which requires glibc 2.43. This is the intentional upstream baseline in
[duskmoon-bundler #9](https://github.com/duskmoon-dev/duskmoon-bundler/issues/9#issuecomment-6396025627),
closed as not planned. No downgrade or native-build workaround was introduced.
Docker now pins the verified Ubuntu 26.04 builder/runtime images; the three
changed workflows pin the generally available `ubuntu-26.04` runner instead of
depending on the November `ubuntu-latest` rollout. Hosted workflows were not run.
The development watcher remains unverified on this host.

Browser checks against an owned isolated Gaoxy listener verified `/`, `/projects`
and `/agents`, loaded hashed JS/CSS, connected LiveSocket, registered DuskMoon
elements and applied theme CSS. Two existing Google font requests encountered
`ERR_NETWORK_CHANGED`; application assets loaded successfully. An extra packaged
release migration attempt could not access the disposable PostgreSQL Unix socket
mount; its fixture access failure is not a successful release migration rehearsal.
The populated-history migration test above passed in the host test environment.

Reproduce the reviewed selection in a verified Elixir/OTP environment, with
`PGHOST`, `POSTGRES_PORT` and `SAMGITA_TEST_DATABASE` set **inside** the devenv
command to an owned isolated cluster. Run file-only and location-selected groups
separately, because Mix applies location filtering globally:

```sh
mix test apps/samgita/test/samgita/styx_test.exs apps/samgita/test/samgita/github/http_fetch_functional_test.exs apps/samgita/test/samgita/workers/schedule_tick_worker_test.exs apps/samgita/test/samgita_test.exs apps/samgita/test/samgita/migration/styx_preservation_test.exs
mix test apps/samgita/test/samgita/schedules_test.exs:101 apps/samgita/test/samgita/schedules_test.exs:137 apps/samgita/test/samgita/schedules_test.exs:208 apps/samgita/test/samgita/events/delivery_test.exs:75 apps/samgita/test/samgita/events/delivery_test.exs:353
mix test apps/samgita_web/test/samgita_web/live/dashboard_live_test.exs
# From apps/samgita_protocol_websocket:
mix test test/wire_error_test.exs:39 test/socket_lifecycle_test.exs:67 test/socket_lifecycle_test.exs:85
```

Security/permission checks, broad suites and hosted workflows remain unrun under
the current restriction. Full Codex compatibility, A11, production cutover and
the blocked WebSocket replacement remain incomplete. Publication and deployment
are outside this qualification.
