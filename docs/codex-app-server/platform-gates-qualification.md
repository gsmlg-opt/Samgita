# Native platform gates

## Evidence state

This profile is drafted against immutable Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Three stock-binary cases pass at seeds `501432` and `987654`, 4.4 and 4.3 seconds
respectively. Python AST, namespace preflight, warnings-as-errors compilation,
formatting and scoped strict Credo pass. No production code or timeout changed.

The fixture forwards stock native app-server stdout unchanged. Its loopback peer
returns HTTP 403 to every request and cannot mint an account, enroll a credential,
provision Windows, sign a challenge or emit an app-server notification.

## Bounded Linux profile

Run the driver command from its own independent directory, with the pinned binary:

```sh
mix compile --warnings-as-errors
mix test test/native_platform_gates_profile.exs --seed 501432
mix test test/native_platform_gates_profile.exs --seed 987654
mix format --check-formatted test/native_platform_gates_profile.exs
```

Three isolated sessions cover experimental API enabled with no account, enabled
with a synthetic selected-workspace account-user identity, and disabled with no
account. All five verification methods require experimental capability. With it,
Linux status returns exact null credential/providerUnavailable metadata; enroll,
delete and valid verification return the exact typed unavailable error. Invalid
unpadded-base64url challenges fail semantic validation before the Linux provider
gate. Completed integer request IDs and unknown integer/string IDs acknowledge
repeated cancellation as empty results.

These commands ran in the verified Devenv with `MIX_ENV=test` and the immutable
`CODEX_BINARY`. Both pass **3 tests / zero failures**. Root
`mix credo apps/samgita_codex_driver/test/native_platform_gates_profile.exs --strict`
passes. Exact logs are `/tmp/samgita-platform-gates-*-20261024.log`; the command
summary is `/tmp/samgita-platform-gates-validation-20261024.log`. Hosted selection
is explicit; final hosted/aggregate results remain separate.

The synthetic access JWT includes `chatgpt_account_user_id` plus a matching
`chatgpt_account_id` and selected `account_id`; an opaque access token would not
exercise that source identity shape. These are unsigned fixture values stored
only in scratch auth.json, never a successful real service authentication. The
profile does not call account/read, so the fixture claim checks alone must not be
reported as independent native account authentication evidence.

Windows readiness is stable without experimental capability and returns exact
`notConfigured`. Each mode acknowledges `started: true`, then emits one genuine
`windowsSandbox/setupCompleted` with exact `success: false` and the non-Windows
error. The profile awaits each completion before starting the next mode and
checks unchanged config bytes and readiness after each. Final cleanup also
checks unchanged synthetic auth bytes or continued auth-file absence.

## Isolation and cleanup

Each profile creates an exclusive random root with fresh HOME, CODEX_HOME,
workspace and TMPDIR. The controller uses Python isolated mode, verifies the
stock binary hash, refuses readable host `/etc/codex` config/requirements/managed
configuration, rebuilds native environment without host credential or bus
variables, disables remote control/analytics/apps/plugins/hooks/shell tools,
uses a static model catalog and allowlists only initialize, verification and
Windows RPCs. No thread/turn, command, tool, helper, browser or real service is
authorized.

A private user/network namespace has only loopback and no IPv4/IPv6 external
route. The deny-only dependency records only fixed known path names, method and
403 status; no headers, queries or bodies. Unexpected paths/methods fail the
profile. Diagnostic native errors retain only code and message from fixed
synthetic inputs. JWT/refresh values are checked absent from native frames,
stderr and journal; this is a synthetic fixture check and does not close A11.

Native termination, reader/HTTP worker joins and socket shutdown share a total
0.75 second cleanup budget under the unchanged stdio one second grace. The
profile requires no pending interactions/uncertain operations, final cleanup
markers, and disappearance of its native/controller/namespace-owner PIDs before
removing scratch files. Namespace or host-configuration failures are BLOCKED_ENV,
not permission to weaken isolation or use host accounts.

## Source basis and remaining success gates

Paths below are relative to the pinned `codex-rs` source:

- `app-server-protocol/src/protocol/common.rs:514-547`: all verification methods
  are experimental. `v2/user_verification.rs` defines strict params and the
  cancellation acknowledgment's no-op semantics.
- `app-server/src/user_verification.rs:46-108`: verify semantic validation, cached
  account-user identity and platform support precede native provider operations.
  `user-verification/src/lib.rs:61-90` supports the platform only on macOS.
- `app-server/src/user_verification_adapter.rs:9-46,110-135`: exact invalid and
  unavailable errors. `app-server/src/message_processor.rs:1090-1097` routes
  cancellation separately; unknown/completed targets are no-ops.
- `login/src/auth/account_user_id_tests.rs:31-98` and
  `login/src/token_data.rs:152-173`: selected-workspace access-token identity.
