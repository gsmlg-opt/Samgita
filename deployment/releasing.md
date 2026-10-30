# Manual release

The `Release` workflow in `.github/workflows/release.yml` builds and publishes:

| Artifact | Destination |
| --- | --- |
| `samgita_protocol` | Hex.pm |
| `samgita_protocol_websocket` | Hex.pm |
| `samgita_protocol_codex` | Hex.pm |
| `samgita_codex_driver` | Hex.pm |
| `samgita-VERSION.tar.gz` and the four Hex archives | GitHub Release `vVERSION` |
| Linux amd64 application image | `ghcr.io/gsmlg-dev/samgita:VERSION` and `:latest` |

All artifacts share the input `M.N.P` version without a `v` prefix. The initial
publication can reuse the checked-in version; later inputs must not decrease it.
The root `mix.exs` is canonical. Per the user's 2026-10-30 release policy, all 0.x
versions are experimental test releases and GitHub marks them as prereleases.
Hex.pm receives the numeric 0.x version; its semantic-version prerelease flag is
not implied by a zero major version, so each package README states the test
status explicitly. Versions at 1.0 or above use the stable channel.

The supported runtime minimum is Elixir 1.18 / OTP 28. Hosted builds and Docker
pin Elixir 1.19.7, OTP 28.5.0.8 and Bun 1.3.13. Devenv uses OTP 28 packages.
The container contains a compiled application release; it does not start a
second Sigma server or an embedded Codex process during the build.

## Prerequisites and gates

Configure these repository Actions secrets through the existing secret facility:

| Reference | Purpose |
| --- | --- |
| `HEX_API_KEY` | Publish all four packages on Hex.pm under an authorized owner; existing organization secret is available |
| `GHCR_USERNAME` | Optional explicit token-owner login; defaults to the dispatching `github.actor` |
| `GHCR_TOKEN` | Publish packages in the `gsmlg-dev` namespace; existing organization secret is available |

The source repository is `gsmlg-opt/Samgita`, while the image belongs to
`gsmlg-dev`. Its normal repository `GITHUB_TOKEN` cannot be assumed to grant
cross-organization registry access. A maintainer must supply the existing
publication credential references; this change creates no credentials or remote
permissions. The workflow's `GITHUB_TOKEN` reads Actions results and writes the
release commit, tag and GitHub Release.

Every release runs the reviewed release-helper functional tests, builds four Hex
archives, compiles all four extracted archives together in a temporary outside
consumer without starting applications, and builds the production application
and Docker image before publication. Any failure stops publication.

The pre-1.0 experimental channel is explicitly authorized despite the recorded
incomplete aggregate checks, full compatibility and A11 boundary. It does not run
or require mixed broad/security suites. Its GitHub release notes include
`deployment/experimental-release-notes.md`; none of those outstanding checks are
marked passing or removed from their evidence ledgers.

