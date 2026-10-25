# Native terminal errors and managed requirement metadata

Fourteen added native cases pass in the complete ten-file owning block:
**49/0 at seeds501432 and987654**, 82.386/83.562s including command overhead.
Stock Codex is `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
All app-server messages come from that binary. No Samgita process/database,
real credentials, external service, model inference backend or OS automation
is required. Synthetic provider SSE is explicitly separate from native output.

## Actual behavior and independent oracles

| Owning file | New cases | Qualified behavior |
| --- | ---: | --- |
| `native_provider_errors_test.exs` | 4 | Misalignment details, context-window exhaustion, blank cyber-policy fallback and invalid-prompt-to-other classification. Exact errors and original thread/turn IDs, failed completion/history, one initial provider request, no automatic continuation, clean pending/uncertain state, and one caller-explicit successful recovery. |
| `native_managed_requirements_test.exs` | 2 | Exact managed catalog/log/SQLite path reporting, effective config overlay and origin exclusion; cold restart; atomic readonly writes, typed source errors and explicit restoration. Public requirements use file URIs while effective ConfigToml uses absolute paths. |
| `native_managed_permission_requirements_test.exs` | 2 | Exact named permission allowlist/default reporting, reload/removal/restoration and cold restart; typed malformed policy rejection and recovery. Managed default is a fallback: the explicit allowed `:read-only` user selection remains. A disallowed managed default is reported before full config validation rejects it. |
| `native_managed_hook_shapes_test.exs` | 3 | Fourteen exact hook-map members: twelve event groups plus two owned directory strings; command/MCP/prompt/agent handler variants; removal/restoration/cold restart and typed malformed input recovery. Hooks remain disabled. |
| `native_managed_computer_requirements_test.exs` | 3 | Independently prescribed macOS bundle IDs and Windows AUMID/executable rows, including omitted binaryName/null; absent versus present-empty per-OS maps; removal/restoration/cold restart and four typed malformed values. Features stay denied/disabled. |

The complete block also runs the retained managed provider, feature, model
default, network and extension/hook suites. Owned native/namespace processes
must be gone on close; original cleanup helpers and deadlines are unchanged.

Provider errors use native Unix WebSockets inside a private loopback-only
network namespace. Error details are live data, not authority: the misalignment
suggestion/opaque review target never initiate another turn and their exact
strings are absent from owned rollout bytes and both provider requests. Context
exhaustion recovers on a fresh caller-created thread; same-thread compaction is
not inferred. No actual provider security-policy enforcement is claimed.

Managed reads use native stdio inside distinct user/mount/network namespaces,
with a read-only synthetic `/etc/codex/requirements.toml`. Exact user/source
bytes, no auth file, no loaded threads, no turn/server request and no uncertain
operation are asserted. Computer cases additionally preserve the only workspace
entry, the independently prescribed `.git/HEAD`. Hook cases check empty managed
directories and twelve absent command canaries; they do not establish general
workspace immutability, hook execution, MCP invocation or OS enforcement.
Linux parsing/reporting of macOS/Windows metadata does not qualify those OSes.

## Exact contract scope

Only47 still-missing physical owners receive `implemented` evidence:

| Group | Owners | Scope |
| --- | ---: | --- |
| Terminal errors | 11 | Four exact CodexErrorInfo literals; nonnull misalignment branch and six exact detail/steer properties/branches |
| Managed paths | 3 | `modelCatalogJson`, `logDir`, `sqliteHome` |
| Permission metadata | 2 | `allowedPermissionProfiles`, `defaultPermissions` |
| Hook metadata | 16 | Twelve selected positive map/reference owners plus four exact retained handler variants; already indexed sibling fields receive no new count |
| Computer metadata | 15 | Eleven nested map/row/positive-reference owners plus four explicitly observed null alternatives |

Every selected ID, pointer and subtree hash is checked independently. Equal
hashes, copied definitions, parent unions, optional/null siblings and other
deployment profiles receive no inherited evidence. Requirements remain485,
462 implemented/12 missing/11 blocked; contracts become6621,
3539 implemented/3082 missing; **zero verified**. Full error/default/approval
lifecycles and external/OS success remain incomplete.

## Preserved failures and source-backed corrections

The initial v22 complete block reports49 tests/2 failures. Both new path cases
incorrectly expect raw absolute paths from `configRequirements/read`.
Pinned `app-server-protocol/src/protocol/v2/config.rs:450–455` declares PathUri;
`app-server/src/request_processors/config_processor.rs:571–573` converts paths,
and `utils/path-uri/src/lib.rs:659–662,689–695` serializes the file URI.
The separate `config_manager_service.rs:137–163` applies exact requirements to
ConfigToml and excludes user origins. The corrected test prescribes both
representations from fixture-owned paths and retains all atomic-write/error/
recovery assertions. No runtime change, deadline increase or assertion removal
is used. The initial source guard matches.

The v22b full block passes both seeds, then strict Credo rejects `-32603`.
Only its numeric separator changes to `-32_603`; the whole original source
snapshot matches after reversing that token. Independent Elixir parsing proves
AST equality. A static invocation accidentally omitted `MIX_ENV=test`, entering
a dev dependency type-check failure in Telemetry.Metrics/beam_lib. Its failure
is retained at `v22c-static`; no dependency or dev artifact is repaired. The
correct test-environment invocation, `v22d-static`, passes warning-free driver
compile, full driver format, numeric AST comparison and root strict Credo
across441 source files. Final combined-source testing remains required.

## Reproduction and provenance

In verified Devenv, `MIX_ENV=test` and the hash-checked `CODEX_BINARY`, from the
driver directory, run all ten owning files listed in
`/tmp/samgita-native-errors-managed-v22b-20261025/source.json` with
`mix test ... --warnings-as-errors --seed 501432`, then seed987654.
Namespace and native-sandbox prerequisites pass first. Complete commands, logs,
exit codes and1,493 source hashes are retained in
`/tmp/samgita-native-errors-managed-v22{,b}-20261025/` and the static directories
above. Terminal report:
`/tmp/samgita-native-errors-managed-v22-terminal-20261025.json`, SHA256
`db33abc87064ef5c3cbb5355496f30107baa7b8698b7bc09b3006cdb4e940648`.

The bounded source audit is
`/tmp/samgita-reviewed-pending-proposal-owner-audit-20261025.json`, SHA256
`41c475dc9b97948a5900d8fba58b958107331554e4143e9abe30b8e37dfad7dd`.
It retains the initial proposals and path-oracle correction as historical
source-only evidence. Parent-run native/static results above supply actual
execution evidence. The47-owner patch and full expected manifest match exactly;
all other manifest sections remain unchanged. Inventory consistency and all37
inventory regressions pass before delivery.

The earlier frozen v21/hosted results predate these executable additions.
Final complete local and exact-pushed hosted matrices remain required. A11,
upstream-unreachable emissions, external/OS success and retained unrelated
aggregate failure remain incomplete. No release, publication, production
migration, sibling-service change or deployment occurs.
