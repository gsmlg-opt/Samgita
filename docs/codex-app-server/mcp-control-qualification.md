# MCP control lifecycle qualification

Target: immutable Codex `rust-v0.163.0`, source commit `83086188ae0614bd882818ff1aa23f3194962012`, Linux x86_64 musl native binary expected SHA-256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

Eight focused native cases passed twice in fresh isolated fixtures: seed `501432`, 8 tests / 0 failures in 18.3 seconds, and seed `987654`, 8 tests / 0 failures in 18.0 seconds. This qualifies the selected Linux x86_64 musl UDS client behaviors below against synthetic loopback MCP/OAuth peers. It does not qualify real account authorization or full method/platform compatibility. The shared compatibility manifest and schema ledger remain parent-owned and were not edited by this unit.

## Scope and ownership

| Unit | Repository path |
| --- | --- |
| `native_mcp_control_lifecycle_test.exs` | `apps/samgita_codex_driver/test/native_mcp_control_lifecycle_test.exs` |
| `isolated_mcp_control_fixture.py` | `scripts/codex/isolated_mcp_control_fixture.py` |
| `mcp-control-qualification.md` | `docs/codex-app-server/mcp-control-qualification.md` |

The fixture uses only Python's standard library; it does not import or modify existing fixtures. Shared Session, transport, schema, CI, manifest and ledger changes are outside this unit's ownership. Source-audit baseline was `main`, `085c4cc8d4af95f5016649c36689bd6a09e8ade5`; the approved three-file installation baseline was `b217123e74c46f5d5b4cc4b5978d3b6cc8febaa7`. Parent integration advanced HEAD to `b592e829149bde647f9953c8950f91d289b38455` before final validation. Unrelated `samgita-codex-repair-followup.txt` and other workers' files were preserved. No commit or push was performed by this contributor.

Requested candidate methods are `config/mcpServer/reload`, `mcpServerStatus/list`, `mcpServer/oauth/login`, `mcpServer/event/stream/start`, `mcpServer/event/stream/stop`, `mcpServer/oauthLogin/completed`, and `mcpServer/event/stream/notification`: five request/response pairs and two notifications. All 12 manifest entries were `missing` in the source audit. Existing `deferred_mcp_test.exs:206` supplies only selected native status name and `toolsError:null` evidence; existing direct stdio tool/resource tests do not establish these control/OAuth/event behaviors.

## Isolation and ownership contract

The outer owned Python process reexecutes itself through `unshare --user --map-root-user --net --fork --kill-child=TERM`. The child brings up only loopback and records distinct parent/child network namespaces, `lo` as the only interface, and no IPv4 or IPv6 default route. The controller creates one loopback `ThreadingHTTPServer` and one explicitly owned native app-server on a scratch UDS. Elixir's separate Session clients borrow the UDS; closing them does not transfer native ownership.

Fresh scratch home/Codex home/cwd/temp directories, an explicit environment allowlist, file credential stores, static model catalog, disabled analytics/plugins/hooks/web search/shell snapshots and absent inference/command endpoints prevent using host accounts or an external model. Apps is enabled only for the event profile. Synthetic ChatGPT claims are fixture data; they do not prove actual ChatGPT authentication. The native binary hash is checked before every launch. The event peer asserts that native withholds ambient Authorization and ChatGPT-Account-ID headers from this untrusted HTTP origin. No turn, tool call, approval response, shell execution task, browser or real account is used.

The HTTP fixture accepts only fixed metadata, OAuth token and MCP inventory/event routes. Unknown requests are rejected and journaled. There is no arbitrary URL proxy or command control. The sole callback control parses an actual native authorization URL, requires the exact owned authorization endpoint, fixed synthetic client, S256 PKCE, loopback callback host/port and registered callback path, and then sends a fixed synthetic code/issuer or denial. Its opener disables proxies and redirects. Tokens and authorization state never appear in the HTTP journal; bearer comparisons are recorded as booleans. Native stderr remains in the owned temporary directory and must be reviewed/redacted before any external evidence publication.

HTTP handlers have bounded bodies/socket timeouts. Owned SSE streams have a 45-second fixture lifetime; these tests intentionally do not exercise the native 90-second startup timeout. Native production deadlines are unchanged. Native shutdown is bounded by 5-second terminate then 5-second kill/reap. HTTP shutdown joins request threads after signaling all stream loops. Test cleanup checks all recorded native/controller/namespace-owner PIDs have disappeared and the fixture closed marker was written before removing scratch data. No unrelated process may be stopped.

