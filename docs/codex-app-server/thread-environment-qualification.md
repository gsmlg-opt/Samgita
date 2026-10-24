# Native thread/environment connection lifecycle

Three actual-binary cases pass at seeds `501432` and `987654`, 30.2/30.1 seconds
on final source. The target is official Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Two notification entries and six directly asserted field contracts gain scoped
`implemented` evidence. Complete behavior and other deployment profiles remain
unqualified; no entry becomes fully verified.

## Actual native path and tested behavior

`native_thread_environment_profile.exs` uses the real authenticated native
exec-server through `isolated_thread_environment_fixture.py`. The latter
extends the retained `isolated_environment_fixture.py` ownership/controller
helper; neither emits a counterfeit app-server or executor result. Native
401/401/101 authentication probes remain required. No Samgita platform/database,
model turn or external executor is involved.

The principal case holds connection traffic while registering selected Unicode
ID `selected-环境λ` and an unselected environment. A persistent zero-turn thread
selects the held environment and duplicate owned workspace roots, with deferred
executor enabled. Releasing the gate yields exact native connected metadata.
A second thread attaches to the already connected environment, and a third
selects none. A later disconnect is the causal barrier proving that attaching
the second listener did not replay initial connected state. Only the selected
two receive lifecycle notifications.

Pausing clears the gate before closing sockets, preventing immediate reconnect
from coalescing the disconnected state. Recovery is an explicit read-only
`environment/info`; there is no second `environment/add`, thread creation or
execution. Both selected threads receive connected again. Stopping only the
owned executor yields disconnected, an actual status error and correlated info
failure. Metadata reads retain selected IDs, cwd and deduplicated roots; the
empty selection remains empty. All three threads retain empty turn projections
and no turn request was sent. Full history is unavailable before materialization,
as explicitly asserted below.

The other two cases prove the local and actual-native experimental field gate,
and exact unknown-environment rejection before thread creation. All cases assert
response correlation, loaded-thread set, zero interactions/uncertain operations,
no execution or approval request, and complete owned process/thread cleanup.

## Safety, bounds and source

Every case owns an exclusive random scratch HOME/CODEX_HOME/TMPDIR/workspace,
private user/network namespace, loopback only and no IPv4/IPv6 default route.
Ambient cloud/desktop/proxy credentials are absent. All three system Codex config
sources fail closed. Hooks, Apps/plugins, recommendations, shell snapshots,
remote control, analytics and web search are disabled; provider HTTP denies
unexpected traffic. Fixed native inputs permit only metadata, registration,
thread creation/read and loaded-list operations. No turn/command/tool/approval
or arbitrary configuration mutation is admitted.

A transparent WebSocket firewall forwards original bytes only and accepts
executor `initialize`, `initialized`, `environment/info` and `environment/status`.
Process, filesystem and HTTP RPCs are rejected before reaching the executor.
Compression/fragmentation and unexpected mask direction fail closed. Upgrade
headers are bounded to 16 KiB; frames to 64 KiB and 96 per direction/connection;
connections to 16; native input to 64 messages/16 KiB; output to 128 messages/
64 KiB; journal to 320 events. Retained stderr is checked for a 256 KiB size
bound and token leakage on close, not advertised as a preemptive buffer cap.
No production deadline or one-second stdio-owner grace changes.

Pinned paths below are relative to `codex-rs/`. The upstream tests are supporting
source evidence; their own execution is not claimed.

