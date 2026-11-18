# Synapsis integration setup boundary

Synapsis follows the same membership, capacity and execution rules as any Agent.
It may initiate an inbound WebSocket to Samgita, or expose its existing endpoint
for Samgita's outbound connector. The operator chooses the connection direction.
Samgita's local fake tests do not prove actual Synapsis conformance. Record the
real client's exact version; this change does not edit the sibling repository,
launch another service or install a new runtime host.

## Synapsis initiates the connection

This mode is intended for the operator's internal network. There is no credential
to copy into Synapsis before connecting. The client creates a random 32-byte
device token, encodes it as base64url and stores it locally before its first
connection. Keep using that token across reconnects and client restarts. Samgita
stores only its digest after the operator confirms the device.

Open a WebSocket at Samgita's `/app-server` (use `wss://` for the deployed HTTPS
endpoint). Send this bootstrap text frame before native protocol messages:

```json
{
  "type": "agent/connect",
  "name": "Synapsis on my workstation",
  "implementation": "synapsis",
  "device_token": "<automatically generated device token>"
}
```

A new device receives:

```json
{"type":"agent/pending","request_id":"<request UUID>"}
```

In Samgita's `/agents`, review the device name, implementation label and request
ID under **Connection requests**. Confirm it as a new Agent, or select an
existing enabled Agent without a Codex host/runtime from the current page to
retain its identity and Project memberships. Rejecting a request closes that
pending connection. The
displayed name and implementation are client-supplied descriptions, not identity
proof or Project authority.

Confirmation stores the device credential digest in `agent_credentials`, with
reference `device:<request UUID>`, and sets the Agent's endpoint transport to
`inbound_websocket`. Binding an existing Agent changes its delivery target:
reconfigure its Project event subscriptions before delivering to the new target.
Converting an Agent with active or unresolved execution from outbound to inbound
is refused. Confirmation grants no Project roles and launches no Task.

After confirmation, or when a remembered device reconnects, the socket receives:

```json
{"type":"agent/connected","connection":{"id":"<connection UUID>","agent_id":"<Agent UUID>","generation":1}}
```

The `connection` object is the normal management connection projection and also
includes its expiry. The client then sends native `connection/initialize` using
schema/version `1.0`, advertising and requiring `project_events.v1`. After
negotiation, Samgita sends `project/event.receive` and `project/event.status`
requests over this same socket; the client handles them and returns correlated
native responses. The client must implement the complete durable event contract,
not merely receive frames. Existing `SamgitaProtocolWebSocket.Client` consumers
need the bootstrap exchange before starting native initialization; a successful
legacy REST connect alone does not attach an inbound event socket.

Use WebSocket ping frames to keep an idle connection alive, and reconnect with
backoff after network loss. Presenting the saved device token restores the
trusted device automatically and creates a new connection generation. A reconnect
does not re-execute a Task, transfer an Attempt or resolve an uncertain remote
effect. Reconcile existing operations and explicitly rebind an eligible Attempt.

Starting with Samgita 0.4.5, the inbound socket uses these close codes:

| Code | Meaning | Client action |
| --- | --- | --- |
| `1012` | Samgita's ingress process stopped or restarted. | Reconnect with backoff and the saved token. |
| `1013` | The socket can be retried, for example after a connection expires, the operator disconnects it, a pending request expires, or event delivery times out. | Reconnect with backoff and the same token. If delivery is uncertain, reconcile by operation status. |
| `4001` | A newer socket or connection generation superseded this one. | Stop the old socket's retry loop so it cannot displace its replacement. Keep the token. |
| `1008` | The device or connection was rejected by policy, for example on explicit rejection, revoked credentials or invalid bootstrap. | Stop automatic reconnect and surface the failure to the operator. |

For 0.4.4, close code `1008` is ambiguous. These codes describe the
connection lifecycle and never resolve an outstanding event or Task operation.

REST calls use `Authorization: Bearer <device token>` and
`x-agent-connection: <current connection UUID>` from the socket response. Do not
call REST `/connect` again for the same live socket: creating another generation
replaces the socket's management connection. No outbound Synapsis URL,
`SAMGITA_EVENT_DESTINATIONS` entry or `SAMGITA_EVENT_CREDENTIALS` entry is needed
for inbound delivery. Database-external lease keys are still required for
execution callbacks.

The Agent list displays the live inbound connection separately from recorded
activity. **Disconnect** closes the current socket but allows the remembered
device to reconnect. To forget a device, open its Agent's **Credentials** section
and revoke the `device:` credential. Disabled or removed Agents and revoked
credentials cannot restore an authenticated connection. Never place a device
token in URLs, logs, command receipts, event payloads or browser forms.

## Samgita initiates the connection

