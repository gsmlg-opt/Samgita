# Native Bedrock provider authentication recovery

This profile targets immutable Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Both actual-binary cases pass at seeds `501432` and `987654`, 7.7 seconds each
on final source. Two notification entries and four directly asserted shared
fields gain scoped `implemented` evidence; no entry becomes fully verified.

This profile exercises the production Amazon Bedrock provider, native signing,
native unauthorized recovery and native app-server event forwarding. Only the
loopback dependency's HTTP responses and fixed credential helper are synthetic.
No fixture emits app-server frames. No AWS service, live model, real credentials
or paid invocation is reachable or claimed.

## Actual trigger and field coverage

`modelProvider/authRecoveryStarted` and `modelProvider/authRecoveryCompleted`
are stable notifications containing exactly `threadId`, `turnId`, `provider`
and `message`. Native source supplies provider `Amazon Bedrock`, started message
`AWS session has expired. Reauthenticating...`, and successful recovery message
`Signed in with AWS.`. The profile verifies complete maps, original thread/turn
correlation, order, multiplicity, actual final turn state and absence of a
ChatGPT token-refresh server interaction.

| Case | Executed real native journey |
| --- | --- |
| Configured profile | OLD static synthetic AWS profile signs HTTP401; fixed native auth-refresh command replaces scratch profile with NEW; native signs the identical payload with NEW; loopback SSE completes the turn; exact started/completed pair |
| Credential export | Fixed direct export helper supplies OLD; HTTP401; native refresh helper changes scratch credential state; native reruns exporter for NEW; same signed retry/turn/pair |

The peer verifies the complete AWS SigV4 HMAC from synthetic signing keys,
region `us-east-1`, service `bedrock-mantle`, session-token header, loopback Host,
unchanged complete decoded JSON payload and the OLD/NEW credential sequence.
Native request reconstruction can reorder JSON metadata keys; raw-byte equality
is not an upstream guarantee. SigV4 is still checked against each original body.
The peer does not store
raw Authorization, tokens, secret keys or provider payloads in the journal.
It always rejects OLD and only supplies fixed text after verified NEW signing.
The fixture admits only one fixed input turn and never emits a tool call.

## Fixed helper authorization and process ownership

The pinned validator and runtime require `aws.auth_refresh.command` to be exactly
`aws`. The fixture installs only the reviewed Python helper as the exclusive
scratch `bin/aws`, with an absolute interpreter shebang and Python `-I`. Native
initial PATH contains only that directory. Native startup prepends its owned
arg0 alias directory; the helper checks its exact path, exact four entries,
symlink targets against the native SHA256, and absence of another `aws`.
A real AWS CLI cannot resolve. Export uses
that same helper by absolute path. Both commands invoke directly, without a
shell; args are only `--owned-refresh` or `--owned-export`, with native command
timeouts of 2000 ms. No paths or commands come from model output.

Each helper verifies its direct PPID is the exact pinned native executable by
SHA256, its process group matches native ownership, its network namespace is the
fixture's private namespace, and CODEX_HOME/PATH match the exclusive root. It
accepts no dynamic arguments, reads/writes only owned scratch files, spawns no
descendants, and records allowlisted ownership metadata. Successful refresh
changes only synthetic state/files; export emits only fixed synthetic JSON.
Native awaits helper exit; the profile checks helpers have exited before close.

The outer stdio owner owns the complete fixture/native/helper process group.
Each case uses an exclusive scratch directory with 16 random bytes and fresh
HOME/CODEX_HOME/TMPDIR, private user/network namespace, loopback only, and no IPv4
or IPv6 default route. Ambient AWS, D-Bus, SSH, desktop and proxy credentials are
not inherited. All three system Codex config sources fail closed. The AWS
config contains no process, SSO, role, endpoint or web-identity settings; EC2
metadata is disabled. Provider override uses only the built-in's supported
`base_url` and `aws` fields. No borrowed daemon/session is touched.

HTTP peers are released before native shutdown. Explicit native and thread waits
share a 0.75 second total budget under the existing stdio owner's one-second grace.
The fixture verifies helper cessation and scans stderr, config, journal and
helper metadata for synthetic credential leaks. Secret-bearing scratch credential
files and exporter stdout are intentional; they never become app-server frames.
No driver deadline, configuration validator or production code is changed.

## Pinned source evidence and limits

Paths are relative to pinned `codex-rs`:

