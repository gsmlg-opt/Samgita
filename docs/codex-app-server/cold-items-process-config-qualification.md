# Native cold items, process ownership and configuration projections

This continuation uses unmodified `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
All app-server responses, notifications, persistence and process behavior come
from that executable. Local peers supply prescribed model/MCP dependencies only.
No real account, remote backend, sensitive approval or production task is used.

## Observable behavior

| Owning test | Independent assertions and limits |
| --- | --- |
| `native_hook_lifecycle_profile.exs` | Stop continuation's exact HookPrompt and canonical timing survive warm and first cold selective reads. The distinct process reuses the same CODEX_HOME/config in a fresh private namespace. A rejection-only peer at the original origin journals every accepted TCP connection, unsupported HTTP method and request. Zero connections, original two provider requests and eight fixture/config/journal file hashes remain. Codex opens its database normally; this does not claim whole-store byte immutability. |
| `native_review_delivery_profile.exs` | The selected exitedReviewMode item has prescribed review text and exact native identity/times across warm and first cold reads; absence, duplicate IDs and wrong-turn selection retain their exact results. |
| `native_persisted_tool_items_test.exs` | A retained standalone string functionCallOutput has an independent full-item oracle, exact warm/cold entries and no extra inference. |
| `native_persisted_execution_items_test.exs` | Every command/MCP item member is compared with independently prescribed values. Only generated IDs/timing are observed and independently constrained. The command approval's synthetic start differs from the canonical stored start; they are not falsely equated. MCP starts retain canonical timing. Only the known JSON-text leaf is decoded; every other field and raw warm/cold equality remains exact. Optional `mcpAppResourceUri` is omitted, not null, and receives no owner promotion. |
| `native_persisted_mcp_variants_test.exs` | Real MCP success and `isError:true` results retain exact nonnull structuredContent and nested `_meta`, alongside distinct text content. The error case yields an MCP item with `status:failed`, a present result and null error, while its enclosing turn completes. The provider consumes the prescribed structuredContent. Exactly two provider requests, one MCP tool call/effect and native-owned peer ancestry/reaping are checked. JSON-RPC error.message, UI resources and nontext MCP results remain unqualified. |
| `native_persisted_tool_output_variants_test.exs` | Retained singleton text, text plus low-detail image and text plus high-detail image retain full original public items through first cold selection. Explicit-null and omitted namespace both serialize as public null and are omitted from provider output. The known 2x2 RGB PNG has an independent byte, CRC and pixel oracle. Low detail becomes the exact pinned provider placeholder; high detail preserves the small image. Injection does not resolve the pending dynamic tool. Reads produce no new tool request, turn or provider call. |
| `process_lifecycle_test.exs` | Actual child cwd, inherited environment, override and null-unset values are independently printed by owned Python children. A later spawn proves parent environment isolation. Omitted outputBytesCap retains exactly 1 MiB per stream; explicit null retains all prescribed additional bytes, with exact cap flags and no output deltas for buffered mode. Existing PTY, streaming, stdin, timeout and cap regressions remain. |
| `native_command_lifecycle_profile.exs` | Two borrowed UDS connections use the same processHandle for distinct native children. Valid cross-owner controls fail, binary stdin effects remain separate, and reconnect reaps only the old connection's child. No automatic respawn occurs. Explicit fresh spawn gets only the new generation's events; the other child and borrowed native server/socket remain. |
| `native_queue_lifecycle_test.exs` | All 100 prescribed queue records have distinct native IDs and exact ordered inputs/client identities. The 101st request returns the exact capacity error, preserving every accepted record. A distinct native process retains that queue without loading/executing the thread. |
| `native_config_option_projections_test.exs` | Metadata-only config/read scenarios cover null/absent and selected reviewer, login method, workspace string/list/empty list, compaction-scope, sandbox and search values. The reviewer input alias normalizes canonically. No auth, search, reviewer execution, compaction or sandbox-enforcement success is inferred from metadata. |

Pinned source boundaries include:

- `app-server/src/lib.rs:1238–1251`: initialize response can be followed by a
  genuine remote-control status notice; response completion is not notification
  exhaustion. `app-server-protocol/src/protocol/common.rs:1180–1184` defines its
  independent status read parameters as `Option<()>`.
- `app-server/src/request_processors/process_exec_processor.rs:82–139,290–360,427–453`:
  output-cap defaults, connection/handle ownership and disconnect cleanup;
  `utils/pty/src/lib.rs:25` supplies the 1 MiB default.
- `thread-store/src/queue_store.rs:89–115`: transactional queue capacity check.
- `core/src/image_preparation.rs:35,298–335,387–445`: exact unsupported-low
  placeholder and model-facing image preparation, separate from stored input.
- `app-server-protocol/src/protocol/v2/item.rs:264–270,906–911`,
  `app-server-protocol/src/protocol/thread_history_projection.rs:78–84`,
  `app-server/src/request_processors/thread_processor.rs:3155–3177,3622–3669,6173–6185`
  and `thread-store/src/local/thread_history.rs:433–479,529–545`: public item
  conversion, selection and durable retrieval. Cold cases make their first
  content access through thread/items/read, without resume or hydration.

## Failed oracles and corrections

The initial combined run had 101 tests and one failure: the new process-owner
test assumed initialization left no queued notice. The source-backed repair
waits for exactly remoteControl/status/changed, validates its full four-field
status and compares an independent status/read. It uses the existing five-second
observable deadline. The next run failed because the new read supplied `{}`;
the pinned `Option<()>` contract requires null. Correcting that input yielded
101/0 at both seeds. No driver, process cleanup or timeout behavior changed.

The first four-case MCP/content-array run failed one provider oracle. It
incorrectly expected low-detail bytes to bypass native image preparation. The
corrected test retains low detail as an explicit negative preparation case and
adds a distinct high-detail positive case. Public original-input assertions stay
exact. No sleep, deadline increase, assertion removal or retry-until-green is used.

The cold peer's initial fixture preflight missed connect-only activity. Its
server now journals acceptance before HTTP parsing. The corrected independent
control records three connections and one supported request across unsupported
method, connect-only and GET inputs. Native cold reads record zero connections.
This control qualifies the helper's oracle, not Codex or A11 confidentiality.

## Commands and scoped results

Run with immutable CODEX_BINARY in the repository's Devenv environment. The
five new MCP/array cases pass **5/0 at 501432 and 987654**. The complete 15-file
owning block, including existing image-preparation regressions, passes
**115/0 twice**, in **137.8/134.4 seconds**. It includes the ten owning files
above plus method_families, native_turn_steering, tool_output,
server_interactions and image_preparation tests. No case is excluded.

Root and driver warnings-as-errors compile, changed-file formatting, namespace
preflight and strict Credo across **437 files** pass. The **1,488-file** source
guard includes the unchanged baseline manifest and matches before/after tests.
Commands, exact source hashes, logs and results are retained in
`/tmp/samgita-native-cold-process-queue-v{3,4-focused,5-focused,6-owning}-20261025/`
and the matching Python runners. The terminal v6 summary is
`/tmp/samgita-native-cold-process-config-v6-terminal-20261025.json`, SHA256
`dab5948f3bcac54641703654b96c473d0e4cc53a6b3a46ba96f6dc7dde95e44c`.
Initial failing logs are retained, not replaced by later successful runs.

## Manifest mapping and continuing gates

Only exact physical properties/variants gain scoped implemented evidence:
8 HookPrompt/Stop notification owners, 20 retained process/queue owners,
4 actual process-input owners, 22 config metadata owners, 18 command-item
owners, 27 MCP-item owners, 5 review-exit owners, 8 string-output owners,
2 MCP-failed enum owners and 13 selected content-array/image owners: **127**.
Four MCP metadata fields gain nonnull depth and existing array/namespace/image
rows gain additional cases without another count. Null-only plugin/UI/error
fields do not qualify their nonnull alternatives. Structural reference wrappers,
omission-only URI fields, equal hashes, aliases and other schemas are excluded.
The manifest carries each exact ID, pinned subtree hash and owning test range.

No row becomes verified. Broad lifecycle, external backend/account, other OS,
source-unreachable legacy and A11 gates stay incomplete. Final combined-source
package/consumer, retained-database and exact-head hosted checks remain required;
the historical v20 matrix cannot qualify these executable additions. No release,
publication, deployment, production migration or sibling-service change occurs.