The existing outbound setup remains available. The following endpoint,
destination approval and external service-credential settings apply only to that
mode.

### Establish actual service conformance

Determine the existing approved `wss://<approved-host>/app-server` endpoint and
its machine authentication. Require authenticated upgrade/dispatch and native
`connection/initialize` schema `1.0`. For event delivery, the host must implement
the complete `project_events.v1` receive/status/report contract. An existing chat,
SSE, provider or Codex-compatible API does not imply this profile.

Test stable event/operation identity, committed inbox versus transport receipt,
duplicate/conflicting-content behavior, lost replies, explicit status queries
and host restart persistence. Enable a routing idempotency guarantee only after
the host's durable contract is reviewed. Additional native groups need their own
complete method and authentication tests. Unsupported methods fail explicitly;
they do not fall back to another runtime or confer permission.

If the existing endpoint lacks the required profile or current authentication,
record the integration as blocked/unverified. Implementing a native host boundary
belongs to a separately authorized service change. Do not create a second server
inside Samgita to claim Synapsis support.

### Operator registration and Project setup

1. In `/agents`, register the stable identity, a descriptive Synapsis label,
   capacity and tested native advertised/approved groups. The protocol/version
   are `samgita`/`1.0`; endpoint transport is `websocket`.
2. Set the exact verified endpoint and a versioned external outbound reference
   such as `synapsis-service-v1`. This field contains a reference name, not the
   service credential value.
3. Register a separate operator-supplied inbound machine credential and provision
   it securely in the existing Synapsis service. Only its digest/metadata remain
   in Samgita; no credential is issued back to the browser. Reconcile metadata
   after interrupted submission before re-entering a credential.
4. Create/select a Project without requiring a PRD/repository/provider. Bind the
   Agent and grant explicit roles. Configure responsible-Agent routing only with
   an enabled manager membership and advertised/approved `project_events.v1`.

Membership roles, protocol capabilities and machine connection generations are
separate authorities. Disablement fences future authorized work while preserving
history. Connection status and recent activity remain unverified health evidence.

### Runtime destination and callback configuration

The runtime operator separately provisions approved exact URL/address and secret
reference resolution in Samgita. These are illustrative placeholders:

```text
SAMGITA_EVENT_DESTINATIONS
  {"<agent_uuid>":{"url":"wss://<approved-synapsis-host>/app-server","addresses":["<approved-ip>"]}}
SAMGITA_EVENT_CREDENTIALS
  {"synapsis-service-v1":"<value supplied by external secret management>"}
```

Every resolved DNS address must remain in the approved set. The client pins its
connection and rejects redirects, URL credentials and remote plaintext. UI
endpoint registration alone does not enable egress. Outbound service credentials,
inbound callback credentials and database-external lease keys are distinct.

Synapsis uses `POST /api/agent/connect` with its inbound Bearer credential, then
sends the returned current connection UUID in `x-agent-connection` on callbacks.

## Project work and verification limits

For either connection direction, read Project context and use the
[management API](../management-api.md) for stable
commands, versions, sessions, claims, owner proof reads, start/progress/report,
and rebind. Effect resolution is separate former-owner reconciliation with the
former proof and explicit evidence. No native event or thread result directly
changes authoritative Task state. Synapsis owns its reasoning and delegation policy.

A successful Attempt report with `effects_resolved: true` means
`awaiting_review`; unresolved effects leave the Task `blocked` with an execution
hold. Explicit current review and a separate acceptance decision are required
for `accepted`. Timeout/reconnect/reopen cannot clear execution uncertainty;
retain the durable local execution journal and
reconcile existing operations instead of launching them again.

Record actual-service authentication, advertised groups, durable inbox/journal,
restart/lost-ACK and callback evidence separately from fake qualification. Consult
the [matrix](../capability-matrix.md), [P3](../domain-phase-3.md),
[P4 coordination](../coordination-phase-4.md), [P4 GitHub](../github-phase-4.md)
and [acceptance ledger](../acceptance.md). This guide does not authorize live
credential provisioning, permission changes or deployment. The current repository
restriction leaves credential, authentication, authorization and confirmation
tests unrun; functional checks do not qualify those gates. Actual Synapsis
bootstrap support and real bidirectional integration must be verified separately.

Local functional verification (2026-11-18): the focused inbound delivery and
LiveView checks passed six tests, including real-WebSocket event delivery,
status, lost replies and timeout reconciliation using pre-trusted synthetic
fixtures. Compilation with warnings as errors passed. Assets built on Ubuntu
26.04 with the supported native bundler runtime. Read-only desktop and mobile
browser checks covered the request empty state and inbound configuration;
confirmation, rejection, revocation and authenticated restoration were not
exercised under the test restriction above. No actual Synapsis client or deployed
service was qualified.