## Verified assertions — eight cases

| Case | Observed native behavior and effect |
| --- | --- |
| M1 | Two synthetic HTTP MCP inventories return sorted raw names, sanitized origin, nonempty serverInfo/capabilities/tool/resource/template values and `bearerToken` auth. Global runtime/plugin lookups are nil; these lookup assertions do not distinguish omitted keys from explicit null. Exact serverInfo equality proves `icons:null`. One-item pages preserve opaque next cursor and terminal null; zero limit coerces to one; invalid/out-of-range cursors reject. Selected live-thread status becomes connected and reuses its initialized connection; `toolsAndAuthOnly` avoids resource/template requests and returns their empty arrays. |
| M2 | A loaded thread starts on endpoint generation A. After the owned config changes, native reload returns exactly `{}` and selected live status reflects generation B with a new observed initialization. Malformed config produces native refresh error, then restoring valid config and reloading recovers. There is deliberately no atomic rollback assertion for a failing strict reload. |
| M3 | Preregistered ordinary OAuth returns an owned HTTP authorization URL and UUID loginId, with exact scopes, S256 challenge and native loopback redirect. Real native callback/token exchange verifies code/client/redirect/PKCE. Completion exactly correlates name, nonnull thread and loginId with success and absent error. Callback listener closes. Reload/status uses authenticated MCP; a cold native restart with the same isolated home generates a fresh observed bearer-authenticated initialization without another login or token exchange. |
| M4 | Wrong issuer and provider denial produce correlated native `success:false` completion with nonempty error, nil global-thread lookup and closed callback listener. Neither reaches token exchange or creates usable credentials. Missing server and invalid/nonexistent thread errors retain native messages. Wrong-state support exists in the fixture but is not exercised and supplies no evidence. |
| M5 | A nonhosted server name rejects with the exact hosted-only message. Invalid, missing or unsubscribed threads and nonobject `_meta` reject at their actual native boundary. A second UDS client cannot use another client's subscribed thread. No provider `events/stream` opens for these failures. |
| M6 | Native start remains pending until a real provider active notification; duplicate ID rejects during that pending interval. Missing/wrong native subscription IDs do not route. Valid active and Unicode/nested event notices preserve exact client outer subscriptionId, provider method/params/metadata, and native MCP request ID. The unrelated client receives no notice. Stop returns `{}` and the exact active HTTP stream observes physical peer EOF/reset within the unchanged five-second bound. |
| M7 | Explicit/repeated/unknown-ID stop returns `{}`. Peer journal correlates physical transport teardown and stream closure with the native request ID. A guard on the original thread reuses the same native MCP connection, has a distinct request ID, and discards a stale old-request event before forwarding a valid ordering-barrier event. Unsubscribing a separate thread and closing another client tear down their own streams; the guard survives both and still forwards exact events. Closing a borrowed client leaves the owned native process running. |
| M8 | Provider terminated is forwarded exactly and canceled without a reconnect. Completing an active MCP request normally causes native reconnect using the same client name/arguments/metadata and a new native request ID; native-added progressToken may differ. Reconnected active/event notices retain the client subscription ID. Completing before active fails startup promptly, without waiting for or changing the native 90-second timeout. |

All provider output is MCP JSON-RPC over actual HTTP/SSE. The fixture never synthesizes app-server JSON-RPC. Only the native app-server creates the responses/notifications asserted by the driver tests. Event metadata's `io.modelcontextprotocol/subscriptionId` is the native MCP request ID, not the app-server client's outer ID. File assertions alone never establish persistence; fresh bearer use is required.

## Exact upstream anchors

All paths below are relative to `tmp/codex/0.163.0/codex-83086188ae0614bd882818ff1aa23f3194962012/codex-rs/`.

