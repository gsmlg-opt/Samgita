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
## Successful Apps resource origins

The dedicated `native_mcp_resource_origin_profile.exs` runs immutable Codex
`rust-v0.163.0` with a private, loopback-only network namespace and synthetic
model/Apps MCP dependencies. The fixture produces model tool calls and backend
responses; only the official executable produces app-server frames. This is
actual-native local qualification, not real provider-account acceptance.

Two model-requested tools complete for different Apps/accounts. Subsequent
resource reads supply each original call ID together with deliberately
conflicting connector and target hints. Native Codex must use the successful
origin's app/account, return the exact original `originCallId` and HTML bytes,
and send the independently expected nested backend scope. A second native
thread, a future/unknown call, a mismatched URI and a missing thread produce
exact native errors without another model request, tool effect or backend read.
Complete started/completed items, structured results, explicit metadata nulls,
namespace isolation, idle state and owned-process reaping are also asserted.
The [pinned processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/mcp_processor.rs#L548)
defines the origin/target paths; the distinct model-free target path is qualified
separately below. A conflicting target being ignored does not itself qualify
target-driven selection or explicit `target: null`.

### Preserved failures and repairs

The first disposable run failed before native startup because the launcher
options omitted the required absolute `CODEX_HOME`. The next run reached both
tools but expected an omitted result `_meta`; the pinned `McpToolCallResult`
serializer emits `None` as null, so the exact expected map now includes null.
Safe method/path/source-line diagnostics then identified six rejected analytics
POSTs to `/backend-api/codex/analytics-events/events`. These were real background
requests from the native default analytics queue, not a resource-origin failure.
Every failed run stopped before positive origin-read acceptance; its later seed
remained unrun.

After two unsuccessful Sol repair/validation rounds, bounded recovery sets only
`analytics.enabled = false` in the isolated fixture. The supported
[analytics option](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/config/src/config_toml.rs#L534)
flows through configuration to
[queue creation](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/analytics/src/client.rs#L317),
which creates no queue for `Some(false)`. Routes, authentication, scope, bounds,
effects, cleanup and deadlines remain asserted. Disabling analytics here does
not qualify its enabled behavior. The disposable profile passes **1/0 twice**,
with **71,485 guarded files unchanged**, no additions or owned processes left;
each journal records three model requests, two tool effects, two scoped reads,
zero fatal events and native closure. Prior r1–r3 evidence stays preserved.

Initial original-checkout integration passes both complete native blocks but
fails strict Credo on nested test assertions. Extracting the unchanged
started/completed result assertions into two explicit helper clauses fixes the
finding; no assertion, deadline or dependency fixture is relaxed. The complete
three-file block (`mcp_direct`, origin profile, `native_apps`) then passes
**13/0 at each seed 501432/987654**, zero exclusions, with warning-free compile,
format, strict Credo, all **38 tooling regressions**, inventory consistency and
matching **1,503-file/executable guards**. The origin profile is a required
explicit hosted conformance step; final-source hosted success remains pending.

```sh
PATH="$PWD/.devenv/profile/bin:$PATH" ERL_FLAGS='+S 4:4' \
  python3 -B /tmp/samgita-native-mcp-origin-v43-r2-20261025.py
python3 -B /tmp/samgita-bind-native-mcp-origin-v43-20261025.py
python3 -B scripts/codex/inventory.py --check
```

Recovery: `/tmp/samgita-v43-origin-astra-recovery.json`, SHA256
`bdbbcdfbb0a6b1ae865b40a876fcc8c9760eb8b94469df8067da3581ba7d91d1`.
Source evidence: `/tmp/samgita-v43-origin-astra-source-evidence.json`, SHA256
`628da61ab2fd49d04b7f201d4c9992bb1160bbbf4c275ec4e97c4207fb744d1f`.
Exact owner/node audit: `/tmp/samgita-v44-mcp-resource-request-owner-audit.json`,
SHA256 `50e68d0744c957806e6c333e1046226d8f0c8cac4a7283e64ec2c36544c844ac`.
Integrated binding: `/tmp/samgita-native-mcp-origin-v43-terminal-20261025.json`,
SHA256 `1f4c3aa1603a8e22b18e636716cb8ee013e9c0a63a831d5d69b8fecbdae4627c`.

At this origin-only checkpoint, eight physical owners become implemented:
rows 4348–4352, 4354–4355 and 4367. Explicit target-null row 4353 remains missing.
Contracts become **4,442
implemented / 2,120 missing / 59 blocked**; requirements remain **462 implemented
/ 12 missing / 11 blocked**, with **zero verified**. Full final-source matrices,
real external/backend/OS success, source-unreachable emitters and A11 remain
incomplete. No tag, publication, production migration or deployment.

## Explicit target and null Apps resources

The separate `native_mcp_resource_target_profile.exs` qualifies the generic
model-free path with the actual immutable executable. Ten positive cases cover
threadless and current-thread reads crossed with target omission, explicit
target null, linked target objects, public no-auth target objects with null
`linkId`, and legacy connector-only filtering. Boolean-only driver-to-native
input observations prove that explicit target null remains present on the
actual wire, separately from omission. A fixed peer policy supplies literal
resource contents and independently checks flat target metadata and nested
legacy connector filters. Both channels remain independent; the native processor
does not invent precedence or an account for a legacy filter.

Ten invalid-target/thread guards reject before a peer read. Ten peer policy
denials retain exact code/message/data for wrong/unknown accounts, private
no-auth resources and conflicting filters. Two subsequent explicit linked reads
succeed without reusing a rejected scope. Those are synthetic backend policy
decisions, not native permission grants or Samgita project authorization.
Every run records **22 resource reads: 12 accepted and 10 denied**, with no
model, tool, command or turn execution. Route/body/journal bounds, absent MCP
credentials, private namespace and reaped native processes remain asserted.

The first disposable run passes these resource cases but fails its final
`thread/read(includeTurns: true)` on an unmaterialized loaded thread with native
`-32601`, `list_turns is not supported yet`. This failed profile and unrun second
seed stay preserved. Switching to legacy would not fix the prerequisite:
[the pinned negative test](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/tests/suite/v2/thread_read.rs#L1609)
also rejects an unmaterialized legacy thread. The supported
[empty-thread archive test](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/tests/suite/v2/thread_archive.rs#L293)
materializes empty history without a user turn. The repair performs one
acknowledged native archive of only its owned empty thread, then retains the
native `turns: []` assertion and adds exact `notLoaded` status. No database,
synthetic historical payload, timeout or existing resource assertion changes.

The repaired disposable profile passes **1/0 twice**, both fixed seeds,
with **71,571 protected files unchanged**, no additions or remaining processes.
Original-checkout integration passes all four complete owning files
(`mcp_direct`, origin profile, target profile, `native_apps`): **14/0 at each
seed 501432/987654**, zero exclusions. After the additional input-shape proof,
the whole block passes again, including warning-free compile, format, strict
Credo, **38 tooling regressions**, inventory and matching **1,505-file/executable
guards**. The target profile has its own required hosted conformance step.

```sh
PATH="$PWD/.devenv/profile/bin:$PATH" ERL_FLAGS='+S 4:4' \
  python3 -B /tmp/samgita-native-mcp-target-v45-r2-20261025.py
python3 -B /tmp/samgita-bind-native-mcp-target-v45-20261025.py
python3 -B scripts/codex/inventory.py --check
```

Source semantics: `/tmp/samgita-v45-mcp-target-source-audit.json`, SHA256
`035b23e01a53923e741f97e8bcc80a6d3b919459de87b8f0ba49c6b81cf5e0a3`.
Direct `ClientRequest` trace: `/tmp/samgita-v46-mcp-target-live-request-owners.json`,
SHA256 `b12e1267339193988e0bc10eb14a30e310656a67fd928fa64900010365f37da1`.
It resolves the method-selected native export at `/oneOf/78` and the Samgita
source supplement at `/oneOf/133` to identical target definitions; it does not
claim whole-document/index equality or sibling-schema inheritance.
Disposable result: `/tmp/samgita-v45-mcp-target-candidate/handoff-result-repair-1.json`,
SHA256 `4d6c45f98110cc9aaff156acf7069683517b2f64082b637575360f76fec548b1`.
Integrated binding: `/tmp/samgita-native-mcp-target-v45-terminal-20261025.json`,
SHA256 `ae2cab0f70371fc51acce127559d51952cc3e11eaa865bcd837ce1c7c6ae90a6`.

Exactly three physical owners become implemented: `ClientRequest` target fields
237/238 and explicit target-null row 4353. Eight already implemented resource
owners gain the separately qualified target evidence. Contracts are **4,445
implemented / 2,117 missing / 59 blocked**; requirements remain **462 implemented
/ 12 missing / 11 blocked**, with **zero verified**. Other values/transports,
real external/backend/OS success, analytics, A11, unreachable emitters and complete
final-source local/pushed hosted acceptance remain incomplete. No publication,
production migration or deployment.
