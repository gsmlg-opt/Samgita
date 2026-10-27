# Complete original native MCP startup notifications

V440 strengthens the retained ordinary MCP startup test on the combined source
based on `76e0b1bfc738a7a0cba42d8b9831b9949f163a13`. Two separately named
local MCP dependencies, `owned_startup_alpha` and `owned_startup_beta`, each
remain held at initialize until an explicit release. Existing native RPC and
peer-journal barriers establish starting before release and ready afterward,
with zero inference. The peers produce MCP replies; stock pinned Codex produces
every app-server notification.

The test previously compared complete params to captured input but did not
check the full original envelope. It now requires exactly starting then ready
in both original capture and projected events, with the original initialized
generation, known notification kind and strict unique sequence. Each whole map
independently prescribes the method, genuine thread ID, literal peer name and
status, and explicit null error/failureReason diagnostics. Native emittedAtMs is
an integer within its own held-start or post-release host bracket. Original JSON,
direct Wire decoding and the projected event must equal that complete map; both
originals validate the canonical experimental ServerNotification schema.

The held starting capture remains exact after ready, and the selected pair
remains unchanged through existing native/MCP/provider cleanup. Per-profile RPC
and MCP inventories, release logic, fixed inputs, empty workspace, zero tool
execution/model requests, all deadlines/caps and checked owned-process/Port
cleanup remain. No new process, RPC, fixture, dependency or production driver
code is introduced. Fixed YOLO launch configuration remains.

Only four physical canonical owners gain scoped implemented evidence:

| Owner | Pointer in `ServerNotification.json` | Node SHA256 |
| --- | --- | --- |
| 2967 | `/oneOf/45` | `be18e58ed574051182fcfdd1b7eb5de6e0cdfdd77f8395bef6942c10fe06e303` |
| 2968 | `/oneOf/45/properties/method` | `a5e0518b2256238093e2f28db5f5290f712b280d780a0feb6b89c2d693b1d84d` |
| 2969 | `/oneOf/45/properties/method/enum/0` | `896e77cc278d314115f4b050d9e66ce92a68d22dd5bc04e7c9cea33624783faf` |
| 2970 | `/oneOf/45/properties/params` | `5cf6a40c78f974850f4eec5b42dcd9f6392d37d2accb818d17b20163c127fa63` |

Six whole native producer files match the immutable source archive.
`codex-mcp/src/connection_manager.rs:689–714,755–784` emits real Starting/Ready
updates around actual managed-client initialization. Native startup emission
and `bespoke_event_handling.rs:203–233` map those typed events to the genuine
thread/name/status and null diagnostics. The protocol binds their public method
`mcpServer/startupStatus/updated`; outgoing-message code adds native emission
time. This tests fresh local clients, not the reused-client shortcut.

Pin: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
All exact source/node hashes are in
`/tmp/samgita-v439-v440-binding/source.json`, SHA256
`cd4fbaaf9ea1e18b520e739205b5953fd14729252b7081fd3a28b7dc6433c6fa`.

## Actual checks and limits

The combined final matrix with the separate timeline enhancement passes all
nine commands: owning **4/0**, explicit ordinary block **51/0** at both
`501432` and `987654`, Python syntax, scoped format, warning-free driver compile,
root strict Credo, inventory consistency and the reviewed independent consumer
**1/0** against actual pinned Codex outside Repo/Phoenix/umbrella. The initial
timeline-helper complexity failure and unchanged-assertion extraction remain
recorded in [its qualification](realtime-timeline-ordinal-qualification.md).
No native/MCP failure is hidden by that correction.

Final commands and logs:
`/tmp/samgita-v440-functional-checks/final-after-split/results.json`, SHA256
`2f06079b8f15f6a89fe5e8f8dc524be2737222394ac732b009445fd2c34042fe`.
All 414 source hashes remain stable; 412 prior paths are exact and only two
tests change. Guard SHA256
`b93c23ca6ed50efd892de4f1aaefeeae5d65e886dec94628ff96efa898abd7f3`.
Final MCP test SHA256
`920afb77a1091a1e19759c32c16fc6a393eb9108c05fcce9d6a0b79a71fd6844`.
Binder `/tmp/samgita-v439-v440-bind.py`; evidence JSON SHA256
`35b538363e60b0ff476ca144e39d6891be22b20dc9859938ac65dc7767a1d825`.

Contracts become **5,242 implemented / 1,313 missing / 66 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both
ledgers. Failed/cancelled/threadless notifications, reused clients, remote MCP,
tool execution, reconnect and other OS/transports remain unqualified. No alias
or referenced payload receives blanket evidence. Security/permission tests and
audits, broad suites and hosted workflows remain unrun under the user's
restriction. A11, unreachable legacy, external/platform/full-goal and release
gates stay incomplete. No publication or deployment. Rollback reverts these
additional assertions and four evidence bindings, preserving runtime/history.
Continue the genuine paginated thread-revert notification and retained-prefix
readback profile.