- `model-provider-info/src/lib.rs:279-298`: built-in Bedrock override allowlist.
- `model-provider-info/src/lib.rs:211-272,332-365`: supported profile/export/refresh config; export cannot combine with profile; refresh command must be aws.
- `model-provider/src/amazon_bedrock/auth.rs:52-91`: actual configured profile/export auth selection.
- `model-provider/src/amazon_bedrock/mod.rs:158-165,323-392`: eligibility, provider messages, refresh and re-export before Recovered.
- `model-provider/src/amazon_bedrock/auth_refresh.rs`: direct owned command, stderr redirection, kill_on_drop and native timeout.
- `model-provider/src/amazon_bedrock/credential_export.rs`: direct bounded exporter and credential cache invalidation/re-export.
- `utils/process/src/lib.rs:11-22`: Linux background command preserves process-group ownership; it does not invoke a shell.
- `aws-auth/src/signing.rs`: native AWS SigV4 production signer.
- `core/src/client.rs:2750-2820`: Started before provider recovery; Completed only after successful recovery; attempted-once guard.
- `arg0/src/lib.rs:310-414`: the official launcher adds its own locked helper-alias directory to PATH.
- `core/src/client.rs:1776-1925,1071`; `core/src/responses_metadata.rs:330-339`; `codex-api/src/common.rs:301`; `http-client/src/request.rs:23-24`: unauthorized recovery rebuilds the request, recreates HashMap metadata and directly serializes it; key order is not stable.
- `app-server/src/bespoke_event_handling.rs:251-275`: native thread/turn forwarding.
- `app-server-protocol/src/protocol/v2/notification.rs:9-16`: public notification fields.
- `core/tests/suite/external_auth.rs:418-655`: upstream OLD/profile refresh and native event reference.

The existing repository Bedrock profile proves configuration controls only and
does not authorize inference/commands; this new unit has separately explicit
fixed-helper/synthetic-turn scope. It does not establish real AWS/SSO access,
credential issuance, default-chain discovery, credentials from a live process,
Bedrock Runtime's Converse wire format, concurrent refresh coalescing,
helper-timeout/cancellation behavior, provider restart/reconnect recovery or
production readiness. Failed or disabled refresh is also unqualified: built-in
stream retries default to five (`model-provider-info/src/lib.rs:67,506-509`),
HTTP401 maps to retryable UnexpectedStatus, and helper nonzero exit maps back to
that original transport error (`core/src/client.rs:2800-2816`). A single final
failure/Started-only assertion would misstate those semantics. No retry override,
provider alias or increased observation deadline is introduced to avoid that
gate. Gateway OAuth and ChatGPT refresh are independent paths.
Required external/platform profiles and A11 remain incomplete.

## Reproduction, repairs and executed checks

The initial native run failed **2/2**. Retained isolated diagnosis showed the
refresh helper rejecting native's own PATH alias directory. Its strict guard
now validates that source-defined directory and every target, retaining the
exclusive scratch `aws`, exact PPID, process-group, namespace and argument checks.
The next run still failed **2/2**, after genuine recovery-completed notices:
the peer incorrectly required byte-identical retry JSON. A second retained
diagnosis records `raw_equal: false`, `semantic_equal: true`, and no changed
keys for both modes. Exact pinned request construction above explains the
reordered keys. The peer now compares the complete decoded payload, removes
no fields, and retains full raw-byte HMAC verification and two-request bound.
No timeout, production implementation or native retry policy changed.

In verified Devenv, from the independent driver directory with `MIX_ENV=test`
and immutable `CODEX_BINARY`:

```sh
mix compile --warnings-as-errors
mix test test/native_bedrock_recovery_profile.exs --seed 501432
mix test test/native_bedrock_recovery_profile.exs --seed 987654
mix format --check-formatted test/native_bedrock_recovery_profile.exs
```

Both runs pass **2 tests / zero failures**. Python AST, namespace preflight and
root scoped `mix credo
apps/samgita_codex_driver/test/native_bedrock_recovery_profile.exs --strict` pass.
CI explicitly selects the profile. Initial results remain at
`/tmp/samgita-bedrock-recovery-initial-*-20261024.log`; the PATH and payload
diagnoses are `/tmp/samgita-bedrock-recovery-path-diagnosis-20261024.log` and
`/tmp/samgita-bedrock-recovery-payload-diagnosis-20261024.log`. Final results:
`/tmp/samgita-bedrock-recovery-final-*-20261024.log`. Diagnosis scratch directories
are retained with synthetic files only; their owned processes have exited.
Final aggregate, hosted, real-service and other-platform acceptance are separate
gates. Successful local refresh is no claim of AWS login, publication or deployment.
