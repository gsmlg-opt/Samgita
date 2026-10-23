# Initialization and the initialized notification

This evidence targets immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, and the pinned Linux musl executable
in [qualification](qualification.md). It adds tests and corrects inventory
metadata; no protocol schema or driver runtime is changed.

## Server readiness and client policy

Successful `initialize` establishes readiness on the pinned server. An early
`initialized` does not initialize a connection. The server logs client
notifications without acknowledging them or changing initialization state.
Consequently, reads work after successful `initialize` even if the notification
is omitted. The Samgita Session follows the canonical client sequence: validate
the correlated initialize result, send exactly `{"method":"initialized"}`, and
only then report initialization success and local readiness. This stricter local
readiness policy must not be described as an upstream notification requirement.

The unit notification's generated schemas require only its exact method name.
The generic upstream JSON-RPC notification accepts optional arbitrary JSON
parameters. Omitted and explicit null therefore remain distinct on the client
wire even though the server gives neither a processing result. Unknown envelope
additions also survive the native codec. The inventory previously gave this
notification itself as a prerequisite. A failing Python regression reproduced
that error before the generator and manifest were corrected. Other entries'
`initialized` prerequisite denotes an initialized connection, rather than receipt
of this notification.

## Executed evidence

| Test layer | Contract exercised |
| --- | --- |
| `samgita_protocol_codex/test/initialized_notification_test.exs` | Both schema profiles; omitted/null/object/array/string/integer/boolean/nested params; future additions; exact encode/decode round trips; missing, nonstring and incorrectly cased methods rejected by the schema |
| `samgita_codex_driver/test/initialized_transport_test.exs` | Nine actual-binary combinations: stdio, capability-token WebSocket and borrowed Unix socket, each with absent/false/true experimental negotiation; early notification followed by `-32600 Not initialized`; successful initialize without the notification; usable reads after each parameter variant and duplicate notification |
| `samgita_codex_driver/test/initialization_test.exs` | Eight scripted client lifecycle cases: no premature notification; exact canonical emission after matching validated success; unmatched/duplicate/late responses; upstream rejection; malformed results; deadline; notification send failure; explicit reconnect and generation isolation |
| `scripts/codex/test_inventory.py` | Generator regression proves the client notification and initialize request have no readiness prerequisite while ordinary reads retain theirs |

The raw-transport tests inspect every decoded message in a received batch. Each
notification has a unique subsequent read barrier. Unexpected/duplicate response
IDs, server requests, echoes and closure fail. A final bounded 100 ms drain checks
for additional messages; this is not proof of indefinite silence. Unrelated
server notifications are permitted. The Session tests use synchronous status
barriers for mailbox ordering and an actual request deadline for timeout evidence.

Fixtures use exclusive random scratch homes/workspaces, no account or model
provider, bounded monotonic startup/read deadlines and asserted owned-process
shutdown. After closing a borrowed WS/UDS client, a fresh client connects to the
same endpoint and completes its own initialize and correlated read before
closing. Only then does the fixture explicitly close the server owner. Server
survival is established by a new protocol round trip, rather than only the
presence of a helper process or socket file.

## Scope and next requirements

These checks qualify selected Linux initialization behavior. They do not qualify
other operating systems, signed-JWT success, every initialization capability or
all transport failure profiles. The Session currently exposes its automatic
canonical notification; arbitrary client-notification envelopes remain available
through the native codec/transports rather than a Session notification API.
Keep that driver surface and the remaining deployment profiles visible in the
full compatibility assessment. Selected evidence is attached to the initialized
and initialization-order entries without marking either fully verified.

Upstream references, relative to `codex-rs/`:

| Contract | Source |
| --- | --- |
| Typed unit notification | `app-server-protocol/src/protocol/common.rs:1764-1770,2097-2099` |
| Generic optional JSON params | `app-server-protocol/src/rpc.rs:58-65` |
| Logging-only notification handling | `app-server/src/message_processor.rs:740-751` |
| Readiness set by initialize request | `app-server/src/request_processors/initialize_processor.rs:134-145,220-229`; `app-server/src/lib.rs:1238-1269` |

Exact local/hosted commands, counts and residual gates belong in
[the qualification record](qualification.md).
