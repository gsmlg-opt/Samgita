# Initialization and the initialized notification

This evidence targets immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, and the pinned Linux musl executable
in [qualification](qualification.md). The initial checkpoint added tests and
corrected inventory metadata. The subsequent native-notification checkpoint
adds an explicit driver API without changing the pinned schema.

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
all transport failure profiles. The subsequent `Session.notify_native/3` fills
the native client-notification driver surface: it preserves full envelopes and
params presence, applies wire/schema/size bounds and checks instance,
generation and absolute dispatch deadline immediately before sending. A local
write returns `sent_unconfirmed`; there is no ID allocation or fabricated ACK.
Notifications do not alter handshake/correlation state, and reconnect never
replays them. Explicit wire extensions are not a compatibility claim.

Nine deterministic tests first failed for the missing API, then passed with the
implementation. They cover complete native values/additions, sending during
initialization, bounds, invalid inputs, dispatch fences, queued reconnect and
failed writes preserving pending mutation uncertainty. Three further tests use
the real pinned binary over stdio, capability-token WebSocket and UDS. Early,
duplicate and parameter-varied Session notifications leave readiness under
initialize control; subsequent correlated reads work, with no fabricated
notification responses. Independent server notifications may arrive during the
local send and remain in the checked event queue. Borrowed endpoints survive a
fresh-client initialize/read after client closure.

The focused command covering these 12 new cases and 28 retained Session cases
passed **40 tests**, seed `362646`; logs are
`/tmp/samgita-native-notification-{red,green,focused,static}.log`. An initial
real-transport assertion compared asynchronous incoming-event counters as though
they were notification-send state; excluding those counters while still checking
every drained event corrected that test assumption. No runtime workaround was
needed. Parent full-package/final-source checks remain separate in qualification.
Selected evidence is attached to the initialized and initialization-order entries
without marking either fully verified or completing unavailable profiles.

Upstream references, relative to `codex-rs/`:

| Contract | Source |
| --- | --- |
| Typed unit notification | `app-server-protocol/src/protocol/common.rs:1764-1770,2097-2099` |
| Generic optional JSON params | `app-server-protocol/src/rpc.rs:58-65` |
| Logging-only notification handling | `app-server/src/message_processor.rs:740-751` |
| Readiness set by initialize request | `app-server/src/request_processors/initialize_processor.rs:134-145,220-229`; `app-server/src/lib.rs:1238-1269` |

Exact local/hosted commands, counts and residual gates belong in
[the qualification record](qualification.md).

## Entry and field evidence audit

The repeated complete-driver checkpoint at `bc437ca` executes the raw transport,
Session initialization and native-notification cases above. The manifest now
records `initialize` request/response and `initialization-order` as scoped
`implemented`, in addition to the existing notification entry. This closes an
evidence-index gap; it adds no executable behavior or full-verification claim.

Six directly exercised fields/branches receive that same scoped status:
`clientInfo`, the capabilities object and its nonnull branch, exact disposable
`codexHome` including its path branch, and Linux `platformOs`. The nine raw
transport combinations prove absent/false/true negotiation; native Session
notification cases assert the exact home and platform and subsequent usable
reads. Scripted lifecycle tests separately prove matching-result readiness,
late/duplicate/malformed/deadline/reconnect behavior. They do not establish
native production emission of any unrelated server request.

Explicit-null capabilities, full client identity semantics, user-agent and
platform-family values, every opt-out/gating interaction, signed-JWT success
and other deployment profiles remain unqualified. The manifest does not promote
those fields because the selected tests only construct or forward them, or do
not assert their actual native meaning. No entry is marked `verified`.

## Response metadata and validation

`native_initialization_metadata_test.exs` adds two stock-native cases. Explicit
null capabilities initialize a connection; distinct fresh originating clients
select their prescribed name/version user-agent boundaries. CR, LF and lambda
in the selected version sanitize to exactly three underscores. The variable
OS/terminal segment is deliberately not asserted as a portable constant.
Native codexHome, platformFamily=unix and platformOs=linux are exact, with zero
loaded threads or provider requests.

An invalid header client name returns the exact native -32600 error and leaves
initialization uncommitted. A valid name succeeds on that same connection;
the invalid identity cannot contaminate its user-agent. Source is
`app-server/src/request_processors/initialize_processor.rs:80-104,130-218`,
`login/src/auth/default_client.rs:152-203` and
`app-server-protocol/src/protocol/v1.rs:27-40,72-84` at the pinned commit.

The **17/0** combined block passes both seeds `501432` and `987654`; compile,
format, strict Credo and source guards pass. Logs are
`/tmp/samgita-native-followup-projections-v3-20261024/`.
Five exact fields/branches gain scoped evidence: client name/version,
explicit-null capabilities, platform family and selected user-agent semantics.
Title, full capabilities/opt-outs, shared-process identity, other transports,
OSes and full verification remain incomplete. The earlier paragraph's withheld
null/identity/family claims apply to its earlier evidence, superseded only for
these selected new cases.
