# Native Gateway OAuth readiness and cancellation

This profile exercises official Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Five actual-binary cases pass at seeds `501432` and `987654`, 6.8/7.0 seconds
on the final fixture source. Enabled successful sign-in remains unqualified.

`native_gateway_oauth_profile.exs` covers the stable
`account/gatewayOAuth/read`, `login` and `cancel` methods and genuine native
`account/gatewayOAuth/changed` notices. The fixture emits no app-server frames.
Its only synthetic dependency is a loopback OAuth token endpoint that always
returns HTTP400; it cannot issue a usable token or run a model turn.

The five cases exercise absent gateway policy; primary-account prerequisite;
the changed-notice opt-out rejection; passive notReady/model-list readiness,
pending started/duplicate/cancel/failed and immediate retry; and native callback
state plus PKCE followed by sanitized token-exchange failure and matching passive
readiness. `required` denotes selected gateway policy, not whether login remains
necessary. All methods are declared in the stable native surface, so this draft
deliberately initializes with `experimentalApi=false` and
`explicitGatewayOauth=true`.

## Executed checks and evidence scope

From the independent driver directory in verified Devenv, with `MIX_ENV=test`
and the immutable `CODEX_BINARY`:

```sh
mix compile --warnings-as-errors
mix test test/native_gateway_oauth_profile.exs --seed 501432
mix test test/native_gateway_oauth_profile.exs --seed 987654
mix format --check-formatted test/native_gateway_oauth_profile.exs
```

Both runs pass **5 tests / zero failures**. Python AST, required namespace
preflight and root scoped `mix credo
apps/samgita_codex_driver/test/native_gateway_oauth_profile.exs --strict` pass.
Logs: `/tmp/samgita-gateway-*-20261024.log`; runner summary:
`/tmp/samgita-gateway-static-repair-validation-20261024.log`.
The initial native runs also passed. Strict Credo then identified an assertion
expressed with `length(Enum.filter(...)) >= 1`; replacing it with the equivalent
`Enum.any?` retained the predicate and all deadlines. The complete scoped block
was repeated on final source. No runtime code or timeout changed.

Six selected request/result/notification entries gain scoped `implemented`
evidence. The successful `account/gatewayOAuth/login` response remains missing:
cancel and token-exchange failure do not prove its successful `{}` result.
Fifteen exact field/variant contracts gain evidence: the explicit initialization
opt-in; notReady/started/failed statuses; all four changed-notice fields; all five
read fields; and its exact status enum/null branches. The null branch is asserted
only for the no-gateway read and confers no successful authentication evidence.
The `succeeded` enum remains missing. CI explicitly selects this profile.
No entry is promoted to fully verified; final aggregate/hosted and real-service
acceptance are separate gates.

The fixture starts only its owned pinned binary under private HOME, CODEX_HOME,
TMPDIR, user/network namespace and loopback-only routes. It drops ambient auth,
AWS, D-Bus, desktop and proxy variables and rejects all three `/etc/codex`
configuration sources. It never launches a browser or an auth refresh command.
The initiating connection intentionally receives the issuer authorization URL;
the synthetic query canary is allowed only in that native private handoff and in
the fixture config. Errors, broadcasts, readiness, stderr and the allowlisted
journal must not contain it. Cleanup releases HTTP sockets, terminates the owned
native process and joins workers inside a 0.75 second budget under the existing
one-second stdio-owner grace. No Session deadline is increased.

## Source evidence and remaining gates

All paths below are relative to the pinned `codex-rs` source root.

| Contract | Source |
| --- | --- |
| Stable optional-unit method params | `app-server-protocol/src/protocol/common.rs:1133-1146` |
| Four public readiness statuses and private authorization handoff | `app-server-protocol/src/protocol/v2/account.rs:596-647` |
| Latest effective provider policy, global active slot, owner cancellation, disconnect cancellation, release-before-cancel-ACK | `app-server/src/request_processors/account_processor/gateway_oauth.rs` |
| Opt-out rejects login before starting it | `app-server/src/message_processor.rs:1774-1789` |
| Ordinary status broadcasts clear authUrl and filter current provider config | `app-server/src/gateway_oauth_notifications.rs` |
| Readiness does not refresh/open a browser; login terminal errors are sanitized | `login/src/gateway_auth_login.rs:200-337` |
| Successful authorization persists the token before returning | `login/src/gateway_auth.rs:418-472` |
| Gateway storage always uses Local GatewayOAuth encrypted namespace | `login/src/gateway_auth_storage.rs` |
| Missing ciphertext returns before keyring I/O; save requires keyring passphrase | `secrets/src/local.rs:191-283` |
| Native failure/cancel/readiness reference | `app-server/tests/suite/v2/gateway_oauth_tests.rs:140-375` |

Successful sign-in, succeeded readiness, credential reuse/rotation and inference
delivery remain **BLOCKED_ENV** for this profile: native gateway storage requires
an OS keyring even with `cli_auth_credentials_store="file"`. Inherited host D-Bus
or desktop keyring access is outside the owned fixture boundary. Native Rust
success tests inject a mock keyring (`message_processor_gateway_oauth_tests.rs`),
which is not proof for the stock binary. No plaintext fallback, fabricated
encrypted file, custom app-server build or host keyring entry is proposed.

Multi-connection authorization URL privacy, cross-owner cancellation rejection
and owner disconnect cancellation are source-grounded but **not exercised** by
this bounded stdio profile. The native reference uses two WebSocket connections
(`gateway_oauth_tests.rs:380+`). Configuration-change filtering and legacy-client
automatic-browser selection also remain uncovered here.

## Provider auth recovery is a separate profile

Gateway OAuth does not emit `modelProvider/authRecoveryStarted` or
`modelProvider/authRecoveryCompleted`. The default provider returns no recovery
messages (`model-provider/src/provider.rs:180-190`); the sole pinned implementation
is Amazon Bedrock (`model-provider/src/amazon_bedrock/mod.rs:330+`). Core emits
Started only when the provider supplies messages and Completed only after
successful provider recovery (`core/src/client.rs:2750-2810`), forwarded at
`app-server/src/bespoke_event_handling.rs:251-275`.

The genuine trigger is an Amazon Bedrock provider using synthetic OLD AWS profile
credentials, a loopback HTTP401 response, a configured fixed auth-refresh command
that writes NEW synthetic credentials, then native SigV4 retry with NEW and HTTP200.
Expected messages are `AWS session has expired. Reauthenticating...` and
`Signed in with AWS.`. The upstream reproducible reference is
`core/tests/suite/external_auth.rs:418-655`. Ordinary external-account refresh
server requests and gateway token refresh cannot substitute for these notices.
The repository's existing Bedrock profile covers configuration controls and
explicitly does not execute refresh commands or model turns. Qualifying these
notices therefore needs a separately owned fixed-command Bedrock inference
fixture; this gateway profile does not claim them.
