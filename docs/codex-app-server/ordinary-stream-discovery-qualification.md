# Ordinary stream gaps and native discovery contexts

This unit follows `e8de126` on existing `main`, continuing the complete
client/driver goal against stock Codex `rust-v0.163.0`. The source commit is
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`, and
archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
YOLO launch configuration is fixed fixture setup. No security, permission,
credential, authentication, authorization, approval or sandbox behavior is
tested. Audits, mixed broad suites and hosted workflows remain unrun under the
user's restriction; no retained test or acceptance gate is weakened.

## Stream gap with explicit history recovery

`native_ordinary_websocket_gap_test.exs` uses the actual owned native WebSocket
server. The synthetic local Responses provider emits one prescribed Unicode
delta and holds the rest behind an explicit control. The test observes that
native delta, receives `thread/unsubscribe:unsubscribed`, then explicitly
reconnects and initializes a new connection without resuming the thread.

The unsubscribe reply is the causal detach barrier. Releasing the provider
then produces a genuine global idle notification while thread-scoped turn,
item and delta notifications remain absent on the new connection. Explicit
read/resume/read returns the exact original completed paginated history. The
driver keeps its visible gap; history recovery does not invent delta replay.
Exactly one original turn and one provider request occur, with eleven typed
request/reply pairs and two initialized notifications across two generations.
Closing the borrowed client leaves the native listener alive until its owner
explicitly closes it and confirms process disappearance.

This qualifies controlled unsubscribe/reconnect. It does not establish physical
packet-loss recovery, ambiguous mutation-ACK reconciliation, cold-process
recovery or upstream execution deduplication. No automatic execution retry is
introduced. The pinned source distinguishes dropped scoped notifications from
pending server-request replay: `thread_processor.rs`, `thread_state.rs`,
`thread_lifecycle.rs`, `thread_status.rs` and `outgoing_message.rs` establish
the subscription, serial-listener, global-status and replay boundaries.

## Installed-app thread context

`native_ordinary_installed_thread_context_test.exs` first observes an empty
threadless installed cache using explicit null. It creates an ephemeral native
thread with its own cwd, then waits for the genuine MCP Ready notification.
Ready follows cache publication; neither thread/start success nor the fixture's
response-written record substitutes for this barrier.

Loaded-thread and explicit-null `app/installed` calls return independently
prescribed descriptive id/runtimeName data. A valid-shaped absent thread ID
returns the exact native `-32600` thread-not-found error. This ordinary lookup
control prevents a client that discards threadId from passing through global
cache data. Original JSONL bytes, integer/string correlation, eleven replies,
four native notifications, immutable inputs and confirmed cleanup are checked.
No turn, model request or MCP tool call occurs. Other computed app outcomes
remain opaque.

The existing installed-app fixture gains a separate profile limited to one
initialize/initialized/tools-list exchange and zero directory queries. Its
original profile's three-initialize/four-tools-list bounds remain unchanged,
as do every original installed-app test assertion. Only that test's fixture
SHA pin changes. The fixture SHA is
`e20306dd396d517a2f4f9bf75356052c442490b15f39c75d98a9e714ab19a706`.

## Genuine dormant child MCP connection

`native_ordinary_mcp_not_started_test.exs` warms an ordinary inert MCP tool
catalog through a native root Ready notification. A genuine generic child
inherits that environment/cache, completes the prescribed ordinary delegation,
and never calls an MCP tool. Independent completed root/child histories and
the provider's native wait result establish completion before the status read.

The child `mcpServerStatus/list` query omits serverName. Pinned production
`mcp_processor.rs` therefore performs separate temporary eager discovery while
reading the child's existing runtime status. The temporary peer returns
descriptive metadata; the child's actual connection remains `notStarted`.
Adding serverName could start a different path and is explicitly excluded.
The API detail selector is opaque setup; no authentication output is inspected.

The original reply is checked against this standalone enum's own bytes and
hash. Exactly ten native request/reply pairs, four synthetic provider requests
(three root, one child) and two inert MCP discovery peers occur. Each peer
permits only initialize, initialized and tools/list. Native/provider/peer
shutdown must be confirmed before scratch files can be removed. Existing
guardian contracts, deadlines, buffer limits and provider behavior remain.

Fourteen causal Rust sources were byte-matched against the pinned archive in
the source review, including connection-manager cache/runtime/status,
environment inheritance, child creation and request processing. The bounded
review artifacts are
`/tmp/samgita-ordinary-mcp-not-started-20261028-reviewed-v2-*`.
These source artifacts establish a production route; runtime evidence comes
from the repository tests, rather than a scripted native-status emitter.

## Active page, native interruption and first cold content read

`native_ordinary_active_page_recovery_test.exs` adds one completed ordinary
prefix and a second genuinely active turn. The provider finishes one assistant
message, starts a subsequent empty message and withholds the terminal response.
Observing that later native item/started is a serial-listener barrier after
the prior completed message's canonical and legacy reductions. A small explicit
descending full bootstrap page contains exactly the original active turn and
completed prefix, in order, without duplicate or omitted content.

The pinned live reducer gives ordinary active user/assistant items legacy
`item-1`/`item-2` IDs; its canonical paginated writer retains core/provider IDs.
The test independently asserts both representations, preserving thread/turn
identity and exact content. It does not normalize IDs locally to make the
representations appear identical.

Native interruption must acknowledge the original turn and emit its
interrupted terminal notification. Only then is the held provider handler
closed, without a provider terminal response. A native paginated includeTurns
read persists before projection. After confirmed warm-process shutdown, a
distinct native process's first content access is turns/list: its entire
interrupted/completed turn objects equal the durable warm objects. Loaded
thread inventories remain empty, and no cold resume or execution occurs.
Fourteen correlated requests/replies and exactly two original provider requests
are required, with no cold turn/item notifications.

The fourteen relevant Rust files were freshly archive-matched in
`/tmp/samgita-ordinary-active-page-recovery-20261028-handoff.md`, including
`thread_history.rs`, `thread_history_projection.rs`, thread lifecycle/processor,
turn interruption, event reduction and the live writer. This establishes
ordinary explicit-interruption recovery; genuine crash-tail normalization
remains a separate prerequisite. No new schema owner is promoted by combining
these already represented behaviors.

## Physical contracts and focused evidence

Only two previously missing physical owners gain scoped `implemented` evidence:

| Owner | Exact schema pointer | Canonical node SHA256 |
| --- | --- | --- |
| 3319 | `v2/AppsInstalledParams.json#/properties/threadId` | `22649c82b922402200147e8ee7d966cb548fcffa2852cd9e2f6e7d1fa1da8ad5` |
| 4225 | `v2/ListMcpServerStatusResponse.json#/definitions/McpServerConnectionStatus/enum/0` | `72e41c38bb91284167523b58c1765d474c64b1e10e58d026b4310c0feb2daa9f` |

