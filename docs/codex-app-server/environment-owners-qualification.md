# Direct environment owners and native connect timeout

This record indexes eleven existing positive environment owners and adds one
actual-native timeout differential. All are scoped **implemented**, not fully
verified. The immutable target is `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The real owned app-server and exec-server exchange original frames; no Agent,
executor response, completion or timeout is synthesized.

## Existing physical owners

Paths in this table are below `schema:v2/`. Each is the physical node in the
named file; no similarly shaped alias or nullable/enum child is promoted.
Existing assertions are in `native_environment_profile.exs` (E),
`native_thread_environment_profile.exs` (T) and `environment_profiles_test.exs`
(L), under `apps/samgita_codex_driver/test/`.

| Physical owner | Actual native evidence and limits |
| --- | --- |
| `EnvironmentAddParams.json#/properties/authBearerToken` | E49-66: null/wrong credentials fail with 401; explicit corrected upsert becomes ready, then reconnect retains credentials without another add. Only synthetic loopback credentials; no live rotation, external WSS or universal confidentiality claim. |
| `EnvironmentAddParams.json#/properties/environmentId` | E35-94, L61-75, T62-100: identity-specific ready/info, invalid replacement preserves registration, explicit upsert and selected Unicode identity. No durable identity across app-server restart or normalization claim. |
| `EnvironmentAddParams.json#/properties/execServerUrl` | E35-94, L65-91: actual approved destination yields distinct executor metadata; invalid replacement preserves registration, empty/disabled/insecure destinations reject. No external WSS, DNS/SSRF or arbitrary-destination authorization qualification. |
| `EnvironmentInfoParams.json#/properties/environmentId` | E161-167, L20-48, T98: exact local/remote/unknown/case-sensitive selection and explicit recovered metadata. No work retry is implied. |
| `EnvironmentInfoResponse.json#/definitions/EnvironmentShellInfo/properties/name` | E162-167, L21-22, T273-275: real local/owned Linux shell metadata, nonempty name. No other OS or shell execution claim. |
| `EnvironmentInfoResponse.json#/definitions/EnvironmentShellInfo/properties/path` | E162-167, L21-23, T273-275: nonempty native shell path. No exact arbitrary executable/Windows path qualification. |
| `EnvironmentInfoResponse.json#/properties/cwd` | E165, L24, T274: exact nonnull POSIX file URI for distinct owned executor and local workspace, including recovery. Null/Windows/UNC/escaping variants remain missing. |
| `EnvironmentInfoResponse.json#/properties/shell` | E162-167, L21-23, T273-275: required actual shell object/name/path. Other platforms and unavailable-executor success remain unqualified. |
| `EnvironmentStatusParams.json#/properties/environmentId` | E86-112, L16-43, T64-115: ID-specific unknown, pending, ready and disconnected reads, including selected Unicode ID. Status does not initiate work. |
| `EnvironmentStatusResponse.json#/properties/error` | E51,86-89,105-106,171, L40-43, T102-115: actual unknown/disconnected detail and omission in exact ready map. No explicit-null output or universal failure-text claim. |
| `EnvironmentStatusResponse.json#/properties/status` | E86-112,171, T64-115: all four actual current states, including pending held behind a controlled connect gate. No durable replay or external health guarantee. |

Pinned source anchors are
`app-server-protocol/src/protocol/v2/environment.rs:38-149`,
`app-server/src/request_processors/environment_processor.rs:22-99`,
`exec-server/src/environment/connect_options.rs:45-108`,
`exec-server/src/environment.rs:509-584` and
`exec-server/src/client.rs:474-502`. The reviewed exact owner/hash/assertion
table is `/tmp/samgita-environment-owner-audit-20261025.md`, SHA256
`ff8f98748f9a30d6f6ce69807cbc82787fbfd10eb4ef2b768773bd462475820f`.
Its existing source hashes match the frozen v16 two-seed package evidence;
the current full owning block below also executes all three unchanged modules.
Historical local/hosted evidence remains in
[executor qualification](isolated-environment.md) and
[selected-thread lifecycle](thread-environment-qualification.md).

## Configured connection expiry and delayed successful control

`EnvironmentAddParams.connectTimeoutMs` is passed to
`ConnectOptions::connect_timeout` in `environment_processor.rs:30`.
`connect_options.rs:103-108` chooses a finite supplied value or the native
default; `exec-server/src/client_transport.rs` bounds opening the WebSocket.
Supplying a number and receiving an add acknowledgement alone does not prove
that timeout governs a connection.

The dedicated wrapper
`scripts/codex/isolated_environment_timeout_fixture.py` inherits the retained
owned native process, private user/network namespaces, exact destination/auth,
bounded framing, metadata-only RPC firewall and process reaping. It consumes
the original bounded HTTP upgrade headers, then holds their forwarding. It
never constructs a successful upgrade or an executor RPC response.

The profile registers one ID with `500ms`, observes the actual native EOF while
the upgrade is held, requires no successful upgrade/RPC, and checks the exact
native disconnected error ending `after 500ms`. Three status reads must leave
the connection count unchanged. A separate ID with `5000ms` is still pending
behind the same gate; after at least one second, explicit release forwards the
original bytes. Only the real executor's upgrade/initialize makes it ready.
Actual remote shell/cwd are then checked. Exactly two physical connections,
one successful connection, one failed peer close and no loaded thread or model
request are allowed. This is connection timeout qualification, not execution
cancellation, an initialize timeout or an ambiguous-mutation retry.

The one selected physical owner is
`schema:v2/EnvironmentAddParams.json#/properties/connectTimeoutMs`, SHA256
`3808f32ffd19ac8287ee6f271684c543bf0689290c95ca385087dbf604961de7`.
Omitted/null/default, zero/max/invalid values, later recovery, external WSS and
other OS profiles remain unqualified. Supplied required skills and exact
request-ID upgrade/reconnect observation remain separate missing owners until
their own native scenarios pass.

## Actual validation and initial fixture failure

From the independent driver in verified Devenv, `MIX_ENV=test` and the immutable
`CODEX_BINARY`, the exact commands are recorded in
`/tmp/samgita-native-repair-continuation-v2-20261025/results.json`:

```sh
mix compile --warnings-as-errors
mix test test/native_environment_timeout_profile.exs --warnings-as-errors --seed 501432
```

The new profile passes **1/0**. The complete 15-file owning block passes
**91/0** at each of `501432` and `987654` (144.0/143.9 seconds); it includes
both environment profiles, local environment tests, native defaults/goal forks,
queued notifications and stdio/session confidentiality/lifecycle regressions.
Formatting, root strict Credo (431 source files) and a matching before/after
executable/config/workflow snapshot pass. Exact commands and logs remain in
that directory. The explicit hosted selection is the 47th isolated profile;
selection alone is not a hosted pass.

The initial v1 timeout run failed before native startup with
`invalid_transport_options`: its draft omitted isolated `CODEX_HOME`, which
the driver correctly requires. The fixture now supplies explicit scratch
HOME/CODEX_HOME/TMPDIR/PATH and no inherited environment, matching the retained
thread-environment profile. The driver guard, all bounds and every behavior
assertion remain. The failed log is retained in the adjacent v1 directory.

These selected Linux/stdio/owned-executor checks establish neither full
compatibility nor production readiness. Complete final-source local/hosted
checks, A11, source-unreachable emitters and external/OS acceptance stay open.
