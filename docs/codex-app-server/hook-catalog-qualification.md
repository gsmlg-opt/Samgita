# Native hook catalog metadata and diagnostics

Status: six selected physical contracts implemented; **full compatibility incomplete**.
One added stock-native case passes in the complete five-file owning block:
**29 tests / zero failures**, no exclusions, at seeds 501432 and 987654.
The target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
No production code, fixture, deadline, permission or process-cleanup change occurs.

## Native behavior

The new `native_hook_lifecycle_profile.exs` case uses the existing success
fixture in private user/network namespaces and its owned stdio process. It
first saves the exact two-command TOML catalog, then writes a new owned
hooks.json containing an MCP descriptor and unsupported prompt/agent entries.
No MCP server is configured and no trust, thread, turn or execution is requested.

The actual native catalog returns the prescribed server/tool/matcher/source/key,
timeout and status message with untrusted authority. Existing TOML descriptors,
keys and hashes remain equal except for displayOrder +1. Three exact ordered
warnings identify mixed JSON/TOML sources and both unsupported handlers. Two
repeated calls preserve identical metadata, warnings and source/config bytes,
with no provider requests/errors, loaded threads, hook/turn/item lifecycle,
server request, pending interaction, gap or uncertain operation.

Removing only the new JSON file restores the exact original catalog and empty
diagnostics twice in the same live native process. Existing owned-process
cleanup and reaping checks remain in force. This is discovery/diagnostic
evidence, not an MCP call, hook execution or cold-restart test.

Six `v2/HooksListResponse.json` owners gain scoped evidence: the MCP HookMetadata
variant, handlerType field/value, server and tool fields, and nonempty warnings.
No equal-hash alias, shared property or referenced type inherits this evidence.

## Unsupported schemas remain incomplete

Pinned [discovery.rs:635–652](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/hooks/src/engine/discovery.rs#L635-L652)
records the prompt/agent unsupported warning and continues before adding an
entry. The native registry represents Command and McpTool handlers; pinned
[catalog_processor.rs:72–108](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/catalog_processor.rs#L72-L108)
maps those two into response metadata. The real test asserts warnings and absence
of prompt/agent response metadata. Their advertised schema variants remain
missing; neither raw config retention nor a scripted peer proves production
emission. This preserves the complete compatibility requirement.

## Qualification

Run:
`devenv shell --no-tui -- python3 -B /tmp/samgita-native-hook-catalog-v27-20261025.py`.
Namespace/sandbox prerequisites, warning-free compile, format and strict Credo
pass. The complete block includes hook lifecycle, import lifecycle,
configuration notices, managed hook shapes and managed extension requirements.
Native runs pass in 39.934/40.148 seconds. All 1,495 guarded source files and
the immutable binary match after completion.

Parent preflight and independent review check 12 source preimages, 21 exact
excerpts, all six full original rows/canonical nodes and the complete additive
virtual test hash. The prior disjoint retained52 promotion explains the observed
manifest hash change. The complete resulting manifest equals expected JSON;
only the six selected rows change. Inventory consistency and 37 tooling
regressions pass. Local evidence:

- `/tmp/samgita-native-hook-catalog-v27-20261025/{source.json,results.json,guards.json,*.log}`.
- `/tmp/samgita-v27-hooks6-parent-preflight-20261025.json`.
- `/tmp/samgita-v26-hooks6-independent-review-20261025.json`, SHA256
  `d8b281b5ea28135d0f9e55c9a085f97ee243a43baaf69fef210862244ba7599d`.
- `/tmp/samgita-v27-hooks6-owner-terminal-20261025.json`, SHA256
  `55de584610868de50a3a8eaa943485fbeab95e01c60e8a6f8cc46fe2a070fff1`.
- `/tmp/samgita-v27-hooks6-owner-bound-20261025-index.json` maps exact physical
  owners to the passing test hash and transport.

Contracts become **3,849 implemented / 2,772 missing**; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified in both sets.
Complete final-source and hosted matrices remain required. A11, source-unreachable
emitters, external/backend/OS success and retained aggregate failures stay open.
No release, deployment, live credentials or full compatibility is claimed.
