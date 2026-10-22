# Synapsis integration setup boundary

Synapsis follows the same registration, membership, capacity and execution rules
as any Agent. Samgita's local fake tests do not prove the actual Synapsis service
implements the native protocol. Use the existing service endpoint and record its
exact version; this work does not edit the sibling repository, launch another
service or install a new runtime host.

## Establish actual service conformance

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

## Operator registration and Project setup

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

## Runtime destination and callback configuration

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
Read Project context and use the [management API](../management-api.md) for stable
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
credential provisioning, permission changes or deployment.
