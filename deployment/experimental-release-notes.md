This pre-1.0 release is experimental and intended for testing. All first-party
apps, the four reusable Hex packages, the application archive and the Docker image
share one release version. Package versions are independent of the Codex
app-server release and of the neutral wire schema version.

The release builds every archive, compiles the extracted Hex packages in an
outside consumer, runs the reviewed release-helper functional tests, and builds
the application and container before publication. Those checks start no
database or service.

Known limits remain open:

- Codex is not pinned. The Codex adapter follows the latest Codex release through
  a refreshed schema snapshot, so there is no full-compatibility target. The
  retired `rust-v0.163.0` compatibility records are historical evidence only.
  Live Codex, Sigma and Synapsis conformance is not established.
- GitHub is a future TODO. Existing GitHub ingestion is unchanged; no new GitHub
  features, release observation or App permission changes are included. A real
  GitHub App has not been provisioned, and GitHub writes stay disabled.
- A11, the confidentiality of the platform's raw telemetry, is unresolved. The
  last minimum runtime Dialyzer check reported ten diagnostics. This prerelease
  does not claim aggregate acceptance passes.
- Security and permission tests, audits and mixed broad suites have not been
  run, because of the current verification restriction. Deployment inventory,
  exclusion of legacy writers, a full memory and backup rehearsal, and
  production cutover remain open. This release does not establish production
  readiness, a production migration or a deployment.

The complete evidence ledger and the open blockers remain in the source
repository under `docs/redesign/` and `docs/codex-app-server/`. Stable releases
(1.0 and above) keep the full publication gates.