- `app-server/src/request_processors/windows_sandbox_processor.rs:101-137,248-265,318-323`
  validates before start ACK, emits completion and returns Linux readiness.
  `core/src/windows_sandbox.rs:253-270,310-319,371-419` fails non-Windows setup
  before persisting configuration.

Linux unavailable/error results do not qualify successful enroll, deletion,
verification, active native cancellation, worker-slot release or connection
ownership. macOS success still needs an explicitly owned native macOS artifact,
local stdio/in-process origin, selected ChatGPT account-user identity, approved
Keychain/Secure Enclave/biometric operations and independently checked challenge
signature. Direct RPCs have no client-name restriction; automatic MCP activation
has a separate client-origin/name/hardware gate.

Windows ready state, successful setup, actual helper/service provisioning,
managed-policy behavior and filesystem ACL effects require an explicitly owned
Windows host and stock artifact. Linux failure notifications do not qualify those
success variants.

`windows/worldWritableWarning` has **no production construction/send site
in this pin on any platform**. Source search finds its schema/enum, classification
and exhaustive consumers, plus an unrelated UI preference; it finds no emitter.
Running Windows alone cannot resolve this source gap. Keep its required success
entry blocked and its field contracts missing; do not synthesize a frame, patch the binary or reclassify it as
schema-only evidence.

The complete pinned Rust-tree search was repeated with:

```sh
rg -n -g '*.rs' 'WindowsWorldWritableWarning|WorldWritableWarningNotification|windows/worldWritableWarning|world_writable_warning' tmp/codex/0.163.0/codex-83086188ae0614bd882818ff1aa23f3194962012/codex-rs
```

It finds exactly six lines: the type at
`app-server-protocol/src/protocol/v2/windows_sandbox.rs:10`, the wire declaration
at `app-server-protocol/src/protocol/common.rs:2068`, exhaustive matches at
`app-server/src/notification_media.rs:137`,
`tui/src/app/app_server_event_targets.rs:223` and
`tui/src/chatwidget/protocol.rs:393`, plus the unrelated configuration preference
at `config/src/types.rs:1022`. No construction/send site exists. These source
links are anchored to immutable commit
[`83086188`](https://github.com/openai/codex/tree/83086188ae0614bd882818ff1aa23f3194962012/codex-rs);
this is an upstream-unreachable blocker without a scope waiver, not a verified
native absence/emission profile. Windows execution cannot manufacture a producer.

The selected positive entry IDs are:

- `client_request:userVerification/status` and `server_response:userVerification/status`
  for the providerUnavailable status result.
- `client_request:userVerification/cancel` and `server_response:userVerification/cancel`
  for completed/unknown repeated no-op acknowledgments only.
- `client_request:windowsSandbox/readiness` and `server_response:windowsSandbox/readiness`
  for notConfigured on Linux.
- `client_request:windowsSandbox/setupStart` and `server_response:windowsSandbox/setupStart`
  for the genuine started acknowledgment on Linux.
- `server_notification:windowsSandbox/setupCompleted` for the exact failure variant
  only, with successful Windows provisioning still incomplete.

Verification enroll/delete/sign request/result success remains missing; the
real rejection evidence is indexed without promoting those six entries.
`worldWritableWarning` remains blocked. Twenty-seven directly asserted positive
fields/variants are indexed; the verify-success proof, enroll metadata, other
unavailable/error reasons, Windows ready/update states, `cwd` and warning fields
are not inferred. No entry becomes fully verified.
No full compatibility, A11 closure, publication or production readiness follows
from this bounded profile.

## User-verification prerequisite recheck

A source-only recheck at `086d5c5` found no safe additional stock-Linux success
path. The immutable
[production provider factory](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/user-verification/src/lib.rs#L61-L90)
selects UnsupportedProvider outside macOS. The
[service gate](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/user_verification.rs#L46-L108)
rejects Linux enroll/delete/verify before creating a native worker even with
cached synthetic account-user identity. Rust test-support providers are injected
in tests; they are not a production binary configuration. Existing actual-native
Linux errors and malformed-challenge tests already cover these reachable paths.
No duplicate negative test or success promotion is added by this recheck.

The real macOS profile also needs explicitly owned OS resources, not just a
scratch CODEX_HOME. The
[key namespace](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/user-verification/src/key_namespace.rs#L15-L19)
uses a fixed Keychain service prefix plus the account-user hash. Production
creation/reuse/deletion operates on DataProtectionKeychain/Secure Enclave P-256
items with unlocked-device/biometric policy; verification requires real
LocalAuthentication signing. Acceptance must independently verify the signature
against enrollment SPKI and challenge, then exercise ownership/cancellation and
account-change races. Enrollment/deletion concern local keys, not backend
registration/revocation. No such OS/account resource or operation was authorized
or used here. All six enroll/delete/verify request/result success entries remain
missing; unavailable prerequisites are not a passing platform profile.
