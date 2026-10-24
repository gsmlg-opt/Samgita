# Native parsed-config projections

Four actual-native cases add **25 exact physical contracts** in
`v2/ConfigReadResponse.json`: ten selected Config options, eight explicitly
tested null/non-null branches, AnalyticsConfig.enabled, four
SandboxWorkspaceWrite fields and the low/high Verbosity enum members. These
are scoped implemented records. They do not qualify every enum, optional
setting, model behavior, permission enforcement or complete method.

The target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
`config_manager_service.rs:137-149` parses effective TOML into the API Config;
`protocol/v2/config.rs:144-171,278-315` preserves selected optional fields with
explicit null. `config/src/types.rs:245-252,1181-1192` defines nested defaults.
Physical schema pointers/hashes are checked individually, without alias or
equal-hash promotion.

`native_config_option_projections_test.exs` writes owned literal TOML and checks:

- Absent selected source options are present response keys with null, using
  `Map.fetch!` so omission cannot pass.
- Two distinct scalar profiles retain independently prescribed numeric values,
  strings, empty prompt strings, summary encodings and low/high verbosity.
- Empty analytics/workspace tables produce the exact parsed null/empty/false
  defaults. A separate native process preserves explicit analytics false,
  the known owned writable-root path and three true flags.

The retained ManagedRequirementsFixture runs native stdio inside private
user/mount/network namespaces with owned HOME/CODEX_HOME, read-only synthetic
system requirements, loopback only and no default routes. It verifies the
binary hash and reaps native/namespace PIDs. No thread, turn, model or tool is
requested. The global sandbox stays read-only; the nested true flags above
prove metadata retention only, with no filesystem/network execution claim.
Input config and requirements bytes remain unchanged.

The combined eight-case block and static checks passed both seeds as recorded
in [client-request capture](client-request-capture-qualification.md). Full
commands, source hashes, results and logs:
`/tmp/samgita-native-capture-projections-v2-20261024/`. Final aggregate/hosted
checks, A11 and unavailable real-service/platform paths remain separate gates.