| Contract | Immutable source anchors |
| --- | --- |
| Wire registration and experimental stream gates | `app-server-protocol/src/protocol/common.rs:1246-1281,2014-2017` |
| Status params, full row, pagination response | `app-server-protocol/src/protocol/v2/mcp.rs:50-105` |
| Stream params, empty responses and nested notice | `app-server-protocol/src/protocol/v2/mcp.rs:154-197` |
| Reload/OAuth params, registration enum, response and completion | `app-server-protocol/src/protocol/v2/mcp.rs:280-355` |
| Status/auth camel-case serialization | `app-server-protocol/src/protocol/v2/mcp.rs:18-44`; `app-server-protocol/src/protocol/v2/shared.rs:29-69` |
| Native inventory value serialization | `protocol/src/mcp.rs:231-305,330-346` |
| Prequeue stream reservation | `app-server/src/message_processor.rs:995-1025` |
| Dispatch, activation acknowledgement and stop | `app-server/src/message_processor.rs:1705-1741` |
| Connection close/thread unsubscribe cleanup | `app-server/src/message_processor.rs:866-879,1295-1305` |
| Strict reload/error prefix | `app-server/src/request_processors/mcp_processor.rs:99-106`; `app-server/src/mcp_refresh.rs:45-165` |
| Scoped/global OAuth, named server and ordinary/enterprise split | `app-server/src/request_processors/mcp_processor.rs:132-285` |
| Ordinary OAuth creation, fresh login ID, completion and runtime invalidation | `app-server/src/request_processors/mcp_processor.rs:285-361` |
| Status connection reuse, detail, origin, pagination and row construction | `app-server/src/request_processors/mcp_processor.rs:390-545` |
| Ordinary OAuth is nonbrowser | `rmcp-client/src/perform_oauth_login.rs:234-281` |
| Actual callback server, temporary loopback port, issuer validation | `rmcp-client/src/perform_oauth_login.rs:283-350,490-540,810-838` |
| Save credentials before successful completion | `rmcp-client/src/perform_oauth_login.rs:768-778`; `rmcp-client/src/oauth.rs:462-505` |
| Explicit inventory headers/auth status; runtime Apps auth | `codex-mcp/src/mcp/auth.rs:245-330`; `rmcp-client/src/auth_status.rs:82-160` |
| Hosted URL and ChatGPT registration | `codex-mcp/src/mcp/mod.rs:610-690` |
| Hosted-only/subscription/duplicate/activation/stop bounds | `app-server/src/request_processors/mcp_event_stream.rs:30-183` |
| Forwarded identity, production retry delays and terminal behavior | `app-server/src/request_processors/mcp_event_stream.rs:185-325` |
| Nonobject metadata rejection | `core/src/codex_thread.rs:1184-1205` |
| Real cancellable stream and async bounded drop cancellation | `codex-mcp/src/resource_client.rs:75-190,380-402` |
| Native MCP cancellable request | `rmcp-client/src/rmcp_client.rs:995-1022` |
| Local HTTP cancellation interception and response-stream drop | `rmcp-client/src/http_client_adapter.rs:226-237,401-425` |
| Request-ID routing, metadata filter and cancellation route removal | `rmcp-client/src/event_notification_transport.rs:96-265` |
| Upstream real OAuth fixture precedent | `app-server/tests/suite/v2/mcp_server_status.rs:179-400,485-695` |
| Upstream gated hosted-Apps event precedent | `app-server/tests/suite/v2/mcp_event_stream.rs:40-245` |

The source-audit companion `/tmp/samgita-mcp-control-source-audit.json` records 19 inspected file hashes. It is source provenance only, not executable verification.

## Verification and repair evidence

All Mix/native commands ran serially through root `devenv shell --no-tui -- bash ...`; independent-driver commands ran from `apps/samgita_codex_driver`. Native commands set `CODEX_BINARY` to the hash-checked pinned musl binary.

| Check | Actual result |
| --- | --- |
| Initial native seed `501432` | 8 tests / 6 failures, 32.2 seconds; `/tmp/samgita-native-mcp-control-initial.log` |
| Sol repair 1, seed `501432` | 8 tests / 3 failures, 33.0 seconds; `/tmp/samgita-native-mcp-control-repair1.log` |
| Sol repair 2, seed `501432` | 8 tests / 0 failures, 18.3 seconds; `/tmp/samgita-native-mcp-control-repair2.log` |
| Fresh seed `987654` after formatting | 8 tests / 0 failures, 18.0 seconds; `/tmp/samgita-native-mcp-control-final.log` |
| Independent-driver `mix compile --warnings-as-errors` | Exit 0, in final log |
| Changed-file `mix format` and `mix format --check-formatted test/native_mcp_control_lifecycle_test.exs` | Exit 0, in final log |
| Python `ast.parse` without import/execution | Passed |
| Root default-dev `mix compile --warnings-as-errors` | Failed in dependency `telemetry_metrics` while checking `Telemetry.Metrics.ConsoleReporter.terminate/2`: `beam_lib` atom decoding / `binary_to_atom` `badarg`; `/tmp/samgita-mcp-control-static.log`. Parent diagnosed an incompatible existing `_build/dev` telemetry BEAM. |
| Parent root `MIX_ENV=test mix compile --warnings-as-errors` | Passed in the verified test environment; `/tmp/samgita-mcp-root-static-test-environment.log`. This does not establish a passing default-dev build. No dependency sources or build directories were deleted or repaired. |
| Parent `MIX_ENV=test mix credo --strict apps/samgita_codex_driver/test/native_mcp_control_lifecycle_test.exs` | Passed: 1 source file, 69 checks, no issues, 0.7 seconds; same parent log. The contributor read the completed log; no `--no-compile` substitution was used. |
| Owned-process/scratch audit | No matching owned MCP fixture/native/test processes and no runtime scratch directories after final checks. Only `/tmp/samgita-mcp-control-draft` source archive remains. Each test also waits for every recorded owned PID to disappear and requires `fixture_closed` before scratch removal. |

