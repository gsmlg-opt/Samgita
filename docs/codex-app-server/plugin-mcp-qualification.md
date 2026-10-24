# Native plugin capability, policy and uninstall

`native_plugin_mcp_profile.exs` runs stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
It installs one owned local marketplace plugin containing a real stdio MCP peer.
No provider listener, inference, shell command, auth file or external URL starts.
The existing namespace, guardian and checked process-reaping protections remain.

One ephemeral native thread exists before installation. Its direct echo call
initially fails with the exact unknown-server error. Real plugin/install returns
exactly `authPolicy:ON_INSTALL` and an empty auth-app list. On the same thread,
echo then returns independently specified text, structured content, native-added
thread identity and false `isError`. The peer's independent bounded journal must
contain exactly one tools/call with the expected arguments and metadata.

The plugin-specific `disabled_tools=[hidden]` policy rejects hidden before peer
dispatch. Its journal remains unchanged. Native plugin/read reports the exact
MCP server; status attributes it to the ordinary plugin ID and reports connected
with the prescribed peer identity. No top-level MCP registration is introduced.

After real uninstall, echo fails again in that original loaded thread. The
installed catalog and cache are empty, source bytes unchanged and the journal
still has its sole echo call. A confirmed distinct native process repeats the
failure and empty catalog after cold startup. This tests durable capability
removal and runtime invalidation, rather than relying on an empty uninstall
response. Every started peer has exactly one exit journal row and disappears;
there are no turns. Namespace inode reuse after destruction is permitted, while
each live start independently proves parent isolation and native ownership.

## Physical owners and source

Exactly seven previously missing owners become scoped implemented, never fully
verified. All physical nodes were independently rehashed against experimental
JSON and checked by exact manifest ID:

| Schema | Pointer |
| --- | --- |
| `v2/PluginInstallResponse.json` | `/properties/authPolicy`, `/definitions/PluginAuthPolicy/enum/0` |
| `v2/PluginReadResponse.json` | `/definitions/PluginDetail/properties/mcpServers` |
| `v2/ListMcpServerStatusResponse.json` | `/definitions/McpServerStatus/properties/pluginId` |
| `v2/McpServerToolCallResponse.json` | `/properties/content`, `/properties/structuredContent`, `/properties/isError` |

The pluginId is nonnull and isError false only; no null/omission, result `_meta`,
error-result body, whole union, remote backend, model-mediated selection or
unrelated server policy is inferred. Registry/capability metadata grants no
Samgita authorization.

Immutable upstream anchors relative to `codex-rs/`:
`app-server/tests/suite/v2/plugin_install.rs:2460-2557` establishes same-thread
publication; `app-server/src/request_processors/plugins.rs:1540-1591,2010-2038`
refreshes install/uninstall; `core-plugins/src/loader.rs:982-995` applies policy;
`codex-mcp/src/connection_manager.rs:991-1021` rejects disabled dispatch;
`core/src/codex_thread.rs:1204-1220` refreshes a dirty MCP runtime before calls.

## Executed evidence and limits

The complete eight-file block passes **25/0 twice**, seeds501432/987654, under
`/tmp/samgita-native-goal-plugin-v5-20261024.py`, including this one native case.
Compile, format, Python AST, root strict Credo and executable-source guard pass.
Exact result/source hashes and the first failed namespace-inode oracle are
retained in [goal/control qualification](goal-control-qualification.md).
The implementation uses its own fixed stdio peer, not a fake Codex server.
Its test/peer SHA256 are respectively
`6e7a3510f1803aa558a1a04011e7ed3900007675f8cc5fcd2719138483bba8dc` and
`a28705ee5a69837f317129df1f1586240bfec064583762f635867eb89a04b858`.

CI gains a required explicit profile. Complete final-source package/platform/
hosted checks remain required. Real service/OS profiles, A11, source-unreachable
emitters and the complete goal remain incomplete; no release or deployment.
