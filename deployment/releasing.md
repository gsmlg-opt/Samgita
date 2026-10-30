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

All artifacts share the input version. Stable `M.N.P` versions without a `v`
prefix are supported. The initial publication can reuse the checked-in version;
later inputs must not decrease it. The root `mix.exs` is canonical.

The supported runtime minimum is Elixir 1.18 / OTP 28. Hosted builds and Docker
pin Elixir 1.19.7, OTP 28.5.0.8 and Bun 1.3.13. Devenv uses OTP 28 packages.
The container contains a compiled application release; it does not start a
second Sigma server or an embedded Codex process during the build.

## Prerequisites and gates

Configure these repository Actions secrets through the existing secret facility:

| Reference | Purpose |
| --- | --- |
| `HEX_API_KEY` | Publish all four packages on Hex.pm under an authorized owner |
| `GHCR_USERNAME` | Owner of the GHCR publication token |
| `GHCR_TOKEN` | Publish packages in the `gsmlg-dev` namespace |

The source repository is `gsmlg-opt/Samgita`, while the image belongs to
`gsmlg-dev`. Its normal repository `GITHUB_TOKEN` cannot be assumed to grant
cross-organization registry access. A maintainer must supply the existing
publication credential references; this change creates no credentials or remote
permissions. The workflow's `GITHUB_TOKEN` reads Actions results and writes the
release commit, tag and GitHub Release.

For the exact source commit, the latest runs of `CI`, `Tests` and `Pinned Codex
conformance` must all have completed successfully. The release then checks
`scripts/codex/inventory.py --check --require-verified` without changing its
requirements. The separate `deployment/release-blockers.json` gate retains A11:
the Codex inventory does not verify the platform telemetry boundary. Remove a
blocker only when its original acceptance evidence passes and is recorded for
review. The current complete-compatibility evidence and A11 boundary remain
incomplete; ordinary fake/native functional evidence cannot satisfy those gates.
Publication remains blocked until the applicable gates are actually closed.

The user's current restriction prohibits security/permission tests, audits and
mixed broad suites or hosted runs containing them. Keep those definitions and
gates intact, but do not run `Tests`, `Pinned Codex conformance` or release under
that restriction. No hosted workflow was dispatched for this configuration task.

## Run after qualification is authorized and complete

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

`scripts/release.py` updates both root versions, all six application versions and
the three internal package requirements together. Source checkouts retain local
path dependencies. Fresh staging directories contain only each package's listed
library/config/schema files, README, formatter and license; their sibling
dependencies use Hex version requirements with the workspace path removed.
Pinned upstream schema notices remain included. Tests, platform configuration
and build caches are excluded. Published packages do not require the umbrella.

Package-only Hex publication runs in dependency order: core, WebSocket, Codex
wire layer, then driver. It does not invoke `mix docs`. The image is pushed with
the version and `latest` tags. The workflow then commits version manifests when
changed, pushes an annotated `vVERSION` tag and branch atomically, and creates a
GitHub Release with generated notes and the five archives. The release tag can
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
