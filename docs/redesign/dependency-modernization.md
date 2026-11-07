# Dependency modernization

Date: 2026-11-05. The user approved documentation and code migration on the
existing branch. This changes infrastructure libraries, not domain ownership,
Agent authority, Task acceptance or external execution policy. Implementation
and verification results are recorded below separately from the target.

The user's 2026-11-08 clarification requires complete removal of Oban and
Bandit, including test/release dependencies and migration compatibility code.
The current contract below supersedes the retention choices in the historical
2026-11-05 and 2026-11-07 result sections. Those results remain tied to their
original source/dependency revisions.

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
Bandit is absent from production, test and release dependencies. Remove its
old raw-HTTP telemetry test with the retired server behavior; preserve the
historical result in documentation/Git. This removal does not close the
recorded A11 telemetry boundary or qualify Gaoxy/LiveView telemetry safety.

## Durable jobs and preservation

Styx uses `styx_jobs` storage installed by its additive migration and is the
sole durable job framework. Remove Oban from manifests, lockfiles, release
configuration and fixtures/test helpers. Remove
`20260129100006_setup_oban.exs` and `20260907000000_create_oban.exs` from the
active migration directory; do not add compatibility modules, substitute
migrations or an `oban: :load` release entry. Their original sources and P3
hash evidence remain historical records, not active migration requirements.

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

Old `oban_jobs` rows are neither copied, renamed, replayed, pruned nor deleted
by this code change. Platform job admission/status reads `styx_jobs` only;
it does not inspect or classify a legacy Oban store. Its status cannot certify
the absence of old deployment jobs or external effects. New legacy hook
notifications enter the disabled Styx `legacy_webhooks` queue and propagate
enqueue errors; no historical executor returns. Job IDs are scoped to their
storage table and are not translated between engines.

Before any real cutover, inventory and stop old producers/consumers, reconcile
executing effects and establish a single runtime owner. A code change is not
proof of a drained deployment. A rollback switches binaries and disables the
new consumers; existing database objects remain and any old-consumer resumption
requires separate reconciliation and authorization. Removing migration sources
does not provide a rollback binary or certify an old schema. The Styx additive
migration's down operation retains history.
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
durable insertion/deduplication, worker scheduling and existing database history with
an explicitly named `samgita_redesign_*_test` database. Compile the umbrella and
standalone packages, build assets and check the final diff. Preserve existing
tests when adapting engine types. Security/permission tests, audits, mixed broad
suites and automatic hosted workflows remain prohibited. Their gates are
unrun/incomplete, not waived. Full Codex compatibility, A11 and production
cutover retain their existing separate boundaries.

## Historical result — 2026-11-05

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

## Historical version refresh and WebSocket migration — 2026-11-07

At this revision the requested version refresh used the following resolved versions. The root,
standalone WebSocket, standalone driver and driver example consumer lockfiles
are updated together, without adding umbrella/config inheritance.

| Component | Resolved version / role |
| --- | --- |
| DuskmoonBundler, runtime and native build cohort | 10.1.2 |
| phoenix_duskmoon | 10.1.0, per the user's subsequent upgrade clarification |
| Gaoxy, gaoxy_http and gaoxy_websock_adapter | 0.15.1 |
| http_fetch, http_web_socket and HTTP runtime/core cohort | 1.0.0-rc.5 |
| Styx | 0.1.1, latest; sole durable job runtime |
| Oban | 2.24.2, non-runtime historical migrations only |
| Bandit | 1.14.1, test-only historical telemetry evidence |
| Mint / mint_web_socket | test-only independent protocol raw-wire oracle |
| DuskMoon Core npm CSS | 1.21.0 |

