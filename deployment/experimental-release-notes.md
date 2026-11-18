This pre-1.0 release is experimental and intended for testing. All first-party
apps, the four reusable Hex packages, the application archive and the Docker image
share one release version. Package versions are independent of the Codex
app-server release and of the neutral wire schema version.

Samgita 0.4.5 distinguishes recoverable inbound WebSocket closure from device
rejection. A client can reconnect with its saved token after an ingress restart
(`1012`) or connection expiry (`1013`). A superseded socket receives `4001`
so it can stop retrying while the newer connection stays active. Policy
rejection retains `1008`. See `docs/redesign/integrations/synapsis.md` for the
client contract. Reconnect leaves any uncertain event delivery to status
reconciliation. The focused loopback checks exercised restart, expiration,
replacement and event timeout over a real WebSocket.

Agent-initiated WebSockets at `/app-server` were introduced in 0.4.4. A new device
waits for operator confirmation in Samgita, then uses its automatically saved
token to restore the same Agent identity after reconnect or restart. Samgita
stores only the digest. Native event delivery and status queries share that
socket; reconnect does not replay execution or transfer an Attempt. Each Agent
uses its own connection. Actual Synapsis client adaptation remains separate.

The reusable protocol includes optional `sessions.list.v1` with read-only
`thread/list`, pagination and metadata filtering. Existing `sessions.v1` hosts
retain their method set. The WebSocket client adds configurable Ping keepalive
(20 seconds by default), owner disconnect notifications, and bounded cleanup
that acknowledges queued deliveries before confirming transport termination.

The 0.4.4 reviewed functional checks passed for thread listing, lifecycle,
fragmented control traffic, ordinary outbound event delivery and the inbound
delivery/read-only UI. The generated schema and outside-consumer checks passed.
Device confirmation, authentication, authorization and approval tests remain
unrun under the verification restriction; those gates are not qualified.

The runtime image retains the OpenSSH client. Deployments provide SSH
configuration, identity and known-hosts records externally; credentials are not
bundled in the image. The local transport still sees the container filesystem.

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
