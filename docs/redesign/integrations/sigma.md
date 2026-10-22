# Sigma integration setup boundary

Sigma is an ordinary registered Agent. Its name and implementation label grant
no special permissions. This guide describes the setup contract; no real Sigma
endpoint, credential or live compatibility is established by Samgita's fake tests.
Do not edit the sibling Sigma repository or start a second Sigma server as part
of this setup. Use the service's existing endpoint and its actual deployed version.

## Qualify the existing endpoint

1. Identify the existing externally approved Sigma URL, service version and
   authentication mechanism. For Samgita's native event connector it must be an
   exact `wss://<approved-host>/app-server` URL without userinfo, query or fragment.
2. Verify authentication before upgrade/dispatch, native schema `1.0`
   initialization, and the complete `project_events.v1` method contract:
   `project/event.receive`, `project/event.status`, `project/event.report`.
   A path name or successful WebSocket upgrade alone proves none of this.
3. Verify durable inbox commitment, stable event/operation identity, duplicate
   handling, conflicting-content rejection and status reconciliation after a lost
   reply/restart. Configure the idempotency guarantee only after this evidence.
4. Advertise additional groups only after verifying every method in those
   groups on that exact host/version. Do not infer a native group from a Codex
   session or Sigma's product features.

If the existing endpoint cannot meet the contract, leave it unconfigured/disabled
and record the failed conformance gate. A new endpoint/process, adapter, permission
change or sibling-service modification needs its own authorized scope.

## Register and authorize

Use `/agents` to register the selected stable identity. Set a descriptive Sigma
implementation label if useful, capacity, native protocol/version, the verified
endpoint URL/`websocket` transport and an external immutable/versioned outbound
credential reference such as `sigma-service-v1`. Advertise and separately approve
only tested groups. Registration starts no execution.

Register an independently generated inbound machine credential on the Agent
detail page and provision it securely in the existing service. Samgita stores
only its digest. This credential authenticates Sigma's callbacks to Samgita and
is separate from Samgita's outbound service credential and runtime lease keys.
After an interrupted credential write, inspect metadata before re-entering it.

Create/select a Project, bind this Agent explicitly, and assign only the needed
Project roles. Responsible event routing requires an enabled manager membership
and advertised/approved `project_events.v1`. Configure event type filters and
the reviewed idempotency guarantee on the Project page. Agent capabilities alone
grant neither membership nor Task ownership.

## Approve runtime routing separately

An authorized runtime operator must provision these external configuration maps
before delivery; entering a descriptor in the UI does not approve egress:

```text
SAMGITA_EVENT_DESTINATIONS
  {"<agent_uuid>":{"url":"wss://<approved-sigma-host>/app-server","addresses":["<approved-ip>"]}}
SAMGITA_EVENT_CREDENTIALS
  {"sigma-service-v1":"<value supplied by external secret management>"}
```

The Agent UUID and URL must exactly match registration. All currently resolved
DNS addresses must be approved, and the actual connection is pinned. Remote
plaintext, redirects and URL credentials are rejected. Secret values stay outside
PostgreSQL, documentation and screenshots. Changing a credential reference or
destination requires reviewed routing/replay; do not reuse a versioned reference
for a different secret and silently replay uncertain operations.

## Management callbacks and acceptance

Sigma authenticates to `POST /api/agent/connect`, then sends the current
`x-agent-connection` plus Bearer credential on Project/session/Task/Attempt
callbacks. Follow the [management API](../management-api.md) for command IDs,
integer versions, explicit owner proof reads and fenced claim/start/progress/
report/rebind operations. Effect resolution is a separate former-owner
reconciliation using the former proof and explicit evidence. A reconnect never
launches another execution.

Native event receipt requests attention. Sigma owns reasoning, planning and
delegation; only authenticated management commands create/transition Tasks.
A successful Attempt report with `effects_resolved: true` submits
`awaiting_review`; unresolved effects leave the Task `blocked` with an execution
hold. Explicit review plus a separate acceptance decision produce `accepted`.
Reopening or connection presence cannot clear unresolved effects. The UI displays
activity evidence with health unverified.

Record actual endpoint/version, authentication, persistence/restart, lost-ACK and
callback evidence before claiming real integration. See the
[capability matrix](../capability-matrix.md), [P3](../domain-phase-3.md),
[P4 coordination](../coordination-phase-4.md), [P4 GitHub](../github-phase-4.md)
and [acceptance ledger](../acceptance.md). Setup does not authorize live GitHub
provisioning, external permission changes, publication or deployment.
