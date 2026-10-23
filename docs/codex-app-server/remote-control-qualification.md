# Remote-control native qualification

Sixteen actual-binary cases passed locally at seeds `501432` and `987654`,
29.8 seconds each. Python AST, private namespace preflight, compile, format and
scoped strict Credo passed. This is selected native evidence with a synthetic
remote-control dependency, not real ChatGPT/relay or full compatibility acceptance.

Task: `codex_audio_skill_inputs / remote-control-native-baseline`, direct assignment. Target: immutable Codex `rust-v0.163.0`, source commit `83086188ae0614bd882818ff1aa23f3194962012`, Linux musl executable SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

This bounded unit covers selected behavior for all seven remote-control RPCs (request/response entries) and the real `remoteControl/status/changed` emitter: 15 native inventory entries. It adds no application runtime behavior, dependencies, schema forwarding, fake app-server output, service listener, daemon or production operation.

## Draft ownership and installation boundary

Only these three draft files are owned by this assignment:

| Draft under `/tmp/samgita-remote-control-draft-20261024/` | Intended repository path after parent review |
| --- | --- |
| `native_remote_control_profile.exs` | `apps/samgita_codex_driver/test/native_remote_control_profile.exs` |
| `isolated_remote_control_fixture.py` | `scripts/codex/isolated_remote_control_fixture.py` |
| `remote-control-qualification.md` | `docs/codex-app-server/remote-control-qualification.md` |

The source-only contributor prepared these paths while the coordinator owned
runtime validation. The coordinator reviewed and installed them on the existing
branch, then serialized qualification. The test uses repository-relative paths;
the `/tmp` files are source drafts, not standalone runnable packages. No runtime
driver interface or sibling service is changed.

## Isolation and provenance

Each test creates a cryptographically random scratch root with exclusive
`File.mkdir!` before creating subdirectories. A stale root is never reused or
adopted for cleanup.

The fixture verifies the immutable binary hash before and after entering its own `unshare --user --map-root-user --net --fork --kill-child=TERM` environment. It enables only loopback, checks distinct parent/child user and network namespaces, checks that only `lo` exists and that IPv4/IPv6 have no default route, and records the proof for each native generation. It starts one fixed `127.0.0.1:32145` HTTP/WS peer inside that private namespace. The same address in successive fresh private namespaces deliberately preserves the enrollment URL across owned native restarts.

The driver starts the fixture through its existing owned Stdio transport. The fixture launches the unmodified pinned executable with `app-server --listen stdio://`, copies native stdout lines verbatim to the driver, and never constructs app-server JSON-RPC responses/notifications. The backend produces only synthetic dependency HTTP bodies, a genuine WebSocket101 handshake, pong and close frames. It sends no relay `client_message`, `server_message` or counterfeited app-server output. The optional relay-dispatch qualification from the source audit is outside this unit.

The native environment is a new allowlist. HOME, CODEX_HOME, sqlite_home, TMPDIR, workspace, auth, installation identity, catalog, config and stderr live in the named disposable root. Auth uses `cli_auth_credentials_store="file"` and synthetic auth.json with mode0600, fresh synthetic tokens and a forbidden owned refresh endpoint. Host tokens, proxy variables, D-Bus/keyring service handles and user provider configuration are not inherited. There is no keyring/Auto storage, mTLS enrollment, real account, browser login, host `/etc` edit, mount change or remote repository operation.

Only initialize/initialized, thread/loaded/list, and the seven remote-control methods may enter native stdin. Turns, thread creation, command execution, tools, input delivery and response-to-server-request paths are rejected before dispatch. Config disables hooks, apps, plugins, recommendations, shell snapshots, web search and analytics; model/provider endpoints point to the owned peer, whose other methods/paths fail closed. A scratch shell canary records an unexpected execution, while native input/output journals and an empty native loaded-thread list establish the narrower actual no-execution claim. A dormant canary alone is not proof that all possible executors were inaccessible.