| Contract | Source |
| --- | --- |
| Experimental notification annotations | `app-server-protocol/src/protocol/common.rs:1973-1976` |
| Notification fields and thread selection view | `app-server-protocol/src/protocol/v2/environment.rs:10-32,72-80` |
| Experimental thread selection field | `app-server-protocol/src/protocol/v2/thread.rs:136-144` |
| Selection input fields | `app-server-protocol/src/protocol/v2/turn.rs:93-102` |
| Validate IDs/cwd and deduplicate runtime roots | `app-server/src/request_processors.rs:643-699`; `core/src/environment_selection.rs:140-166` |
| Auto-attach listener before thread/start response | `app-server/src/request_processors/thread_processor.rs:1588-1620` |
| Selection view is independent of connection readiness | `app-server/src/request_processors/thread_processor.rs:6581-6600`; `utils/path-uri/src/api_path_string.rs:206-209` |
| Deferred executor snapshot is nonblocking | `core/src/environment_selection.rs:938-971`; `core/src/session/session.rs:1467-1480` |
| Install listeners and subscribe only to changes | `core/src/session/session.rs:1902`; `core/src/environment_selection.rs:737-796` |
| Actual app-server emission and routing | `app-server/src/bespoke_event_handling.rs:231-250` |
| Shared environment connection state and recovery projection | `exec-server/src/client.rs:315-344,435-456,505-641`; `exec-server/src/client_refresh.rs:227-282` |
| Readiness/status/info and error mapping | `app-server/src/request_processors/environment_processor.rs:18-99` |
| Metadata-only native executor operations | `exec-server-protocol/src/protocol.rs:23-34`; `exec-server/src/server/registry.rs:92-107`; `server/handler.rs:208-210` |
| Snapshot-disabled/remote path cannot capture a shell snapshot | `core/src/session/session.rs:1440-1466`; `core/src/shell_snapshot.rs:152-164` |
| Official two-thread/no-initial-replay reference | `app-server/tests/suite/v2/environment_add.rs:75-200` |

An initial authentication failure is not assumed to emit disconnected:
`client_refresh.rs:254-273` attaches its state sender after successful handshake,
and `watch::Receiver::changed` does not replay initial state. Existing separate
authentication errors remain evidence for that branch.

## Reproduction, repair and executed checks

The initial native run passed connection/disconnection/recovery but failed the
zero-user-message `thread/read includeTurns:true` expectation. The diagnostic
expectation first chose the wrong unmaterialized-history branch. The exact
native result is `-32601`, `list_turns is not supported yet`:
`thread-store/src/local/thread_history/read.rs:203-228` rejects absent persisted
metadata, and `thread_processor.rs:3164-3177` forwards the unsupported operation.
The test now requires that exact rejection for each thread, then reads
`includeTurns:false` metadata, retaining every environment, root, no-turn and
notification assertion. No history or turn is manufactured. Source review also
corrected the hooks-off key and added all three system-config absence checks.
No runtime implementation, observation bound or timeout changed.

In verified Devenv, from the independent driver directory with `MIX_ENV=test`
and immutable `CODEX_BINARY`:

```sh
mix compile --warnings-as-errors
mix test test/native_thread_environment_profile.exs --seed 501432
mix test test/native_thread_environment_profile.exs --seed 987654
mix format --check-formatted test/native_thread_environment_profile.exs
```

Both native runs pass **3 tests / zero failures**. Python AST, namespace preflight
and root scoped `mix credo
apps/samgita_codex_driver/test/native_thread_environment_profile.exs --strict`
pass. Initial/diagnostic/repair logs remain under
`/tmp/samgita-thread-environment-*-20261024.log`; final results are
`/tmp/samgita-thread-environment-final-*-20261024.log`. CI explicitly selects
the profile. The configured native connect timeout remains 15 seconds; the
proxy gate is bounded to 12 seconds and event collection to ten seconds.

## Exact evidence scope and remaining requirements

```text
server_notification:thread/environment/connected
server_notification:thread/environment/disconnected
schema:v2/EnvironmentConnectionNotification.json#/properties/environmentId
schema:v2/EnvironmentConnectionNotification.json#/properties/threadId
schema:v2/ThreadStartParams.json#/properties/environments
schema:ClientRequest.json#/definitions/TurnEnvironmentParams/properties/cwd
schema:ClientRequest.json#/definitions/TurnEnvironmentParams/properties/environmentId
schema:ClientRequest.json#/definitions/TurnEnvironmentParams/properties/runtimeWorkspaceRoots
```

Fields cover owned POSIX paths, a Unicode ID, absent/nonempty workspace roots,
empty/nonempty selections and the exact lifecycle. Null roots/selections,
Windows/UNC paths, app-server restart/resume, durable notification replay,
active turns, pending remote operations, execution, distinct executors, selected
environment replacement, initial-401 events, Noise/rendezvous, external WSS and
other OS/service profiles remain unqualified. No unrelated thread field or
Task acceptance follows from this evidence. A11, final aggregate/hosted gates,
full compatibility, publication and production readiness remain incomplete.
