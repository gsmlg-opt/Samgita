# Native MCP startup and authentication states

These scenarios use stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, with executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Only native Codex emits app-server responses. The owned Python dependency serves
synthetic MCP/OAuth HTTP inside a private loopback-only network namespace with no
default route. No model task or real credential/service is used. Other deployment
profiles, A11 and complete compatibility remain incomplete.

## Startup cancellation and explicit recovery

M12 holds alpha's actual initialize response at an observable barrier while beta
finishes initialization. A selected alpha status request remains pending. Public
`turn/interrupt` with the real thread ID and empty turn ID acknowledges startup
cancellation independently; both request/response IDs are checked. Alpha returns
an exact `cancelled` row, `MCP startup cancelled`, physical null metadata and no
catalog. Beta's complete connected row remains unchanged.

The late initialize response is attempted and its handler finishes before another
status request. Alpha stays cancelled, has never listed tools, and has exactly
one initialize request. Explicit configuration repair and `config/mcpServer/reload`
then recover it. There is no reconnect, execution or automatic resubmission.
Session instance/generation, pending requests, uncertainty, interactions, execution
events and workspace contents are checked throughout.

Immutable producers are [empty-turn interruption](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/turn_processor.rs#L1620-L1666),
[core cancellation](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/mod.rs#L5309-L5316)
and [completed-client preservation](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-mcp/src/connection_manager.rs#L160-L170).
Holding ordinary initialization alone cannot produce a returned `starting` row:
ordinary metadata queries wait for startup. M14 supplies the separate cache path.

## Authentication discovery and logged-out state

M3 checks its prelogin state before the existing OAuth/PKCE and cold credential
reuse journey. Real initialize HTTP401 plus valid discovery yields selected
`authenticationRequired` with `notLoggedIn`. Threadless status physically contains
`runtimeStatus:null`. Full row equality and M1's `Map.fetch!` distinguish physical
null from an absent key.

M13 advertises a fixed owned issuer whose metadata endpoint returns HTTP404.
Native auth status becomes `unknown`; runtime independently stays
`authenticationRequired` because initialization received HTTP401. Journaled
written 401/404 responses establish the stimulus. No successful OAuth metadata,
callback, token exchange or credential file exists. Explicit discovery repair and
reload yield `notLoggedIn`, without logging in or starting work.

The error field must exist and contain the source-supported startup, handshake
and authentication fragments; its dynamic full string is not independently
qualified as a literal. Source producers are [auth projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-mcp/src/mcp/auth.rs#L201-L242),
[startup classification](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/rmcp-client/src/startup_error.rs#L19-L90)
and [selected/threadless status](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/mcp_processor.rs#L398-L539).
Pinned RMCP `4048ac40e958fb1a7d614617a2ae8d26666ee2fa`
[retains named-issuer discovery failure](https://github.com/modelcontextprotocol/rust-sdk/blob/4048ac40e958fb1a7d614617a2ae8d26666ee2fa/crates/rmcp/src/transport/auth.rs#L2667-L2692).

## Cached Apps metadata does not establish connection health

M14 first primes the native Apps tools/server-info cache. A second distinct thread
starts its own client with the same synthetic account; its real initialize
response is held. Native status returns `starting`, cached server info, empty
cached tools and `toolsError:null`, while `serverCapabilities:null` remains
physical. The original thread stays connected. Disk cache wrappers, schema
versions 4/1, matching identity basenames and exact bytes are checked without
writing or fabricating cache contents.

Releasing only the held dependency response crosses a completion barrier. The
second native row must become exactly the first connected row, with exactly one
additional initialize/tools-list sequence. Cache bytes and the original connected
row stay unchanged. No turn, approval, uncertain operation or workspace effect
is permitted. Existing five-second handler barriers and bounded test deadlines
remain unchanged.

The pin [downgrades untrusted Apps to OAuth](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-mcp/src/mcp/mod.rs#L367-L424).
The original candidate incorrectly expected `bearerToken` from ambient ChatGPT
identity; its failed run is preserved. A diagnostic initially selected the previous
test after line numbers changed; that pass is not M14 evidence. Declaration-based
selection reproduced M14's failure. Its actual auth probe lacked resource metadata
for the Apps URL. The fixed dependency now supplies that exact owned resource and
valid issuer; native status is explicitly `notLoggedIn`, with no token exchange,
callback or credential file. Forbidden-route and fixture-error checks remain.
No ambient bearer header or production auth override is added.

The unchanged cache/null oracles follow [cache persistence](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/connectors/src/connector_runtime/persistence.rs#L71-L109),
[cached metadata](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-mcp/src/connection_manager.rs#L1072-L1087)
and [cached tools while starting](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-mcp/src/rmcp_client.rs#L605-L629).
Physical `icons:null` uses the same serializable core type on disk and wire.

## Evidence and limits

M3 and M12 additionally observe full native `mcpServer/startupStatus/updated`
sequences for the exact thread/server: `starting,failed` with the literal login
guidance, and `starting,cancelled` with physical null error/failureReason. Both
require explicit recovery and exact `starting,ready` notices; M12 also checks no
late ready publication before reload. Previously collected events still pass
the original no-turn/item/server-request checks.

The first notification extension fails **14/1**, seed `501432`, because M3's
combined recovery stream contains `starting,ready,ready`. Immutable source
explains two producers: OAuth completion invalidates runtimes and prewarms a
fresh authenticated client, then unchanged configuration reload republishes
ready for a reused connection. The repaired observation uses public selected
status plus exact notification collection to finish the first startup before
reload. It separately requires a fresh exact `ready` publication and unchanged
authenticated initialize count. Arbitrary duplicates are not accepted; no
timeout, fixture, driver behavior or authentication assertion changes.

Sources are [OAuth invalidation/completion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/mcp_processor.rs),
[startup and reused-ready publication](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-mcp/src/connection_manager.rs#L698-L834)
and [native notification projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/bespoke_event_handling.rs#L203-L229).
The source-only producer audit is `/tmp/samgita-v79-mcp-ready-origins.json`,
SHA256 `0b30eccfa17dcabb990d30757013cadcb1d5320504cc93f9aaaff8522b07b7cb`.
The failed run is `/tmp/samgita-v78-native-startup-notifications-501432.log`.

Final scoped notification code passes the complete file **14/0 twice** at
`501432`/`987654` in 30.1/30.0 seconds. Logs
`/tmp/samgita-v79-native-startup-notifications-{501432,987654}.log` have SHA256
`2371c3350ac1a179f68f6a2a477f2ff328097feae46594d1f116a2666603315f` and
`d210031b5f3d3da49e85aff28c3ba075b2f115ca328aa4bb4a5ddc96a9d70081`;
test source SHA256
`c757d023a18a7a63166e9a1e7bbcf14065425fe63c3ea794ca3a67e0463c5d9c`.
Only the two physical startup `failed`/`cancelled` owners gain implementation
evidence. Current contracts are **4,471 implemented / 2,091 missing / 59
blocked**, zero verified; requirements remain 462/12/11, zero verified.
The earlier integrated checks below precede these additive assertions; full
final-source checks remain required.

Final scoped `MIX_ENV=test` compile, root formatting and strict Credo (448 source
files) pass; all 38 inventory/fetch/fixture tooling regressions and inventory
consistency pass. `/tmp/samgita-v79-integrated-test-static.log` retains static
output. An earlier launcher omitted `MIX_ENV=test` and failed before checks while
compiling development dependencies: the type checker could not read a telemetry
BEAM atom table. That log remains `/tmp/samgita-v79-integrated-static.log`;
development caches are not deleted or repaired. The successful launcher explicitly
uses the same test environment as the native qualification and final matrix.

From the independent source/dependency layout `/tmp/samgita-v66-native-candidates`,
the complete fourteen-case file passes **14/0 twice**, no exclusions, seeds
`501432` and `987654`, in 30.7/30.5 seconds. Formatting and strict Credo pass.
Commands/logs are in `/tmp/samgita-v74-starting-repair-checks/results.json`.
The earlier 12/0 and 13/0 candidates are historical checkpoints, not evidence for
M14. Initial failures and the wrong-location diagnostic remain in
`/tmp/samgita-v71-starting-diagnostic/` and the candidate directory.

After integration into the current checkout, the complete fourteen-case file
again passes **14/0 twice**, seeds `501432`/`987654`, in 31.0/30.6 seconds.
Root and independent driver compile/format, and strict Credo (448 source files)
pass. The checked two-file source snapshot remains unchanged across these runs.
Exact commands and results are in `/tmp/samgita-v76-integrated-mcp/results.json`,
SHA256 `70e0e0df3a81ab38835a631816e298bb4c4ede218b21a55521d1f1c760803d14`;
source snapshot SHA256
`1b4e7e1cc12acea3560bedcf92ba483f397e194bfba1ae44ec653394bc14f320`.
Inventory consistency passes with **4,469 implemented / 2,093 missing / 59
blocked** contracts and **462 implemented / 12 missing / 11 blocked**
requirements; both verified totals remain zero.

Six status contracts index only the physical `unknown`, `notLoggedIn`,
`starting`, `authenticationRequired`, `cancelled` and runtime-status null owners in
`v2/ListMcpServerStatusResponse.json`; the two notification contracts above use
their separate physical `ServerNotification.json` owners. No alias, arbitrary JSON domain or
`notStarted` branch is inferred. They gain scoped `implemented` evidence; no
requirement or contract becomes fully verified. Final integrated local/hosted
matrices remain separate and required. No package publication, deployment,
production migration or other repository change occurs.

## Revoked OAuth access and explicit reauthentication

M15 completes native OAuth/PKCE and lets Codex write its credential file. The
owned dependency then revokes only acceptance of that access token. A cold native
restart preserves the file and sends the revoked token, receiving actual HTTP401
`invalid_token`. Valid discovery stays available and this synthetic credential
has no refresh token. Exact native startup notices are `starting,failed` with
`reauthenticationRequired` and the pinned recovery guidance.

Repeated selected status reads must preserve authenticationRequired/notLoggedIn,
physical null metadata, empty inventories, credential digest and exact request/
token/callback counts. There is no silent token exchange or execution. A second
explicit native PKCE login issues a new token; Codex replaces the credential file
itself and publishes `starting,ready`. Tests never write, restore, edit or delete
that credential file. Normal refresh, real external OAuth/keyrings/issuer changes
and other deployment profiles remain unqualified.

## Boolean-only legacy form opt-in without a turn

M16 initializes with only `mcpServerOpenaiFormElicitation:true`; it omits the newer
extensions list. An owned stdio MCP peer emits legacy `openai/form` during an
explicit out-of-turn direct tool call. Real Codex emits the correlated elicitation
request. The consumer explicitly accepts the prescribed form; the peer observes
the exact decision, and the real native tool result and request resolution retain
their IDs and content. No model request, turn or item execution is manufactured.

The initial peer rejected native `resources/list`. Pinned full-status discovery
also queries resources and resource templates, regardless of a tools-only catalog;
only those two empty inventory handlers were added, with exact request/response
counts. Unknown methods still fail the fixture. The initial failure and repair
are retained in `/tmp/samgita-v94-m16-*`.

Two successive history oracles were incorrect. The live metadata read succeeds
with physical empty turns, paginated history and `ephemeral:false`. No user turn
has materialized a thread metadata row in the owned native SQLite store, even
though its state database exists. Thus `includeTurns:true` follows paginated
`list_turns`, whose missing-thread validation returns `Unsupported`; the exact
native result is **-32601, `list_turns is not supported yet`**. It does not take
the separate -32600 unmaterialized-thread path. Diagnostic public reads and
read-only inspection of this synthetic SQLite store establish the distinction;
no metadata or history is fabricated to make a query succeed.

Immutable producers are [paginated thread read](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L3125-L3187),
[Unsupported error mapping](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L3334-L3375)
and [missing metadata validation](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/thread_history/read.rs#L203-L231).
Preserved failed runs are in `/tmp/samgita-v98-mcp-full-repair-checks/`,
`/tmp/samgita-v101-mcp-qualification-repair1/` and
`/tmp/samgita-v105-m16-recovery/`. The exact negative result is an observed pin
boundary, not successful persisted-history qualification.

A subsequently reached cleanup assertion found the peer as a zombie owned by
the still-live Stdio subreaper after graceful fixture close. That close deliberately
keeps the outer controller/guardian available, as described in
[shutdown ownership](mcp-cleanup-order-qualification.md). Explicit checked close
of this test's owned outer Stdio connection precedes the unchanged peer-disappearance
wait. The diagnostic proves its guardian PID, zombie parent, completion flag and
closed-port state; the original observation bound stays unchanged. No production
guardian, grace period or process cleanup behavior is changed.

## Explicit OAuth registration selection

M17 forces `dcr` despite advertised CIMD support and requires actual dynamic
registration followed by native PKCE. M18 uses three fresh isolated native roots:
omitted/default auto and explicit `auto` select CIMD under matching metadata;
explicit auto falls back to DCR when CIMD is not advertised. M19 explicitly selects
`cimd`, then separately rejects missing advertisement and missing public `none`
token authentication before registration, token exchange, credential creation or
callback completion. Failed preflight does not silently fall back.

The issuer-bound success profiles require the exact public client ID
`https://chatgpt.com/oauth/codex/client.json`, no registration request under CIMD,
and native ephemeral loopback redirect/PKCE. The native client selects that URL as
its identity; it does not fetch the document. An owned local OAuth dependency can
prove selection and request semantics, not real IAM recognition, document validity
or external authorization. Native-written credential digests, selected connection
status and bounded callback-listener cleanup are checked independently.

Immutable selection sources are [request mapping](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/mcp_processor.rs#L293-L327),
[registration strategy and client identity](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/rmcp-client/src/oauth_client_registration.rs#L37-L139)
and [callback selection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/rmcp-client/src/oauth_callback.rs#L52-L101).
Exact source/archive hashes and unqualified alternatives are in
`/tmp/samgita-v91-oauth-selector-audit.json` and the v99 candidate handoff.

The first v101 static run found three overly complex/nested test helpers.
Splitting only those helpers preserves every test body and assertion; compile,
format and strict Credo then pass. These source checks alone do not qualify the
nineteen-case runtime. Final integrated runs and precise owner mappings are
recorded separately below when executed. No A11, legacy-emitter, real external
service or full-compatibility gate is closed by these fixtures.

## Integrated nineteen-case qualification

The complete candidate file passes **19/0 twice**, seeds501432/987654, after the
exact history and outer-sub­reaper ordering corrections. Format, compile and
strict Credo pass. Both unsuccessful recovery rounds and diagnosis remain in
`/tmp/samgita-v105-m16-recovery/handoff.json`; final results SHA256
`89c92a8013d3d1055c07687351289f4ddb101b28096f9538af94e731b826ea8d`.
Production shutdown code is unchanged.

After integration with the final callback repair, the full nineteen-case file
and existing one-case native Apps origin profile pass **20/0 twice**, 49.7/50.0
seconds. Root/driver compile and format, strict Credo, 38 tooling regressions,
inventory consistency and the five-file source guard pass. Commands/logs are
`/tmp/samgita-v106-integrated-mcp-checks/`; results/source SHA256 are
`653a6956fbc339fe017e1efc7fb01b83a6f5549b769a9106d515b8f8cdc206d0` /
`5a396fdf8fde9fa7896c3b413686f964741eb3a3e887a1aa2c4d4a7cc574151d`.

Five exact physical owners gain scoped implemented evidence:

| Physical owner | Actual native evidence |
| --- | --- |
| ClientRequest InitializeCapabilities.mcpServerOpenaiFormElicitation | M16 boolean-only true opt-in |
| ClientRequest McpServerOauthClientRegistration enum0/1/2 | M18 auto, M19 cimd, M17 dcr |
| ServerNotification McpServerStartupFailureReason enum0 | M15 reauthenticationRequired |

Contracts become **4,476 implemented / 2,086 missing / 59 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**. Both verified
totals remain zero. No sibling schema, arbitrary domain or broader negotiation
state is inferred. Full final-source local and exact-pushed hosted qualification
and all remaining native/external/A11 gates remain required.