Other upgrades include Phoenix 1.8.16, LiveView 1.2.13, phoenix_html 4.4.0,
PubSub 2.4.1, Ecto 3.14.3, mdex 0.14.6, mdex_mermaid 0.4.0, lazy_html 0.1.14
and Dialyxir 1.4.8. `mix hex.outdated --all` was checked in the root and both
standalone transport packages. The driver has no outdated dependencies. The
root and optional server retain Abyss/Hell 1.0.0-rc.4 because Gaoxy 0.15.1 pins
them exactly; rc.5 is available. The refresh is tracked by
[Gaoxy #22](https://github.com/gsmlg-dev/gaoxy/issues/22), severity `needed`,
with dependency-site TODOs and no forced overrides. The user subsequently
confirmed adopting phoenix_duskmoon 10.1.0, removing the 10.0-series constraint.
Only Abyss/Hell remain outdated in the root.

Published http_web_socket 1.0.0-rc.5 provides the APIs previously missing in
[http_fetch #152](https://github.com/gsmlg-dev/http_fetch/issues/152). Both
production clients now use `HTTP.WebSocket`: protocol delivery and Codex
WebSocket/Unix WebSocket. No production Mint client remains. Existing validation
and transport options retain destination pinning/hostname identity, bounded
upgrade metadata and Retry-After, independent frame/message/read limits and
negotiated peer frame limits. Pin/TLS/authentication/security runtime checks
were not run; their preservation has source review only in this refresh.

Writes use `send_ack`; message delivery uses ACK mode. Explicit close uses a
100 ms handshake timeout and awaits `HTTP.ClientCompletion` for up to one second.
Unconfirmed cleanup raises an explicit failure rather than allowing reconnect;
owned client cleanup never stops the borrowed server. Driver metadata now
correctly identifies the owned client process. The missing-path URL still
requests `/app-server`. Ordinary GitHub HTTP changes the removed `:ssl` backend
option to the RC's `:ex_ssl`, retaining the existing bounded completion barrier.

Two observable wire differences follow the RC transport: the standard Close
handshake echoes the peer's code and reason (returned metadata still omits the
reason), and a frame exceeding both message and frame limits reports the message
limit first. Separate frame-only, fragmented-message and read limits remain
covered. Existing negative tests remain; no authentication/pin test was split or
renamed to bypass the verification restriction.

PhoenixDuskmoon 10 renders the locally used `dm_card` as native Core HTML.
All local `dm_btn` uses already opt into native rendering. Remove the unused
`el-card` registration/package and align Core CSS to 1.21.0; keep ThemeSwitcher,
existing UI structure, Tailwind semantics and component scanning.

The initial refresh (phoenix_duskmoon 10.0.12) passed **46 distinct functional cases**:

- The prior eleven Styx/HTTP/worker/status/history cases, five selected
  schedule/delivery cases and three dashboard cases: 19 cases.
- Standalone protocol client controls: 9 cases, plus six selected
  initialization/event/replay and wire/lifecycle cases: 15 cases.
- Driver WebSocket/Unix transport: 12 selected cases, excluding the five mixed
  authentication/pin/TLS/security cases. The explicit close case also verifies
  missing-path fallback and confirmed completion with a borrowed peer alive.

The root selection remains the first three commands in the historical
reproduction block above. Run these additional standalone selections from their
respective package directories, keeping file-only and line selections separate:

```sh
# apps/samgita_protocol_websocket
mix test test/client_control_frames_test.exs
mix test test/wire_error_test.exs:39 test/socket_lifecycle_test.exs:67 test/socket_lifecycle_test.exs:85 test/integration_test.exs:22 test/integration_test.exs:253 test/integration_test.exs:270
# apps/samgita_codex_driver
mix test test/transport_web_socket_test.exs:59 test/transport_web_socket_test.exs:75 test/transport_web_socket_test.exs:103 test/transport_web_socket_test.exs:128 test/transport_web_socket_test.exs:155 test/transport_web_socket_test.exs:172 test/transport_web_socket_test.exs:188 test/transport_web_socket_test.exs:204 test/transport_web_socket_test.exs:220 test/transport_web_socket_test.exs:239 test/transport_web_socket_test.exs:264 test/transport_web_socket_test.exs:294
```

Root, standalone driver and standalone WebSocket warnings-as-errors compilation,
driver example consumer compilation, changed-Elixir formatting, diff whitespace
and isolated frozen npm installation passed. Historical migration sources and
existing unrelated untracked files remain unchanged.

The initial refresh's Ubuntu 26.04/glibc 2.43 Docker build completed frozen npm
installation, `mix assets.deploy`, compilation, release assembly and runtime
image creation. A temporary Dockerfile added only a COPY of
six official, checksum-validated native artifact cache archives before dependency
compilation; repository Docker/build configuration is unchanged. The initial
uncached build was stopped after slow native downloads and is not counted as a
pass. The successful build emitted `app-f3100aa9.css` and `app-60361122.js`.
Release inspection confirmed Bandit/Mint/build-only tooling absent, Oban
`load`, and Gaoxy, Styx and http_web_socket present. Docker reported three
existing legacy ENV syntax warnings; the core app's absent static directory is
informational, while web asset digestion succeeded. The glibc 2.42 host still
cannot run the Vize compiler; host watcher qualification remains incomplete.

Browser checks used the emitted assets on an owned isolated Gaoxy endpoint at
`127.0.0.1:39157`, with the scratch database
`samgita_redesign_dependency_upgrade_test`. `/`, `/projects` and `/agents` loaded
the hashed JS/CSS with HTTP 200 and connected LiveSocket. Native `ARTICLE.card`
rendering had Core flex layout, an 8 px radius and applied theme colors; selecting
moonlight changed computed colors and persisted through navigation. No browser
console errors or warnings were reported. This was a read/navigation/theme
smoke check, not a new full management journey or real Agent integration.

These results do not
establish full native compatibility, A11, production cutover or security gates.
Security/permission checks, audits, mixed broad suites and hosted workflows
remain unrun. No release, deployment or real external integration was performed.

### PhoenixDuskmoon 10.1.0 follow-up

The user clarified that phoenix_duskmoon must also reach the latest release.
Its manifest now requires `~> 10.1.0`; the Hex lock resolves 10.1.0 and the
workspace Core CSS manifest/lock resolve 1.21.0 to match the published package.
The published Elixir component diff adds React Chat composer behavior, which
Samgita does not use; ordinary local components and ThemeSwitcher are unchanged.
No unused React, composer or optional Lexical dependencies were added.

Fresh checks on this follow-up passed warnings-as-errors compilation, the three
Dashboard functional tests, changed-manifest formatting, diff whitespace and
isolated frozen npm installation. `mix hex.outdated phoenix_duskmoon` reports
10.1.0 up to date; `--all` reports only the existing Abyss/Hell constraint.
The earlier 46-case result above belongs to the initial refresh, not a rerun of
that entire selection after this UI upgrade.

The supported Ubuntu 26.04 Docker build repeated assets, compilation, release
assembly and runtime image creation using eight official native archive caches
in a temporary build input; repository build configuration is unchanged.
It emitted `app-35b24d72.css` and the unchanged `app-60361122.js`. Browser checks
at the owned endpoint `127.0.0.1:39158`, backed by isolated database
`samgita_redesign_ui101_test`, verified `/`, `/projects` and `/agents`, hashed
asset HTTP 200 responses, connected LiveSocket, native card layout and persisted
moonlight theme changes. No browser console errors/warnings were reported.
The existing Docker ENV syntax warnings and host glibc limitation remain.
Security/permission checks and broad suites remain unrun; no commit, push,
publication or deployment was performed for this follow-up.

## Complete Oban/Bandit removal — 2026-11-08

The user explicitly rejected retaining either library for compatibility.
The current architecture therefore has no Oban/Bandit dependency in production,
test or release; no Oban migration shim; no active Oban migration source; and
no retained Bandit raw-HTTP test. Platform inventories only Styx jobs. Existing
database history is not deleted or migrated by these source changes. No
production migration or deployment is authorized.

The final removal must be qualified separately from every result above:

- Check all root, standalone and consumer manifests/locks and assembled release
  applications for absence of Oban/Bandit; compile with warnings as errors.
- Rehearse fresh creation and populated-history up/down/up behavior in an owned
  scratch database without Oban modules, preserving existing rows/references.
  Record the two intentionally removed migration sources explicitly in source
  provenance expectations; do not silently accept unrelated hash changes.
- Verify Styx insertion/deduplication, transactional enqueue rollback,
  disabled legacy queues and Styx-only Platform status/admission. A status with
  no pending Styx jobs is not evidence of a drained legacy deployment.
- Run only reviewed functional selections, affected dashboard checks and
  supported-builder asset/release checks. Preserve prohibited checks as unrun.

Final removal verification passed:

- Warnings-as-errors compilation, changed Elixir formatting and diff whitespace
  checks. Stale local Phoenix/WebSockAdapter optional-dependency build metadata
  initially referenced Bandit; forcing those dependencies to recompile cleared
  the cache and the subsequent compilation/tests passed without source changes.
- 18 reviewed functional cases (15 core and 3 Dashboard) in an owned PostgreSQL
  cluster on socket `/tmp/samgita-remove-deps-O5M5jjvp`, port 55449, database
  `samgita_redesign_remove_dependencies_test`. The selection covered Styx
  transactional rollback/deduplication and quarantined-job inventory, the four
  migration preservation files, schedule wakeups, HTTP fetching, the core smoke
  check and Dashboard. Fresh creation produced `styx_jobs` and zero `oban_%`
  tables; populated-history and Styx down/up checks preserved their stored rows.
  The remaining source-provenance manifest checks all 20 pinned entries.
- Production/test dependency trees and all root, standalone and consumer
  manifests/locks contain no resolved Oban/Bandit package. Upstream optional
  Bandit declarations in Hex package metadata do not resolve or install it.
  Root fetched sources and build artifacts for Oban/Bandit and their now-unused
  HPAX/ThousandIsland dependencies were removed.
- The Ubuntu 26.04/glibc 2.43 Docker build completed frozen npm installation,
  `mix assets.deploy`, compilation, release assembly and runtime image creation
  (`sha256:3014d2346fbae06fad9395a50a7244d08933826be7ea2df93d00b308c78a2c0c`).
  Inspection of all 67 release applications and library directories confirmed
  Oban/Bandit/build-only tools absent, with Styx 0.1.1, Gaoxy/Gaoxy HTTP 0.15.1
  and http_fetch/http_web_socket 1.0.0-rc.8 present. Assets remained
  `app-35b24d72.css` and `app-60361122.js`.

Two initial Docker attempts stopped on Hex download timeouts. The successful
temporary Dockerfile supplied 76 public, lock-matching Hex archives, the public
Heroicons checkout and eight checksum-validated native archives as cache inputs;
repository Docker configuration and dependency sources were unchanged. The
three existing Docker ENV syntax warnings remain. Host asset compilation is
still limited by glibc 2.42.

The final root `mix hex.outdated --all` reports phoenix_duskmoon 10.1.0,
DuskmoonBundler 10.1.2, Gaoxy HTTP 0.15.1 and http_fetch 1.0.0-rc.8 up to date.
Only Gaoxy's pinned Abyss/Hell 1.0.0-rc.4 remain behind rc.8, tracked by
[gaoxy#22](https://github.com/gsmlg-dev/gaoxy/issues/22). The standalone WebSocket
and driver locks retain their earlier rc.5 qualification; this removal did not
refresh those lockfiles again.

Earlier counts, browser checks and release inspections remain historical,
including the former release's Oban `load` entry. Browser checks were not
repeated for this removal. Security/permission/activation checks, audits, mixed
broad suites and hosted workflows remain unrun. A11 remains unverified;
deleting its old Bandit test does not resolve the telemetry boundary. No commit,
push, publication, production migration or deployment was performed for this
removal.