Backend journals retain only synthetic route/query and allowlisted verification fields. Account/server bearer and pairing/manual codes are compared in memory and journaled as booleans/slots or code kind; native request bodies/results containing secrets are not recorded. Journal/stderr canary scans and SQLite token scans run at cleanup. Pairing codes may legitimately exist in native output/driver memory and fixed fixture config; those are not persisted evidence artifacts. This does not close Samgita A11 or establish universal secret-log safety.

Cleanup closes the native stdin, waits/reaps the explicitly owned native PID, bounds termination if necessary, joins the stdout reader, closes all owned peer sockets, stops/joins the HTTP server, and reads the owned SQLite enrollment table with a read-only connection. The outer existing Stdio process-group owner controls and reaps the entire owned descendant group. Each generation records native_closed and sanitized enrollment snapshots; tests also wait for recorded PIDs to disappear before deleting the disposable root. No unrelated process is signaled. The profile does not claim crash-kill durability or graceful shutdown under every signal race; those assertions require the pending runtime checks.

## Observed selected behavior (16 tests, both seeds passed)

| Group | Intended real behavior and evidence |
| --- | --- |
| Disabled + validation | Initial native changed/read show disabled and null environment. Disabled pairing errors; both/neither status code, empty management IDs and limits0/101 reject without backend dispatch. |
| Experimental capability | Driver schema rejects all seven methods before stdin; explicit wire validation bypass reaches native and receives its experimentalApi error. Initial changed remains a legitimate ungated notification. |
| Held ephemeral lifecycle | An enrollment hold/release barrier keeps connecting observable through genuine changed/read. Exact enroll method/body/account+install headers are checked. Actual WS101 header verification precedes native connected; explicit ephemeral disable produces disabled/null and peer disconnect. |
| Ephemeral restart | An enrollment row with NULL preference preserves identity but does not auto-enable on native replacement. Counts remain one enroll/one WS across two process generations. |
| Persistent restart | Omitted enable persists true. Replacement uses the same home/account/client/URL, refreshes a fresh server bearer, and preserves server/environment/install identity. Ephemeral disable preserves true and the next replacement reconnects. Null disable persists false and the following replacement stays disabled without a new relay connection. |
| Pairing mapping | manualCode false/true become snake_case backend bodies, nullable manual code and Unix expiry are returned by native; both normal/manual status requests return claimed false then true. Exact pair/status counts are asserted. |
| Pair-start recovery | One backend401 leads to exactly one account-authenticated server refresh and one native pairing retry; pair bearer slots change1->2. This is a permitted native retry, not driver replay. |
| Pair-status recovery | The equivalent status401 path refreshes once and retries once before native claimed=true, with bearer slots1->2. |
| Pairing errors | Backend410 maps to -32600; mismatched enrollment, malformed expiry and malformed JSON map to -32603, with no unplanned extra HTTP. |
| Disabled management | Pagination/cursor/order/limit, encoded Unicode environment/client IDs, full/nullable metadata, RFC3339->Unix, populated/empty pages. Revoke actually mutates the owned peer's store; subsequent native list proves the effect. No enrollment is needed. |
| Enabled management + errors | Account bearer remains distinct from server bearer while connected. Successful list/revoke effects are checked;403/404 map to -32600,500/malformed JSON/time and revoke500 to -32603, with exact counts. |
| Malformed native inputs | Driver schema rejection emits no stdin; wire bypass reaches actual native parsing and its Invalid request error for six malformed shapes. |
| Auth gates (two tests) | No-auth and API-key persistent enable reject with the exact native auth reason. Ephemeral enable permits an initial connecting or errored snapshot, then requires the actual errored notification and status read, with no remote-control backend HTTP. |
| Invalid URL errored | A loopback FTP base (unsupported by native remote-control normalization) reaches the running native handler, produces errored and permits explicit disable, without any HTTP/WS route. It uses no external hostname or routes. |
| Uncertain pairing | A held pair POST outlives a one-second local driver deadline. Native late success is observed without clearing uncertainty; an explicit owned reconnect preserves the uncertain record and does not replay the pairing mutation. Exactly one pair POST exists across generations. |