IDs, pointers and hashes remain stable. Related existing method/lifecycle rows
gain explicit supplements; no alias, neighboring branch or globally verified
credit follows. Requirements remain **462 implemented /12 missing /11 blocked**;
contracts become **5,728 implemented /757 missing /136 blocked**, with zero
globally verified in either ledger.

The earlier three-case combination passed both seeds but failed strict Credo
on nested capture handling. Its retained evidence is
`/tmp/samgita-ordinary-stream-discovery-focused-20261028`; extracting the same
capture reduction passes the corrected v2 focused gate. The first four-case
MCP combination also passes data assertions at both seeds but fails strict
Credo on nested peer assertions. Extracting those unchanged assertions into a
helper corrects that finding without changing any rule, count or deadline.
The failed gate remains
`/tmp/samgita-ordinary-stream-discovery-mcp-focused-20261028`.

The corrected owning block passes **4/0 at seeds501432 and987654**, including
the retained installed-app case, then strict Credo. Command times are
6.466/6.365 seconds; all1,755 guarded source hashes remain identical.

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-stream-discovery-mcp-focused-v2-20261028.py
```

Evidence directory:
`/tmp/samgita-ordinary-stream-discovery-mcp-focused-v2-20261028`.
Results JSON SHA256:
`391d74719ff1e3f4fa19fa71005ce8a48384a9b53fa0d742e66842877aaa492b`;
source JSON SHA256:
`b83437743c380e5c787ba18eba937df434db4f5ce3cadae06c7224a1fa933316`.
These focused results precede manifest/runner integration and do not certify
the final combined source.

The first five-case active-page combination passes both data runs but fails
strict Credo on the new wire-inventory function's complexity. Extracting the
unchanged event inventory assertions addresses that finding without weakening
the rule. Failed evidence remains
`/tmp/samgita-ordinary-stream-recovery-focused-20261028`.

The corrected five-case block passes **5/0 at both fixed seeds**, followed by
strict Credo, in
`/tmp/samgita-ordinary-stream-recovery-focused-v2-20261028`. All1,757 source
hashes remain identical; command times are7.867/7.816 seconds. Results JSON
SHA256 is
`12fd0064ac3ca467850dd775cb63e1f930bc092343a70a7a6d131f32aa6ed897`;
source JSON SHA256 is
`02c813325a1224044f725e963ec0cf4bc3358998b72e3b7da6fa505d35605483`.

## Final combined-source functional qualification

The reviewed runner adds only these four cases to the separately counted
extension group, now ten cases. The original164-case command,320-second
bounds, all retained assertions and all other command selections are unchanged.
All **17 reviewed functional steps pass** against **1,757 identical guarded
source files**, fingerprint
`a27ef3170c908c9d5231848d9b8b940d72110258306dafec0a3a3d9532262ea3`.
Relative to the preceding frozen checkpoint,1,745 prior sources remain exact;
only the runner, manifest, installed fixture and its old SHA pin change, plus
eight new test/fixture files. No production runtime/cleanup source changes.

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-stream-discovery-final-20261028
```

