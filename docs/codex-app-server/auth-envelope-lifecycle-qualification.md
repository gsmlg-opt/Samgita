# Authentication, envelopes and driver lifecycle evidence

This unit indexes existing concrete assertions against immutable Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, binary
SHA-256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
It adds no runtime feature or test and makes no `verified` promotion. Source
review began at `83524e4a`; the coordinator rechecked all thirteen audited source
hashes against `085c4cc8`. The current package checkpoint is recorded separately
in [qualification](qualification.md). These are selected implementation facts,
not acceptance of every lifecycle variant, deployment or external service.

## Native authentication interactions

`auth_interactions_test.exs:175–216` receives an actual native
`account/chatgptAuthTokens/refresh` after a synthetic provider 401. It checks the
exact `unauthorized` reason and nonempty previous-account hint, explicitly
supplies replacement credentials, observes the old 401/new 200 provider requests
and reads the changed native account email. The second use of the same handle
is rejected. Lines 219–235 require explicit refusal to fail the turn without a
second model request.

Lines 238–268 receive actual `attestation/generate` with its exact empty params
contract, explicitly respond with a synthetic token, and require that exact token
in the actual Responses WebSocket handshake. Lines 271–318 independently assert
refusal (`v=1,s=2`) and the unchanged native 100ms timeout (`v=1,s=1`). They do not
turn a missing response into success. The fixture pumps requests during native
prewarming; the earlier failure and repair remain in
[repair qualification](repair-qualification.md#attestation-prewarm-event-ownership).

Production emission is present in pinned
`app-server/src/external_auth.rs:33–81` and `attestation.rs:63–127`; the former
has a 10s refresh deadline, the latter a 100ms attestation deadline and distinct
status mapping at 139–146. These four request/response entries receive selected
`implemented` status on Linux stdio. Unlike the unreachable legacy approvals,
these tests observe a real native producer. The local provider is synthetic;
no real token authorization or attestation validation is established.

Positive field evidence is restricted to refresh reason and its enum/union
branch, the previous-account hint, the exact attestation token and the two
explicit request discriminants/params wrappers. The empty attestation params
type itself is the contract; it supplies no evidence for populated fields.
Refresh `accessToken` bytes are not asserted exactly: the journal records only a
decoded email. Supplied account ID/plan constants do not establish native
consumption. Those three fields and the two unasserted native request-ID fields
retain missing status and explicit limitations.

## Concrete envelope and fault evidence

All test paths below are under `apps/`. Exact anchors also appear on each
affected manifest row. A local codec assertion or scripted peer remains labeled
as that evidence type; it is never counted as a native producer.

| Entries or fields | Actual assertion and evidence layer |
| --- | --- |
| JSONRPCError, JSONRPCErrorError, JSONRPCMessage, JSONRPCResponse | `samgita_protocol_codex/test/wire_test.exs:5–29,32–68`: four explicit complete maps survive exact codec equality; classify malformed/ambiguous envelopes and preserve selected trace/null/extension values. These are codec-only entries with no invented native transport coverage. |
| Error code/message/nonempty data, response ID/nonempty result, request ID/method/nonempty params | The same four explicit maps; `samgita_codex_driver/test/session_test.exs:107–140` additionally preserves complete scripted responses and structured errors. Native code/message/ID evidence at `real_session_test.exs:194–211` is separate from unproven native arbitrary error data. |
| Notification method and nonempty params | `wire_test.exs:5` has null params only; `session_test.exs:271–281` supplies the additional nonempty map preserved twice exactly across a visible buffer gap. No nonempty params claim is based on null alone. |
| Trace object, null branch, traceparent and tracestate | `wire_test.exs:54–68` explicitly round-trips null, empty and nonempty trace values and rejects known-field type errors. A null union branch is evidence only for that branch, not a positive nonempty field value. |
| Bidirectional correlation | `session_test.exs:107–159` settles out-of-order integer/string IDs and a cross-direction ID collision independently. `initialization_test.exs:138` supplies selected native correlation. |
| Disconnect/reconnect | `real_session_test.exs:424` and `session_test.exs:203`: explicit reconnect/reinitialize, preserved uncertainty and no automatic mutation replay. |
| Error preservation | `real_session_test.exs:194`, `compaction_retention_test.exs:76` and `session_test.exs:127`: selected native errors, failed-turn details and exact scripted error data with redacted inspection. |
| Notification opt-out | `native_thread_event_lifecycle_test.exs:307` checks native opt-out; `session_test.exs:271` separately preserves unknown received notifications. |
| Stdio framing | `transport_stdio_test.exs:43,80` checks partial/coalesced JSONL, oversize and partial exit; `transport_real_codex_test.exs:77` adds actual native stdio. |
| WebSocket framing | `transport_web_socket_test.exs:31,59` checks frames, controls, fragments and order; `transport_real_codex_test.exs:84` adds actual native WebSocket. This does not certify every backend, TLS or OS profile. |
| Unknown server requests | `session_test.exs:162` requires an explicit unsupported-method error, preserved payload and zero pending interactions. This is a scripted fault, not a claim that native Codex emitted an unknown method. |
| Owned resource exit | `transport_stdio_test.exs:104,133,170`, `session_test.exs:257`, `transport_real_codex_test.exs:116`: owned shutdown, owner death, pending cleanup and actual borrowed/owned resources. Existing cleanup fixes remain intact. |

The sixteen selected entries become `implemented`. Thirty-four positive field
contracts gain selected implementation evidence. Five limited fields stay
missing. The five lifecycle entries for deadline uncertainty, buffering,
credential isolation, missing/null/default semantics and experimental
negotiation gain their existing partial evidence without promotion here. The
first two require additional exact quota/deadline tests; the remaining source
and security matrix is broader than these examples.

## Limits and continuation

No lifecycle row is fully verified. The manifest preserves distinctions between
codec equality, scripted client faults, real native events and local synthetic
dependencies. Rust serde's untagged/Option decoding may normalize ambiguous or
null input differently from the client's deliberately lossless, stricter envelope
classifier; no differential qualification of all such cases is claimed.

Refresh timeout, repeated 401, account mismatch, malformed auth responses,
disabled attestation, connection selection and cancellation remain unqualified.
Selected null/omitted observations never imply all field values. Real signed
tokens, account authority, attestation hardware/services, other operating
systems, full authorization/lifecycle coverage and A11 remain incomplete.
Nothing here changes project acceptance, permits automatic approval or replay,
publishes a package, deploys a service or alters an external repository.
