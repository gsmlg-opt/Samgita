# Direct MCP tools and resources

Five actual-Codex cases in
`apps/samgita_codex_driver/test/mcp_direct_test.exs` cover direct tool calls and
resource reads under both MCP `2025-06-18` and `2026-07-28`. The executable/source
are the immutable `rust-v0.163.0` pins in [qualification](qualification.md).
Codex starts an owned synthetic stdio MCP backend; the app-server is real.
The fixture has no network, resource filesystem access or command execution.

The actual MCP request journal proves negotiation. The modern profile needs
both `features.mcp_2026_07_28` and per-server
`CODEX_MCP_PROTOCOL_VERSION="2026-07-28"`; enabling the feature alone negotiates
the legacy protocol. Modern discovery uses `server/discover`, while legacy
discovery uses `initialize`. This correction was validated rather than counting
a legacy response as modern acceptance.

The cases require:

- Tool text, content metadata, structured content, nullable/empty arguments,
  `isError` and top-level metadata remain exact. Codex overwrites a caller's
  spoofed `_meta.threadId` with the loaded native thread identity while retaining
  other caller metadata.
- Resources retain text, binary/base64 bytes, MIME types and nested metadata.
  Threadless, null-thread and loaded-thread calls work. Connector metadata is
  forwarded to the local MCP server under the actual upstream shape.
- Native protocol errors preserve code, message and nested data in both
  versions. Unknown server/tool/thread, non-object arguments/metadata, orphan
  origin calls and invalid hosted targets retain their distinct error boundaries.
- Optional resource MIME/metadata may arrive absent or explicitly null at the
  MCP boundary; native typed serialization omits those keys. Text/blob bytes and
  distinct per-content URIs remain exact, independently of the requested URI.
- All five cases make zero model requests and start no turn. Direct notification
  delivery or a successful tool result cannot grant Samgita work acceptance.

Pinned source references, relative to `codex-rs/`:

- `app-server/src/request_processors/mcp_processor.rs:550-739`: direct dispatch,
  thread metadata, target/origin guards and error conversion.
- `rmcp-client/src/rmcp_client.rs:484-491` and `protocol_mode.rs:36-49`: explicit
  modern protocol selection. Upstream tests:
  `app-server/tests/suite/v2/mcp_2026_stdio_discovery.rs`.
- `app-server/tests/suite/v2/mcp_tool.rs:104,172` and
  `mcp_resource.rs:153,228`: native tool/resource profiles.

Original scoped compile with warnings as errors, formatting and **4 tests passed** at
each seed `501432` and `987654`. Logs:
the coordinator's combined protocol/goal/MCP check is retained at
`/tmp/samgita-native-timeline-protocol-goal-mcp-green.log` (9 tests passed,
seed `987654`). This is local two-version stdio
backend evidence. Hosted apps, event streams, OAuth, continuation, sandbox auth,
every content variant and other transport/platform profiles remain unqualified.

## Optional resource fields and distinct content URIs

The next additive case runs both negotiated versions and both threadless and
loaded-thread read paths. A synthetic MCP backend returns four prescribed,
ordered text/blob entries with distinct URIs. Each arm includes one omitted and
one explicit-null MIME/meta input. Exact native result equality requires all
four original URIs and text/base64 values, absent optional keys and explicit
null `originCallId`. Decoded binary bytes must be `0,1,127,128,255`.
The backend journal requires exactly four original request URIs; no model call,
turn, pending interaction or uncertain operation is allowed.

The [pinned ResourceContent serializer](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/mcp.rs#L296-L326)
maps absent/null options to None and skips them on output. The driver does not
remove fields or supply defaults; this is the unchanged native server's typed
MCP projection. Omission cannot qualify an emitted-null MIME/meta arm. Caller
supplied `originCallId` cannot establish app provenance; populated native origin
remains a distinct required journey.

The complete five-case file passes **5/0 twice**, seeds 501432/987654 with zero
exclusions, first in the ordinary isolated consumer and then in the original
checkout. No behavioral repair, changed deadline or removed assertion is needed.
An isolated post-run original-input guard detects the parent's subsequent
integration of the same two candidate files. That guard diagnostic is retained;
it is not reported as unchanged original source. Snapshot/candidate/prior
evidence remains unchanged. The separate original-checkout run validates those
exact integrated files with a matching **1,501-file/binary source guard**.

```sh
PATH="$PWD/.devenv/profile/bin:$PATH" ERL_FLAGS='+S 4:4' \
  python3 -B /tmp/samgita-native-mcp-resource-v42-20261025.py
python3 -B /tmp/samgita-bind-native-mcp-resource-v42-20261025.py
python3 -B scripts/codex/inventory.py --check
```

Warning-free compilation, format, strict root Credo, all 38 tooling regressions
and inventory consistency pass. Exact scoped commands, hashes and logs are in
`/tmp/samgita-native-mcp-resource-v42-20261025/`; terminal owner report:
`/tmp/samgita-native-mcp-resource-v42-terminal-20261025.json`, SHA256
`a723cb90343633f51b55f68e8c753a40a2715514aaa009c4930d0fd42086d387`.
Source audit `/tmp/samgita-v41-mcp-resource-gap-audit.json` has SHA256
`fef39bffe2def775b25f7096ccb7d64ab2ec225f7b11b99428cebb12e1565c51`.
The isolated execution and post-run guard record is retained under
`/tmp/samgita-v40-candidate-consumer-20261025/evidence/v42-mcp-r1/`.

Only seven physical text/blob/URI/content owners become implemented. Four
MIME/meta field owners and the populated origin field remain missing. Contracts
are **4,419 implemented / 2,143 missing / 59 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, with **zero verified**.
The complete final-source aggregate/profile/consumer/hosted matrix is still due;
this does not close A11, missing native emitters or real external/backend/OS
acceptance. No publication, production migration or deployment.

## Advertised progress notification has no discovered production emitter

The complete target retains `item/mcpToolCall/progress`. Exact pinned evidence:

Upstream anchors include the
[advertised notification](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L2013),
[classification-only reference](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/notification_media.rs#L99)
and [logging-only MCP progress handler](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/rmcp-client/src/logging_client_handler.rs#L63-L74).

| Source, relative to `codex-rs/` | Finding |
| --- | --- |
| `app-server-protocol/src/protocol/common.rs:2013` | Advertises `McpToolCallProgress`. |
| `app-server-protocol/src/protocol/v2/mcp.rs:333-338` | Defines `threadId`, `turnId`, `itemId`, `message`. |
| `app-server/src/notification_media.rs:99` | The sole app-server reference classifies an existing notification; it constructs none. |
| `rmcp-client/src/logging_client_handler.rs:63-74` | Incoming MCP progress only enters `info!`; this handler forwards no app-server notification. |
| `tui/src/app/thread_events.rs:920-921` | A construction exists only in a TUI test. Other TUI/test-client references consume notifications. |

A Rust source search across the immutable `codex-rs/` finds no production
construction of this notification. Generic MCP event-stream forwarding is a
different advertised operation and cannot substitute for this item-progress
contract. The manifest therefore marks this notification **blocked** for required
real-emission success, retains its schema contracts and keeps completeness
failing. Synthetic Session/codec evidence cannot satisfy native emission, and
neither an older/modified binary nor sending a mock progress event changes this
target's evidence. The requirement remains incomplete pending an explicit
upstream/evidence-policy resolution; no target exclusion is assumed.