Before the initial run, source inspection corrected the UnixSocket option from `path` to `socket_path`; this was not a repair round. Repair 1 corrected three fixture assumptions against the immutable source: reload params are null/omitted (`Option<()>`, `common.rs:1253-1257`); native deliberately omits ambient ChatGPT headers for untrusted HTTP origins (`codex-mcp/src/mcp/mod.rs:365-439`); analytics has a supported disable switch (`config/src/types.rs:245-253`, `core/src/config/mod.rs:4619`). Unknown routes remain forbidden.

Repair 2 corrected the cancellation observation. The exact pinned HTTP adapter intercepts `notifications/cancelled`, signals its local event-stream cancellation channel and returns without sending an HTTP POST (`http_client_adapter.rs:226-237`). The cancellation-biased stream wrapper then drops the HTTP response (`401-425`). The fixture now uses nonblocking `MSG_PEEK` on the exact active HTTP connection to record physical peer EOF/reset with its stream number/native request ID. It consumes no application bytes. The test requires that record plus stream-loop closure, within its original five-second wait; a stop acknowledgement, fixture shutdown, or fabricated remote cancellation notification cannot satisfy the assertion. This proves local native teardown, not a remote provider cancellation POST or business effect. M7 also reuses the original native connection for its stale-request guard, avoiding request-ID collisions across separate thread connections.

`/tmp/samgita-mcp-control-direct-schema-pointers.json` supplies source-only field mapping to the passing assertion anchors: 12 method/notification entries and 62 positive schema field/variant candidates, with separate null/omission-only, empty-only, absent and native-error observations. Canonical definitions are compared structurally; equivalent definitions do not establish execution of another method. This pointer artifact is not a retained raw wire transcript or a full schema-coverage claim. Parent owns aggregate integration and manifest decisions.

Coordinating-owner integration on the same reviewed test/fixture hashes ran the
MCP unit together with the five background-terminal cases: **13 tests / 0 failures**
at seed `501432` and again at `987654`, **39.0 seconds each**. Namespace preflight,
independent warnings-as-errors compilation and focused format check also passed.
Log: `/tmp/samgita-native-mcp-background-parent-20261024.log`. The manifest adds
only the 12 selected entries and 62 positive contracts as `implemented`; no entry
is `verified`. Native transport is `linux-x86_64-musl/unix-socket`; Stdio owns
the Python controller and does not qualify native stdio in this unit.

## Explicit limits

No real OAuth issuer, consent screen, account, grant/revocation, hosted client metadata retrieval, CIMD/DCR success, OS keyring, enterprise IdP/XAA/cloud policy, real ChatGPT/Apps authorization, production service or paid/model task is qualified. No macOS/Windows/other transport profile is covered. Stream capacity 64, oversized/overloaded payloads, native 90-second timeout, reconnect exhaustion and principal-change cancellation are not tested. Plugin provenance and all status/runtime/error variants remain incomplete. Optional fixture branches not called by tests create no evidence. A11 remains blocked; no full compatibility, release, publication, deployment or production-readiness claim is authorized.

Task `/root/codex_audio_skill_inputs`: direct three-file implementation; cumulative Sol repair rounds 2 (round 1 unsuccessful, round 2 passed), Astra rounds 0. All owned commands finished, cleanup was verified, and the exclusive runtime slot was explicitly returned to the parent. The selected unit's required checks pass in the verified test environment; the default-dev build failure remains a distinct environment limitation. Parent retains shared manifests, aggregate integration and Git delivery ownership.