The disabled and connected modes are separate in the assertions. Status-read/enable/disable results and changed notifications preserve the complete four-field public status tuple. Server name is derived from the native OS hostname and checked against the Base64 WS name header; installation ID is a known valid disposable UUID. Backend token/expiry do not enter the public status response.

Watch updates can coalesce and response/notification order is asynchronous. The held enrollment barrier is used where connecting must be observed. Other tests wait for the required native target status rather than assuming one event per internal mutation. The backend emits no status message. Disable response and peer disconnect are separately observed. Reconnecting the driver replaces the native process and independently reinitializes it; no existing native initialization state is simulated or reused.

The shared successful-enable helper now also holds the actual enrollment HTTP
response until native enable and status/read both expose the complete connecting
tuple and the journal proves one enrollment request with no WebSocket connection.
It then releases the fixed response and retains the strict native connected,
identity, handshake, request-count and provenance assertions. No deadline or
polling interval is increased.

The exact source permits an unheld ephemeral-enable response to reflect a later
shared status: `remote_control/mod.rs:300-353` enables the worker before reading
its status, and `:818-851` publishes connecting before returning a fresh
`self.status()` snapshot. The worker publishes connecting before auth preparation
(`websocket.rs:696-733,1376-1405`) and errored on its PermissionDenied failure
(`:803-839`). With no ChatGPT auth or API-key auth, this fresh owned profile can
therefore return either connecting or errored; connected is not legal because
auth fails before enrollment. Both accepted initial snapshots must still carry
the exact four-field public tuple with null environment. The test always requires
the native errored notification, a subsequent errored status/read, and zero
enrollment/HTTP requests. The exact persistent-enable rejection reason is
`remote control requires ChatGPT authentication` for no auth and
`remote control requires ChatGPT authentication; API key auth is not supported`
for API-key auth (`auth.rs:102-135`, processor `:195-204`). The public status schema
has no reason/error field; the reason is observed through the native persistent
rejection with unchanged auth, not invented in an ephemeral status message.

Native enrollment/WS failures have automatic jittered retry loops; they are not counted as a supposed one-shot driver behavior. The baseline deliberately uses deterministic client/pairing HTTP errors and explicit native token401 recovery. There is no500 enrollment-count claim, no429/Retry-After timing profile, and no real service token refresh. Timeout uncertainty concerns the driver mutation receipt boundary and remains explicit after late native success.

## Pinned source anchors

All paths are under `tmp/codex/0.163.0/codex-83086188ae0614bd882818ff1aa23f3194962012/codex-rs/`:

- `app-server-protocol/src/protocol/common.rs:1168–1208,2022`: seven experimental RPCs and status notification.
- `app-server-protocol/src/protocol/v2/remote_control.rs`: public camelCase fields, optional/null params, statuses and timestamps.
- `app-server/src/request_processors/remote_control_processor.rs:41–82,139–179,183–235`: dispatch, validation, permission and native error mapping.
- `app-server/src/lib.rs:765–787,864–877,1005,1238–1250,1284–1296`: policy/startup and actual notification emitter.
- `app-server-transport/src/transport/remote_control/protocol.rs:212–289`: exact route derivation and loopback URL policy.
- `.../remote_control/server_api.rs:91–131,134–164,211–251,304–317`: enrollment/refresh account+install auth and ID/time validation.
- `.../remote_control/auth.rs:73–155`: auth/account headers and ordinary Api HTTP route.
- `.../remote_control/websocket.rs:69–85,696–865,1299–1353,1376–1444`: v3 handshake, statuses, headers and timeouts.
- `.../remote_control/mod.rs:293–421,433–561,682–815`: ephemeral transitions, pairing gates/recovery and disabled client management.
- `.../remote_control/desired_state.rs:12–40,91–153` and `.../remote_control/enroll.rs:326–395`: NULL/true/false preference and bearer-free persisted enrollment identity.
- `.../remote_control/clients.rs:68–162,165–223,243–311`: pagination, encoding, auth recovery and timestamp/error mapping.
- `login/src/auth/storage.rs:601–613`: direct FileAuthStorage selection. `core/src/installation_id.rs:19–61`: ordinary local UUID file.

