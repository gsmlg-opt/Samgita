# Native app-policy configuration projections

Scoped implementation evidence against immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, official Linux musl executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Four real-native `config/read` cases pass at both fixed seeds. These are parsed
configuration results; effective connector authorization and tool exposure have
separate contracts.

## Prescribed inputs and complete result maps

The actual native config manager reads synthetic TOML and produces every
app-server response. No model/provider peer is involved. The tests prescribe
complete maps before receiving results and use `Map.fetch!` so an absent field
cannot masquerade as an explicit null.

- No apps table produces a present `apps:null`.
- An empty apps table produces exactly `{"_default":null}`.
- Empty global/app/tool/link tables distinguish omitted optional maps, empty
  maps and a map with an empty typed member. Global boolean defaults are true;
  optional overrides remain explicit null. An empty tool has exactly null
  enabled/approval-mode members; an empty link has null reviewer/mode members.
- Explicit global, app, tool and linked-account values retain their distinct
  levels. A disjoint control app still serializes enabled:true and null overrides
  under false global defaults. This demonstrates raw projection rather than
  inheritance expansion. Omission metadata distinguishes null, empty array and
  the prescribed deferred entry.

Apps, plugins and recommended plugins remain disabled, as do web search and
automatic update/login-shell behavior. All config and requirements bytes remain
unchanged. The existing `ManagedRequirementsFixture` is reused without changes:
private user/mount/network namespaces, read-only `/etc/codex`, pinned executable
hash, loopback-only interfaces and no IPv4/IPv6 default route are required.
Every case verifies no loaded thread, turn or server request, ready/idle driver
state and confirmed owned native/namespace-process cleanup. No credential,
installation, external backend, provider turn, platform data or sibling service
is used.

Existing `native_app_catalog_profile.exs` and its fixture already assert selected
installed/callable effects of app controls. Those stronger effect checks remain
intact; this unit adds separate config result owners and makes no broader
effective-policy claim.

Pinned source anchors:

- [Config manager](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/config_manager_service.rs#L119)
  loads layers/requirements, serializes ConfigToml and parses the API Config.
- [Input policy types](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/config/src/types.rs#L445)
  define defaults, flattened maps and optional overrides; top-level apps is an
  Option in `config_toml.rs:543–545`.
- [Output policy types](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/config.rs#L174)
  restore explicit null output members and boolean defaults.
- [Official source test](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/tests/suite/v2/config_rpc.rs#L1063)
  corroborates policy projection and null versus empty links. That reference was
  inspected, not executed as repository evidence.

## Checks and limits

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-config-apps-projections-20261024.py
```

Its matching directory retains every command, terminal result and executable
source snapshot. Driver warning-free compile, scoped format and root strict
Credo (**416 files**) pass. Actual-native seeds501432 and987654 each report
**4/0**, no exclusions, 4.7s each. The source guard matches; the final test SHA256
is `962da0e94920c10fb8d3ccb64c230c5ecf4d8e3ba905d7de481350f916e06f26`.
The exact proposal and four prescribed inputs/results are retained in
`/tmp/samgita-config-apps-defaults-proposal-20261024.json`, SHA256
`86f8ea3d610da62cda76719419799621bf297e11c5126c42b73f7cd542a7962b`.

Exactly **42** actual canonical `ConfigReadResponse` app-policy owners receive
scoped implemented evidence after direct assertion review: twenty fields,
eleven non-null branches and eleven explicit-null branches. Every owner has its
own direct output pointer, prescribed value and assertion locations in
`/tmp/samgita-config-apps-final-physical-owner-audit-20261024.json`, SHA256
`fdbc55e2c1b357dbd3bc2445bc83537020c02f75ec6b08cfc4c59dca98e313b7`.
No global enum, equal-hash
copy, layer/origin, request envelope, complete response or fully verified
promotion follows. Parsed reviewer, approval and enabled values do not establish
reviewer execution, authorization, inheritance or app/tool enforcement.
Other OS/transports, live external success, full compatibility and A11 remain
incomplete. Complete final-source aggregate/package and hosted checks remain
required. No release, publication, production migration or deployment occurs.
