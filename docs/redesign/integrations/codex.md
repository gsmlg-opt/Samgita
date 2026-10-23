# Codex integration and pinned runtime boundary

Codex is an ordinary Agent implementation label, with the same registration,
membership, capacity and acceptance rules as Sigma, Synapsis or another service.
There is no embedded Codex executor, auto-launched CLI or privileged Codex route.
Use an existing explicitly chosen host; this guide starts no process and changes
no external service or permission.

## Native wire, driver and retained convenience adapter

`apps/samgita_protocol_codex` contains a pure native schema/wire layer pinned to
official Codex **0.163.0**, commit
`83086188ae0614bd882818ff1aa23f3194962012`, plus the retained limited convenience
adapter. `apps/samgita_codex_driver` supplies explicitly started Sessions and
stdio, WebSocket and WebSocket-over-UDS transports, bidirectional correlation and
explicit interaction replies. Neither package requires Samgita's Repo, schemas,
Phoenix or configuration. Source/schema coverage and selected actual-binary
journeys are recorded separately from full compatibility in
[qualification](../../codex-app-server/qualification.md).

The following restrictions apply only to the convenience adapter, whose exact
mapping contract is in the
[adapter README](../../../apps/samgita_protocol_codex/README.md):

| Selected support | Unsupported boundary |
| --- | --- |
| Empty-parameter `thread/start`; `thread/read`, `thread/resume` | Native thread title/metadata fields are rejected |
| Text `turn/start`, `turn/steer`, `turn/interrupt` | Model/provider, working directory, sandbox and tool configuration stay with the existing host |
| `turn/started`, `turn/completed`, selected agent-message deltas | Complete item/tool traffic and arbitrary notifications |
| Codex initialize response plus explicit `initialized` notification | Translation of native initialization/capability negotiation |
| Caller-supplied native correlation/reference context | Upstream durable command idempotency, native `project_events.v1`, approval/cancellation/stream replay groups |

The adapter sends no native `command_id` upstream and automatically replays no
mutation. Thread/turn IDs cannot become Project/Task authorization. Interrupted
turn acknowledgement is intent, not proof that tools stopped. Errors are mapped
to safe codes without copying upstream secret-bearing messages or payloads.

## Direct host usage

Build/test the native wire and driver from their own directories. Follow the
[driver guide](../../../apps/samgita_codex_driver/README.md) and
[standalone example](../../../apps/samgita_codex_driver/examples/consumer/README.md)
for owned or borrowed transports, initialization, bounded events, explicit
approvals and uncertain-outcome recovery. A consumer can communicate directly
with its chosen Codex host while Samgita is stopped. Loading either package starts
no listener, provider, LLM or Samgita application. Callers using only the pure
convenience adapter still own its transport and request lifecycle.

Verify the actual official client/server version and selected handshake/methods
before claiming live compatibility. Source tests against pinned schemas do not
establish authentication, runtime execution or deployment conformance. Do not
advertise a complete native capability group merely because some mapped methods
belong to it.

## Registering a Codex-backed Agent

Register an identity in `/agents` and grant explicit Project membership if a
separately existing Agent service owns authenticated management callbacks. Supply
an independent inbound machine credential, stored only as a digest in Samgita.
Use `POST /api/agent/connect`, then Bearer plus current `x-agent-connection` on
versioned [management callbacks](../management-api.md). The callback service must
own its persistent execution journal and stable command identity.

The operator API accepts optional `runtime_driver: "codex"` and
`runtime_version: "0.163.0"`; those fields are inert and grant no membership.
After the normal Agent claim/start flow, bind the already started native Session
to its running Attempt and use the explicit journal APIs. Follow
[platform integration](../../codex-app-server/platform-integration.md) for
one-use dispatch, encrypted native payloads, current authority checks, protected
reads, additive migration and recovery. Do not confuse the native runtime binding
with a project-event host or infer Task acceptance from a completed turn.

Do not configure Samgita's native event connector directly against an official
Codex endpoint: this adapter does not implement native `project_events.v1`.
Responsible-Agent routing requires an existing authenticated native host boundary
with the full receive/status/report and durable inbox contract. If that boundary
does not exist, leave event delivery unconfigured and record the gap; implementing
or provisioning it requires separately authorized work. Never fabricate support
by setting the capability approval checkbox.

For a separately qualified native host, its exact `/app-server` URL, pinned
destination addresses and versioned outbound service credential reference follow
the same runtime approval rules as the [Sigma](sigma.md) and
[Synapsis](synapsis.md) guides. Native event identity/acceptance and Codex thread/
turn identity are separate. The host must not auto-replay uncertain turns after
delivery retries or reconnect.

## Management outcome and qualification

Explicit authenticated management callbacks perform claim/start/progress/report
and fenced recovery. Effect resolution is separate former-owner reconciliation
with the former proof and explicit evidence. A turn completion or artifact is
evidence; a successful Attempt report with `effects_resolved: true` submits
`awaiting_review`. Unresolved effects leave the Task `blocked` with an execution
hold. Explicit review plus separate acceptance produces `accepted`. The Agent's
reasoning/delegation policy stays outside Samgita. Holds remain until authorized
evidence-based resolution.

The [capability matrix](../capability-matrix.md), [P2](../protocol-phase-2.md),
[P3](../domain-phase-3.md), [P4 coordination](../coordination-phase-4.md),
[P4 GitHub](../github-phase-4.md) and [acceptance ledger](../acceptance.md) separate
package, deterministic fake, actual local Codex executable, real-service and
deployment evidence. Local deterministic model fixtures are not real account or
backend acceptance. Complete compatibility, published packages and production
integration remain unclaimed.
