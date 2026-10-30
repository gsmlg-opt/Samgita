This pre-1.0 release is experimental and intended for testing. All first-party
apps, four reusable Hex packages, the application archive and Docker image use
the same release version. Package versions are independent of the pinned Codex
app-server version and the neutral wire schema version.

The release builds every archive, compiles the extracted Hex packages in an
outside consumer, runs the reviewed release-helper functional tests, and builds
the application and container before publication. No database or service is
started by those checks.

Known limits remain open:

- Full Codex `rust-v0.163.0` behavioral compatibility and real Sigma/Synapsis
  integration are incomplete. Ordinary functional evidence and schema coverage
  do not establish complete compatibility.
- A11 platform raw telemetry confidentiality is unresolved. The prior minimum
  runtime Dialyzer check reported ten diagnostics. Aggregate acceptance is not
  represented as passing by this prerelease.
- Security/permission tests, audits and mixed broad suites are unrun under the
  current verification restriction. Publication does not establish production
  readiness, a production migration or deployment.

The complete evidence ledger and blockers remain in the source repository under
`docs/redesign/` and `docs/codex-app-server/`. Stable releases at 1.0 or above
retain the full publication gates.
