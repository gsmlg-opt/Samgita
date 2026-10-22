# Capability and authority matrix

Native protocol schema version is `1.0`. Its capability catalog is defined by
`SamgitaProtocol.Capabilities`, not an implementation-name catalog. Negotiation
intersects supported groups and rejects missing required groups. Advertised and
operator-approved capabilities are separate from Project membership roles.

| Native group | Methods | Implemented platform use |
| --- | --- | --- |
| `project_events.v1` | `project/event.receive`, `project/event.status`, `project/event.report` | Outbound connector initializes and calls receive/status at a registered existing host. Responsible-Agent management reporting uses authenticated REST callbacks. |
| `sessions.v1` | `thread/start`, `thread/read`, `thread/resume`, `turn/start`, `turn/steer`, `turn/interrupt` | Reusable protocol and standalone fake; Samgita does not choose reasoning steps or start turns for delivered events. |
| `streaming.v1` | `stream/resume`, stream notifications with explicit processed cursors | Optional native client/host replay; not a management Task-state channel. |
| `approvals.v1` | Bidirectional `approval/request` | Caller/host decides the exact pending request; no automatic approval or Project role grant. |
| `cancellation.v1` | `request/cancel` | Cancellation intent; no proof that external execution/effects stopped. |

Initialization is built in. Hosts advertise only groups whose full request method
set their handler supports. Unsupported operations fail; no implementation-name
fallback chooses another Agent. Protocol replay buffers are bounded and may
return `replay_gap`; durable host inboxes/journals are the host's responsibility.

## Platform permissions

| Authority | Source | Does not confer |
| --- | --- | --- |
| Stable Agent identity | Operator registration | Project membership or execution ownership |
| Inbound machine authentication | Current enabled digest-backed credential | Operator API rights or a current connection by itself |
| Connection generation | Authenticated `/api/agent/connect` plus current binding | Capacity/Task claim, execution transfer or health |
| Project roles | Explicit enabled Project membership (`observer`, `worker`, `manager`, `reviewer`) | Additional protocol features or automatic Task acceptance |
| Execution ownership | Serialized claim, lease proof, current generation/fence/epoch | Permission to bypass legal Task transitions or unresolved-effect holds |
| Outbound destination | Exact operator-approved URL, pinned addresses and external credential reference | Arbitrary network access, redirects or URL-provided credentials |
| Transport ACK | Host receive/status response | Durable inbox commitment unless explicitly acknowledged as durable |
| Durable event acceptance | Host committed inbox | Processing completion or Task acceptance |
| Review/acceptance | Explicit current authorized management decisions | An Agent report/artifact/check automatically becoming accepted work |

An enabled responsible Agent must have an enabled manager membership and both
advertised and approved `project_events.v1`. Routing selection is explicit.
Synapsis, Sigma, Codex and any other names follow the same checks. Connection
status and recent activity are shown as evidence with health unverified; no
heartbeat or runtime readiness is inferred.

## Service and adapter evidence

| Consumer | Profile/evidence | Remaining boundary |
| --- | --- | --- |
| Standalone native fake | Core/optional WebSocket fixture contracts; in-memory fake explicitly started | No production durability, provider execution or actual-service proof |
| Platform qualification fake | Authenticated loopback native event host with persistent test journal and explicit management callbacks | Local deterministic qualification only; see acceptance ledger for exact runs |
| Sigma | Register existing service endpoint only after that exact service/version demonstrates its native advertised groups and authentication | No live Sigma conformance claim; do not start another Sigma process |
| Synapsis | Same native host/callback requirements as any registered Agent | No live Synapsis conformance claim or sibling repository changes |
| Codex adapter | Pinned official 0.163.0 selected thread/turn and notification field mapping | Source conformance only; no complete native capability group, project-event support or live Codex compatibility |

The Codex subset supports empty-parameter `thread/start`, `thread/read`,
`thread/resume`, text `turn/start`, `turn/steer`, `turn/interrupt`, and selected
turn/agent-message notifications. It does not translate native initialization,
capability negotiation, project events, approvals, request cancellation or stream
replay. Its native `command_id` is not sent upstream and creates no upstream
durable idempotency guarantee. Consult the
[adapter README](../../apps/samgita_protocol_codex/README.md) and
[Codex guide](integrations/codex.md) before claiming support.

The [P2](protocol-phase-2.md), [P3](domain-phase-3.md),
[P4 coordination](coordination-phase-4.md), [P4 GitHub](github-phase-4.md) and
[acceptance](acceptance.md) documents distinguish package, local platform and
actual-service/deployment evidence. None of this matrix authorizes live setup,
production migration, publication or deployment.
