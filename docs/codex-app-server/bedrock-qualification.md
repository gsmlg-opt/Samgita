# Native Bedrock local controls

This profile targets the three experimental Bedrock discovery/setup/advisory
methods of official Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`. The expected Linux musl binary SHA-256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Ten actual-binary cases pass locally at seeds `501432` and `987654`,
14.1/14.0 seconds on final fixture source. Selected native evidence is recorded below; actual AWS service
acceptance and full qualification remain incomplete.

The fixture bridges actual native stdio responses; it does not implement or
synthesize the app-server protocol. It uses a fresh disposable `CODEX_HOME`,
static synthetic shared AWS profiles and explicitly selected synthetic
environment values. A private user/network namespace has loopback only and no
IPv4/IPv6 default routes. There is no backend listener, AWS connection, model
turn, shell command, SSO, role assumption or credential process. Configured remote
endpoint hostnames in the advisory scenario are data inspected locally; no
remote connection is authorized or possible through this namespace.

Discovery reads local AWS metadata. Environment setup checks local nonempty
credential availability. Static-profile setup resolves only owned static
credentials and writes a provider/region/profile selection. Codex explicitly has
a TODO to validate against Bedrock `ListModels`. Neither setup success nor
`shouldWarn: false` establishes AWS authentication, permissions, service
acceptance or policy compliance.

## Observed scenarios

Ten native tests are supplied. The first checks that all three methods require
experimental negotiation in both the driver and native server. The remaining
nine scenarios are:

1. Discovery returns selected-profile-first metadata and both environment
   credential types, trimming `AWS_REGION`.
2. `AWS_DEFAULT_REGION` alone does not populate the discovery environment region.
3. An incomplete keypair and blank bearer token do not advertise credentials.
4. Environment access-key setup trims/persists its supported region.
5. Environment bearer-key setup trims/persists its supported region.
6. A static profile name is trimmed, environment selection clears it, unrelated
   provider headers survive and a cold native restart retains the configuration.
7. Unsupported region, blank/missing profile and absent environment credentials
   return correlated native errors while leaving config bytes unchanged.
8. Forced ChatGPT login policy rejects discovery/setup without changing files.
9. The advisory rereads current provider/configuration, gives exact official
   GovCloud hostnames precedence over a commercial configured region, and rejects
   a synthetic lookalike suffix as an official hostname. With no managed
   requirements, GovCloud returns `true/true`; commercial returns `false/false`.

Tests preserve the normal Session request deadline. They check exact response
IDs, no loaded threads/active interactions/uncertain operations, config-layer
and disk effects, no auth/dotenv files, namespace proof, native/controller owner
cleanup and synthetic secret absence from wire/config/stderr/journal. The
controller caps each native input/output frame at 64 KiB, native input at 48
messages per process and journal history at 160 records. Its allowlist admits
only the three methods plus initialize/initialized, config read, fixed-value
config writes and empty loaded-thread queries. No app-server frames are created
by the fixture.

## Source evidence

All paths below are under pinned `codex-rs/`:

- `app-server-protocol/src/protocol/common.rs:1309` and
  `app-server-protocol/src/protocol/v2/bedrock.rs` define the experimental methods and
  request/response variants.
- `app-server/src/request_processors/account_processor/bedrock_setup.rs:24`
  performs discovery; `:68` validates setup, trims region/profile, resolves a
  selected profile or checks local environment and persists configuration. Its
  `ListModels` TODO marks the service-validation boundary.
- `aws-auth/src/discovery.rs:18` reads and sorts profiles without resolving their
  credentials; `:46` validates a selected static profile through the SDK provider.
- `app-server/src/request_processors/bedrock_auth.rs:22` writes provider/profile/
  region, clears a null profile and preserves unrelated config. `:73` rejects
  conflicting higher-precedence providers and executable credential exporters.
- `app-server/src/request_processors/account_processor.rs:424` gates Bedrock
  login under forced ChatGPT, workload identity and external ChatGPT auth.
- `app-server/src/request_processors/account_processor/bedrock_gov_cloud.rs:17`
  reloads current config, recognizes exact official domains, resolves fallback
  region, and calculates the advisory from managed requirements.
- `model-provider/src/amazon_bedrock/mantle.rs:12` lists supported regions;
  `us-west-1` is unsupported in this pin.
- `app-server/tests/suite/v2/bedrock_setup.rs` and
  `app-server/tests/suite/v2/bedrock_gov_cloud_tests.rs` corroborate these local
  branch expectations; their upstream execution is not claimed here.

The `CODEX_APP_SERVER_MANAGED_CONFIG_PATH` path is behind `cfg(debug_assertions)`
in `app-server/src/main.rs:150`. The official CLI invokes the app-server with
default loader overrides at `cli/src/main.rs:1281`. This profile therefore does
not use that variable to fabricate a managed-positive profile. It fails closed
if host `/etc/codex/config.toml`, `requirements.toml` or `managed_config.toml` exists, leaving
host policy untouched. Managed `shouldWarn: false`, conflicting managed provider,
credential-export, workload identity, cached Codex-managed Bedrock auth, SSO,
role, refresh/recovery and real AWS acceptance remain unqualified here.

## Reproduction, correction and validation

The initial nine cases all failed before business dispatch: the draft omitted
experimental negotiation. Exact `common.rs:1308-1326` marks all three methods
experimental. The profile now initializes with that capability and adds a tenth
case proving the disabled gate in both driver and native server. That case first
requires zero stdin dispatch, then uses wire-only validation to reach the actual
native experimental error. Config bytes remain unchanged. No production code,
deadline or business assertion was relaxed.

In verified Devenv, from the independent driver directory with `MIX_ENV=test`
and the pinned `CODEX_BINARY`:

```sh
mix compile --warnings-as-errors
mix test test/native_bedrock_profile.exs --seed 501432
mix test test/native_bedrock_profile.exs --seed 987654
mix format --check-formatted test/native_bedrock_profile.exs
```

Both runs pass **10 tests / zero failures**. Python AST and namespace preflight
pass, as does root scoped `mix credo
apps/samgita_codex_driver/test/native_bedrock_profile.exs --strict`.
Initial failure: `/tmp/samgita-bedrock-initial-gate-failure-20261024.log`;
repair logs: `/tmp/samgita-bedrock-*-20261024.log`.
The earlier repair repeat took 13.9/15.4s; adding the fail-closed system-config
guard and rerunning both seeds produced the final times above with all checks
passing, including strict Credo.
An additional combined Bedrock/remote-control repeat passes **26/0**, seed
`501432`, 46.1s. Six method/result entries and nineteen directly positive
contracts gain scoped `implemented` evidence; none is fully verified.
CI explicitly selects the profile. Final aggregate/hosted evidence is separate;
no AWS service validation, real credential, publication or full compatibility
is claimed.
