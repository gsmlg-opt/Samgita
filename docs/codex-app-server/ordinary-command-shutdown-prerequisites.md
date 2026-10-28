# Ordinary command-source and shutdown-history prerequisites

Two remaining selective-history owners stay **missing** under official Codex
`rust-v0.163.0`, commit `83086188ae0614bd882818ff1aa23f3194962012`.
This is bounded source evidence, not a native success test, global non-emission
claim or change to the completion contract. Existing tests remain intact.
No security, permission, approval, authentication or sandbox test is run.

## A shell alias does not select the old Agent command source

Owner **5332** is
`v2/ThreadItemsReadResponse.json#/definitions/CommandExecutionSource/enum/0`,
literal `agent`, canonical node SHA256
`6cf85bf41d9570deed965109eed6c05c9512f6d79e321c70f3f3d900c8d06c74`.

The proposed ordinary route through a legacy model shell_type is closed by the
fixed source. [ConfigShellToolType](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/openai_models.rs#L310)
has only UnifiedExec and Disabled. The strings `default`, `local` and
`shell_command` are aliases of UnifiedExec, not selectors for an older runtime.
[Tool registration](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/spec_plan.rs#L1243)
registers the current ExecCommand/WriteStdin handlers. The
[ordinary launch](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/runtimes/unified_exec/launch.rs#L41)
explicitly supplies UnifiedExecStartup; public item conversion preserves its
source. The previous [persisted execution qualification](persisted-execution-items-qualification.md)
already records that genuine output and its corrected initial oracle.

This establishes only the supported model-configuration boundary. A type,
legacy consumer, different live start representation or spelling alias cannot
prove a native completed `agent` item. Global absence of every possible producer
has not been established. The prerequisite is a permitted genuine producer
that commits an actual completed command item with this source, followed by
original-ID selective-history readback. Injected ItemCompleted records, modified
native code and restricted interaction profiles do not satisfy it.

## Shutdown is possible, but the public subscription barrier is unresolved

Owner **5296** is
`v2/ThreadItemsReadResponse.json#/definitions/CollabAgentStatus/enum/5`,
literal `shutdown`, canonical node SHA256
`77ac1ea0dad495e5d50a989e7ccf7d19c1c2945cc2c8dfc2fbae0d9a9a482990`.

Ordinary sequential close returns a
[pre-close status snapshot](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/agent/control/legacy.rs#L54).
Shutdown flushes persistence, terminates and removes the child; the
[close item](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents/close_agent.rs#L67)
uses that earlier snapshot. The existing
[completed/close/notFound journey](collaboration-lifecycle-values-qualification.md)
is correct and remains unchanged.

A concurrent wait already subscribed to a running child can observe real
Shutdown: [ShutdownComplete conversion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/agent/status.rs#L9)
produces the final status, and the
[watch receiver](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/agent/control/watch.rs#L19)
retains it after removal. Interrupted remains nonfinal. Native
[wait completion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents/wait.rs#L221)
can persist the observed agents_states into a genuine completed tool item.
Therefore this owner must not be classified as globally unreachable.

The unresolved prerequisite is a public causal observation proving wait's
status subscription is installed while the child remains running, before close.
[Wait emits ItemStarted before subscribing](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents/wait.rs#L105).
That notification, an in-progress history item, a sent provider response,
elapsed time or a separate RPC is not an established subscription-ready ACK.
Closing after the early notification can instead yield notFound; waiting on an
already completed child yields completed. The source's direct in-process
subscribe-before-shutdown example is not public app-server acceptance.

Once a deterministic public ordering exists, a real completed wait item must
retain shutdown in canonical history and in the first selective read from a
distinct cold native reader, with the same call/thread/turn/child identities and
no additional execution. No timing-selected retries, sleep-based proof, testing
hook or fabricated terminal record is proposed here.

## Immutable evidence and scope

The report `/tmp/samgita-agent-command-shutdown-producer-20261029-report.md`,
SHA256 `fdb12b51b96fec047bbffc8bded3218b018f8dcbef80ee2b2421cb536b58b104`,
records exact anchors and eleven complete-file comparisons to the official
source archive, SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Selected causal full-file hashes:

| Source under codex-rs/ | SHA256 |
| --- | --- |
| `protocol/src/openai_models.rs` | `4b080aeaf5c158104e27d8277f3bc03ee3ad55b55a41c30a788d831fb2e2a99f` |
| `core/src/tools/spec_plan.rs` | `198432ab11c33b6509d72388ab04b7cb21de8ea500c7c0078b2921de14f7019e` |
| `core/src/tools/runtimes/unified_exec/launch.rs` | `75955d0786f92d1665a2ad9a21b0b4ebf4680c88df92c90042fd381eb5800d18` |
| `core/src/agent/control/legacy.rs` | `e5111e6fa1d44902a747fdeb4dada2ce0047d13cf69e6cf840e57d9a8eea70d6` |
| `core/src/agent/control/watch.rs` | `8de160e3e314ef4e51ce4a3c8383a3375d1204ab237ea0a25ad861ffa7d62dac` |
| `core/src/agent/status.rs` | `11dd75269d0cf2bd35697975c2878db28fb70e7584842a0d4aea198f7bd77d32` |
| `core/src/tools/handlers/multi_agents/wait.rs` | `51f07a8ce45180d5e7efc8b92a924969d9948350c7780326b70ab3f81b191221` |

Both owners keep their missing state and gain only these source limitations.
No runtime fixture, native success, transport coverage, whole-family evidence or
globally verified credit follows. No production code, schema, binary, timeout,
buffer, historical data or shared cleanup changes. Continue independent ordinary
behavior work; these prerequisites and the full goal remain incomplete.