For a stable release at 1.0 or above, the exact source commit's latest runs of `CI`, `Tests` and `Pinned Codex
conformance` must all have completed successfully. The release then checks
`scripts/codex/inventory.py --check --require-verified` without changing its
requirements. The separate `deployment/release-blockers.json` gate retains A11:
the Codex inventory does not verify the platform telemetry boundary. Remove a
blocker only when its original acceptance evidence passes and is recorded for
review. The current complete-compatibility evidence and A11 boundary remain
incomplete; ordinary fake/native functional evidence cannot satisfy those gates.
Stable publication remains blocked until these gates are actually closed.

The user's current restriction prohibits security/permission tests, audits and
mixed broad suites or hosted runs containing them. Keep those definitions and
gates intact, but do not run `Tests` or `Pinned Codex conformance` under that
restriction. The manual Release workflow contains only the reviewed functional
and build checks and is authorized for the experimental publication.

## Run a qualified experimental release or a fully qualified stable release

From Actions, select `Release`, enter `version` (for example `0.1.1`), and use an
existing branch name for `git_ref` (default `main`). Tags and detached commits are
not release sources because the workflow commits the coordinated version bump
back to that branch. Do not start simultaneous releases: the required workflow
concurrency cancels an older run and registry publication is not transactional.

The workflow verifies the source branch and tag, checks source qualification,
synchronizes versions, and stages standalone package sources. It builds all four
Hex archives, the application tarball and the Docker image before publishing.
Docker uses the updated checkout as its context, so the input version reaches
the image. The source branch is checked again before the first publication and
before the final Git push. No database or service is started by the build.

`scripts/release.py` discovers every first-party `apps/*/mix.exs` and updates all
application versions, both root versions, versioned app asset manifests (including
`apps/samgita_web/package.json`) and the three internal package requirements
together. New top-level apps participate automatically; nested consumer examples
have independent versions. Git records all these manifests in the version commit.
The current six apps, four published Hex packages, application archive, release
tag and image version therefore share the requested release version. Source
checkouts retain local path dependencies. Fresh staging directories contain only
each package's listed library/config/schema files, README, formatter and license; their sibling
dependencies use Hex version requirements with the workspace path removed.
Pinned upstream schema notices remain included. Tests, platform configuration
and build caches are excluded. Published packages do not require the umbrella.

Package-only Hex publication runs in dependency order: core, WebSocket, Codex
wire layer, then driver. Each staged package resolves and compiles its real Hex
dependencies after the preceding package is published; unlike `hex.build`,
`hex.publish` requires dependency load paths. It does not invoke `mix docs`. The
image is pushed with the version and `latest` tags. The workflow then commits
version manifests when changed, pushes an annotated `vVERSION` tag and branch
atomically, and creates a
GitHub Release with generated notes and the five archives. For 0.x it also sets
`--prerelease` and attaches the explicit experimental limits. The release tag can
therefore identify a version-only commit after the qualified source commit; the
tag annotation and image revision label retain that source SHA. Application code
must not change between qualification and packaging.

## Partial failure and recovery

Hex.pm, GHCR and GitHub publication cannot commit atomically. A failure or
cancellation after publishing starts may leave some packages, tags or images
published without a completed GitHub Release. Download the saved workflow
artifacts, inspect each remote result and the source SHA, and reconcile the
specific failed step before deciding how to proceed. Do not blindly rerun the
whole workflow, overwrite an immutable package or force-move a release tag.
Prefer a new version for a new build; already published artifacts require
explicit operator reconciliation. `latest` is mutable and may have advanced
even if a later Git step failed. A source branch advancing during the build
also stops the final Git push and requires reconciliation.

To roll back a deployed application, use its separately authorized deployment
procedure and a previously qualified version image/archive. Do not delete
release history, unpublish packages, reset data or migrate production as part of
this workflow. Starting the Docker image runs the existing migration entrypoint;
building or publishing an image does not authorize starting it against a database.

## Local configuration verification

Permitted checks for this change are workflow lint, release-helper functional
tests, package builds and static compilation, plus a Docker build without
starting the image. They prove packaging only. They do not establish publication,
deployment, real provider integration, full compatibility or A11 completion.

Configuration qualification on 2026-10-30:

| Check | Result |
| --- | --- |
| Actionlint 1.7.12: CI, Tests, Release, Codex conformance definitions | Passed |
| Retained disabled CD definition | Existing lint diagnostic for intentional `if: false`; deployment stays disabled |
| Release-helper functional tests | 6 passed |
| Four staged `mix hex.build` archives | Passed; licenses, schema notices and Hex requirements preserved; Python caches excluded |
| Outside consumer compiling the four extracted archives | Passed on Elixir 1.18.5 / OTP 28.5.0.5 without platform configuration or Repo |
| Platform compile with warnings as errors, changed-manifest formatting, strict Credo, legacy source scan | Passed on Elixir 1.18.5 / OTP 28.5.0.5 |
| Assets using installed Bun 1.3.13 and Tailwind 4.3.1 | Passed after frozen dependency installation |
| Docker build and application tar assembly | Passed with Elixir 1.19.7 / OTP 28.5.0.8, Bun 1.3.13; host egress proxy supplied as Docker build arguments; image never started |
| `MIX_ENV=test mix dialyzer --force-check` on Elixir 1.18.5 / OTP 28.5.0.5 | Failed with 10 diagnostics in unchanged `legacy_mapping.ex`, `tasks.ex` and `test/support/codex_generation_runtime_fixture.ex`; includes opaque MapSet mismatches and Dialyxir formatting errors; no suppressions added |
| Broad/security/permission tests, audits, hosted runs, actual publication | Unrun under the current verification restriction |

The Docker build also reports three existing legacy `ENV key value` syntax
warnings. The failing Dialyzer check remains required in CI. This configuration
commit does not close that failure, the full compatibility gate or A11.

The version synchronization follow-up passes all eight release-helper functional
tests and Release workflow lint. A disposable `0.1.1` preparation synchronizes
the root, all six apps and the Web asset manifest; Bun 1.3.13 frozen installation
then succeeds with identical lockfile bytes. This is a local packaging fixture;
it creates no release tag or registry publication and does not close the gates
above.

The first experimental publication attempt (`41017715377`) passed all functional,
package, application and Docker builds but stopped after publishing only
`samgita_protocol 0.1.0`: the next staged package had not resolved dependencies
required by `hex.publish`. No other package, image or Git tag was published in
that attempt. The publication loop now resolves/compiles dependencies in order.
The coordinated retry uses `0.1.1`, preserving the already published core 0.1.0
as historical experimental output rather than overwriting or deleting it.
