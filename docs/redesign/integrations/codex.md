# Codex integration and pinned adapter boundary

Codex is an ordinary Agent implementation label, with the same registration,
membership, capacity and acceptance rules as Sigma, Synapsis or another service.
There is no embedded Codex executor, auto-launched CLI or privileged Codex route.
Use an existing explicitly chosen host; this guide starts no process and changes
no external service or permission.

## What the adapter establishes

`apps/samgita_protocol_codex` is an optional pure adapter pinned to official Codex
**0.163.0**, commit `83086188ae0614bd882818ff1aa23f3194962012`. Vendored source
hashes/license provenance and selected field mappings are checked by package
tests. This is source conformance for a subset, not live or full compatibility.
The [adapter README](../../../apps/samgita_protocol_codex/README.md) is the exact
mapping contract.

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

Build and test the adapter from its own directory. The caller owns transport,
authentication, one initialize sequence per connection, pending request context,
notification routing, timeout/disconnect uncertainty and reconciliation. It can
communicate directly with its chosen Codex host while Samgita is stopped.
Loading the adapter starts no listener, provider, LLM or Samgita application.

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
package, deterministic fake, real-service and deployment evidence. No live Codex
generation, complete compatibility, published package or production integration
is claimed by this guide.
