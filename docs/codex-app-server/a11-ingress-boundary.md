# A11: secret-entry and raw instrumentation boundary

Status: **blocked**, independently of dependency audit, protocol conformance or
local assembly. This source assessment supplements the reproduced exposure in
[repair qualification](repair-qualification.md). It does not implement or claim
confidentiality acceptance. It was reviewed against `main` at `f5fc9155` and the
retained Bandit 1.13.1, Phoenix 1.8.13, LiveView 1.2.11 and Plug 1.20.3 sources.
Plug.Crypto 2.2.1 fixes its separate advisory; it does not redact these events.

## Why application handlers cannot close it

Bandit's `pipeline.ex:38-39` emits the full connection before entering the
application Plug. The connection includes headers, request target and adapter
state, which can retain body bytes. `telemetry.ex:199` retains initial metadata
for exceptions. LiveView's `channel.ex:568-583` emits input parameters before
lifecycle hooks or application event handlers, and retains them at stop.
Handler attachment order, cleared assigns, error filtering, allowlisted metrics
and absence of a current exporter cannot prevent another raw handler seeing it.

The existing real-HTTP tests in
`apps/samgita_web/test/samgita_web/raw_http_telemetry_test.exs` demonstrate body
and header canaries before a diagnostic ingress, retained exception metadata,
and parsed credentials on an unauthorized request through the real Endpoint.
`telemetry_confidentiality_test.exs` demonstrates raw LiveView start and stop
parameters while asserting safe application logs and metric projections. Passing
these exposure tests remains evidence that A11 fails, not acceptance.

## Secret-bearing paths

| Entry | Boundary and evidence |
| --- | --- |
| Browser Agent credential form | `live/agents_live/show.html.heex:76` submits the named credential through LiveView. Decryption or clearing inside `put_credential` would be too late for raw event metadata. |
| Operator API | `controllers/agent_controller.ex:18` accepts body credentials; `plugs/api_auth.ex:22` consumes `x-api-key`. Encrypting the body alone leaves the authentication key in raw connection metadata. Endpoint parsers also run before router authentication. |
| Agent APIs and optional WebSocket listener | `plugs/agent_auth.ex:23` and `samgita_protocol_websocket/plug.ex:8` consume Bearer credentials. TLS protects transport but not plaintext metadata inside the server. |
| Lease proofs and Codex tickets | `attempts.ex:116,342` consumes/returns proof material; `codex_runtime.ex:194,208` returns/consumes dispatch tickets. Response metadata needs explicit confidentiality qualification too; `no-store` does not sanitize a connection. Complete response-path confidentiality is not established by current request tests. |
| GitHub ingress | `github_webhook_controller.ex:7` receives the authentication signature; `plugs/github_raw_body.ex:10` retains signed bytes in connection private data. The signature is authentication material, not the signing secret. The secret itself is resolved externally in `samgita/github.ex:409`. |
| Legacy/invalid endpoint URLs | `agents_live/components.ex:54` and `show.ex:25` receive endpoint text before domain validation. `agents.ex:352` rejects userinfo/query/fragment, and display code blanks them, after raw instrumentation has already seen the input. |

All paths above remain under the existing single-tenant infrastructure, REST
key and project-level Agent authorization boundaries. None authorizes widening
permissions or introducing a browser account system.

## Bounded browser option and its limits

A browser envelope could protect the credential form for upgraded clients:
an unnamed browser-owned password control, no LiveView submit/change/recovery
serialization, no plaintext native-submit fallback, and a controller receiving
only ciphertext. A fixed versioned hybrid envelope could use fresh AES-GCM
material wrapped with RSA-OAEP/SHA-256, bound to a short-lived context, Agent,
command, version, action, session and key identity. Existing CSRF, infrastructure
protection and domain authorization would still supply request authority.
Decrypted values would remain local to the domain call and never enter the
connection, socket, flash, logs, telemetry or raw exceptions. Command semantics
would bind the credential command, not random ciphertext or rotation metadata.

This is an **unimplemented option requiring a reviewed ingress/key contract**,
not a replacement acceptance gate. Disabling it could not restore a plaintext
fallback. Key ownership, provisioning references, rotation overlap, bounds,
expired-key failure, duplicate/conflicting commands, unsupported WebCrypto,
navigation/reconnect and interrupted submission all require concrete tests.
No keys or production settings are provisioned here.

It would not protect existing API/Bearer headers, proof/ticket exchanges,
GitHub's fixed webhook protocol, old LiveView clients, invalid legacy URLs or
secrets pasted into unrelated fields. Even an application rejection occurs after
the raw server event. Narrowing A11 to cooperative upgraded browsers would
silently change the accepted confidentiality contract.

## Minimum prerequisite and acceptance

To retain current external protocols, the server stack needs a **supported
pre-emission metadata projection mechanism** covering Bandit request headers,
targets/buffers and exception snapshots; Plug/Phoenix connection/error metadata;
LiveView parameters/socket metadata; and response proof/ticket bodies. No such
complete supported mechanism is established in the pinned dependencies. A
Bandit-only fix does not address LiveView's separate emission path. Do not patch
private framework state or present post-emission filtering as this mechanism.

The alternative requires an explicitly reviewed migration of every secret-bearing
client/ingress contract, including authentication, proof responses and an external
GitHub webhook boundary. Browser-only encryption is insufficient. This external
instrumentation or whole-ingress prerequisite blocks full A11 acceptance; it
does not block independent protocol implementation or synthetic qualification.

After the prerequisite exists, acceptance must use real Bandit and a real browser,
not only ConnTest. Scan raw start/stop/exception metadata using external-term
encoding so buffers are included, plus socket state, supported exporters and
logs. Exercise success, validation failure, stale clients, wrong/missing authority,
malformed/tampered/expired envelopes where applicable, reconnect, repeated and
interrupted commands, and intentional proof/ticket responses. Preserve digest-only
persistence and the existing authorization/idempotency/review contracts.

The architecture assessment performed source inspection only; no new runtime or
browser result is claimed here. Actual exposure reproductions and exact commands
remain in repair qualification. No publication, deployment or production migration
is justified while this gate is blocked.