Full source audit: `/tmp/samgita-remote-control-source-audit-20261024.md`. Upstream native-app tests with synthetic peers are design references (`app-server/tests/suite/v2/remote_control.rs:833–1025,1046–1142`; `remote_control_auth.rs:76–166`), not this profile's verification evidence.

## Validation and curated evidence

In verified Devenv at root, Python AST and
`python3 -B scripts/codex/check_namespace_prerequisites.py` passed. With
`MIX_ENV=test` and absolute pinned `CODEX_BINARY`, the standalone driver ran:

```sh
mix format test/native_remote_control_profile.exs
mix compile --warnings-as-errors
mix test test/native_remote_control_profile.exs --seed 501432
mix test test/native_remote_control_profile.exs --seed 987654
mix format --check-formatted test/native_remote_control_profile.exs
```

All commands passed; each native run passed **16 tests / zero failures** in
29.8 seconds. Root scoped `mix credo
apps/samgita_codex_driver/test/native_remote_control_profile.exs --strict`
also passed. All native/account/server-bearer distinctions, SQLite preference
and identity, exact HTTP/WS counts, uncertainty/no-replay, namespace,
canary/token scans and owned reaping assertions passed. Runtime Sol/Astra
repair rounds: 0/0. Source review first corrected predictable scratch reuse
with a cryptographically random, exclusive root and replaced an invalid
transient-response assumption with held enrollment barriers and source-legal
auth-error snapshots. No deadline or terminal/error/count assertion was reduced.

Local runner `/tmp/samgita-single-native-unit-validation-20261024.py` recorded
`/tmp/samgita-remote-control-validation-20261024.log` and individual
`/tmp/samgita-remote-control-*-20261024.log` files. Source baseline was
`403607c`; unrelated scoped Git units advanced during these checks.
CI does not yet explicitly select this profile. Hosted/aggregate qualification
and integration of this evidence into the manifest remain pending.

This profile proposes scoped `implemented` evidence for fifteen entries. The 53 positive field/variant
contracts map only the explicit status tuples/enums, ephemeral object inputs,
null-disable's persisted-false effect, desc pagination, client metadata,
revoke IDs and pairing codes/claims/timestamp. Unobserved asc, enable-null,
output-null-only facts and disable's other status variants remain missing.
Null-disable is a tested state-changing default, distinct from a null-only
unavailable output. No entry is fully verified or profile exclusion agreed.

## Explicit limits

Managed `allow_remote_control=false` is not covered here. The immutable `codex app-server` CLI passes `LoaderOverrides::default()` (`cli/src/main.rs:1281–1285`); its system path is `/etc/codex/requirements.toml` (`config/src/loader/mod.rs:730–744`). Test-only scratch-home requirements/debug launcher hooks cannot serve as release CLI policy proof. No private mount profile or host system write is authorized by this unit.

The normal native standalone server always supplies a remote-control handle (`lib.rs:1005`); embedded missing-handle and missing-SQLite RPC errors remain source-only, not manufactured native outcomes. `features.remote_control` and `features.sqlite` are removed/ignored flags, not available native availability switches. Real ChatGPT authorization/relay pairing, external TLS/network policy, mobile clients, macOS host-device detection, mTLS/secret service profiles, full relay request dispatch/chunk/ack/replay/backpressure, production readiness, publication and A11 remain outside these checks.

These selected cases do not close every schema/behavior condition above.
All owned runtime commands finished and recorded child processes were reaped.
