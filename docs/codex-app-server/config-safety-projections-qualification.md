# Parsed safety and tool metadata

Six cases in `native_config_safety_projections_test.exs` read actual Codex
`rust-v0.163.0` configuration through the independent Session. The immutable
source/binary are the [qualification pin](qualification.md#delivered-source-and-immutable-reference).
No model, browser, computer or search operation is requested.

The unchanged ManagedRequirementsFixture supplies private Linux user/mount/network
namespaces, loopback without a default route, an owned read-only requirements
mount, ephemeral auth and a nonexecuting loopback-discard provider. Managed
requirements forbid browser/computer, appshots and remote control. All selected
tool features remain explicitly false and web_search remains disabled.

The six independently specified configurations distinguish:

- Absent browser_use/computer_use/tools tables, each serialized as present null.
- Empty top-level tables with present null nested policies.
- Empty web_search options with null context/domains/location.
- Empty origin policy, platform tables and location, with exact null leaf maps.
- Profile A: false history, mixed allow/deny, distinct platform maps, executable
  without binary_name, low context, empty domains and selected US location.
- Profile B: true history, inverted policies, different platform identifiers,
  explicit binary_name, high context, two domains and selected JP location.

Complete nested expected maps come from the prescribed source inputs. Source
config and requirements bytes must stay unchanged, the native session stays
idle, and owned cleanup confirms native/namespace process shutdown. Platform
tables on Linux are metadata; they do not demonstrate macOS/Windows execution
or enforcement of those policies.

The pinned producer is `app-server/src/config_manager_service.rs:119-166`,
which parses ConfigToml and projects ApiConfig. Exact structs are in
`config/src/browser_use.rs:7-22`, `config/src/computer_use.rs:7-35`,
`config/src/config_toml.rs:700-747`,
`protocol/src/config_types.rs:409-444` and
`app-server-protocol/src/protocol/v2/config.rs:159-163,280-314,562-569`.
These are snake_case configuration structs, distinct from requirements-policy
structs and other similarly named schemas.

The **17/0** combined native block passes seeds `501432` and `987654`, plus
warnings-as-errors compile/tests, formatting, strict Credo and source guards.
Exact commands/hashes are in
`/tmp/samgita-native-followup-projections-v3-20261024/`.
Only sixty physical ConfigReadResponse contracts gain scoped implemented
evidence. Medium search-context enum, Boolean legacy search config, backend/tool
success, policy enforcement, requirements/sibling schemas, other transports/OSes
and complete verification remain unqualified. No confidentiality or A11 closure
is implied.