| Final check | Actual result |
| --- | --- |
| Selected overflow/replay, seeds455834/501432/987654 | 3/0 each,16 discovered/13 excluded |
| Retained stdio cleanup cases | 4/0 |
| Preserved164-case group, both fixed seeds | 164/0 each;284.266/287.854 seconds command time |
| Separate10-case extension group, both fixed seeds | 10/0 each;16.385/16.687 seconds |
| Outside-umbrella actual-binary consumer | 1/0 |
| Inventory, driver/root compile and format, strict Credo, Dialyzer, assets | All pass |

Results JSON SHA256:
`565d12086c6c0c2a8c0c7ebc2597afc266b225a17190301a47dcb34692ba783e`;
source JSON SHA256:
`b0686d814e5e82e61c50511e317f3b980bb1372d238409170007295f9a387104`;
command-plan SHA256:
`e2968888d91187591a1f031e7aaef18c0efcce0c671db3aef109ccfd03419e2a`.
The main-group original logs have SHA256
`c6e05535c37ddeef369402481d9f590dca229ec953fffd4757d810ce1dbaa51a`
and `edb0c5e06f70e20da96c774a66bdbf177fc584b78072149a241ad1a35dbcdfb6`.
These are final combined-source functional results, not broad/security/hosted
or publication acceptance. No successful repeat proves the unknown earlier
intermittent cleanup cause. A separate source review finds no material issue;
its report is `/tmp/samgita-ordinary-stream-unit-review-20261028-report.md`,
SHA256 `3eb022bec5344d7b1840b5dd2e5c95578e8a5eb2062f61271753ee0ff93e30ac`.

## Continuing work and limits

The active bootstrap-page/interruption/first-cold-history case now has focused
runtime evidence. Further source review establishes a candidate for a genuine
process-crash tail: an active paginated includeTurns response must contain the
exact canonical inProgress turn/items after ordered native persistence. A
checked-owned process failure and first cold-page qualification remain unrun;
no authored rollout/SQLite rows can substitute. The report is
`/tmp/samgita-ordinary-crash-tail-barrier-20261028-report.md`, SHA256
`d2761166d8f9c83ae1d166921020313f6e2f76293e0c9d106b12923e649fdc3e`.
This candidate covers process failure, with no power-loss/fsync guarantee.

Owner4572's remote installed `marketplace.path:null` has a genuine producer
(`plugins.rs:2212-2228`), but adding plugin/installed to the existing lifecycle
would schedule background reconciliation and may add another installed GET.
`plugins.rs:853-857`, `manager.rs:1603-1627,1694-1738` and
`remote_installed_plugin_sync.rs:131-146` establish this side effect. The
original lifecycle/two-refresh inventory remains unchanged; owner4572 stays
missing. A separate scenario needs an independently observable native sync
completion boundary, beyond HTTP-send/disk/skill evidence. Both inspected
resume response constructors set nonnull collaboration mode; the separate
app-server executable's source flag does not qualify the combined pinned
binary, which uses VSCode. These narrowly scoped source findings are in
`/tmp/samgita-ordinary-remaining-producers-20261028-report.md`, SHA256
`d36996c863195f57c66732cf3511d84c609ab7d097b7cf1a4310e61d411215dc`.
They establish no global unreachability, native success or owner promotion.

A11's pre-emission instrumentation prerequisite, source-proven unavailable
legacy emitters, real external/backends/other OS success, prohibited checks,
full compatibility and publication/release gates remain incomplete. Successful
repetitions do not establish the original intermittent stdio-cleanup cause.
Existing Plug.Crypto2.2.1 locks, database recovery protections and confirmed
owned-process cleanup stay intact. No Samgita/PostgreSQL recovery, browser, audit,
hosted workflow, publication, Samgita service start or deployment is performed by this
unit. Package tests run without a Samgita Repo/platform, using only owned local
native processes and synthetic dependencies.
