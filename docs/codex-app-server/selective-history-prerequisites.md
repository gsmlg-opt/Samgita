# Remaining selective-history producer prerequisites

This source-only audit targets official Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`. All ten physical owners below
remain **missing** under `v2/ThreadItemsReadResponse.json`. No new runtime,
transport, alias or whole-method acceptance is assigned.

| Owner | Definition/value | Remaining boundary |
| --- | --- | --- |
| 5296 | `CollabAgentStatus.shutdown` | Genuine status/wait conversion exists; deterministic ordinary public observation is unresolved. |
| 5303-5306 | `CollabAgentTool`: sendMessage,followupTask,interruptAgent,listAgents | Stock V2 private analytics and public activity/output have distinct producers. |
| 5310 | `CollabAgentToolCallStatus.interrupted` | Private dropped-call analytics is not a public completed-item producer. |
| 5332 | `CommandExecutionSource.agent` | Ordinary execution supplies other sources; established presentation assignments are in excluded profiles. |
| 5335 | `CommandExecutionSource.unifiedExecInteraction` | Existing source evidence finds no stock assignment; terminal interactions are a distinct event. |
| 5339 | `CommandExecutionStatus.declined` | Prohibited by the current verification restriction; not a technical impossibility claim. |
| 5483 | Completed web-search `action:null` | Ordinary null is start-only; inspected completion producers supply a concrete action. |

## Persistence does not create producer evidence

The selective reader calls `ThreadStore.list_items` and converts stored entries
without overlaying the live full-history builder (`thread_processor.rs:3622-3672`).
The projection consumes actual `ItemCompleted` values and ignores unrelated
ResponseItems (`thread_history_projection.rs:78-87`). Canonicalization preserves
supplied completed items apart from their thread binding, and legacy conversion
copies supplied source/status (`rollout_migration/canonicalizer.rs:231-238`,
`legacy_event.rs:270-289`).

Therefore native readback, imported/canonical retention and inherited/forked rows
can all work without establishing the original stock producer. Those behaviors
keep their existing evidence. They cannot manufacture any missing literal above.

## Shutdown is representable; the ordinary observer barrier is unresolved

Genuine ShutdownComplete becomes AgentStatus::Shutdown and public shutdown/null
state (`core/src/session/handlers.rs:389-398`, `core/src/agent/status.rs:21`,
`protocol/v2/item.rs:1328-1331`). An already registered wait observer can preserve
that final status after the runtime disappears. No global unreachability claim
is justified for5296.

The actual order in `core/src/tools/handlers/multi_agents/wait.rs` is decisive:

1. Lines105-121 emit/await the public started item, with empty agent states.
2. Lines123-127 enter the subscription loop and await actual registration.
3. Lines128-135 consume its initial snapshot. Earlier removal maps to NotFound
   at144-145. Other subscription failures emit their separate completion/error
   at147-167.
4. Lines172-204 await final states or deadline; only206-237 constructs/emits
   the final result. A completed timeout ends that observer.

Receiving the started item therefore does not establish registration. Actual
watch registration occurs at `agent/control/watch.rs:26`; its final-snapshot
retention after removal is explicit at39-45. A late observer cannot inherit it.

Normal close captures the earlier status before shutdown
(`agent/control/legacy.rs:54-73,94-104`), waits for termination, then removes the
runtime/residency/registry/mailbox (`29-44`). Its completed close item uses that
earlier snapshot (`close_agent.rs:68-105`). The existing close→wait/notFound
journey consequently does not qualify shutdown. A same-root batch is not a
concurrency barrier either: v1 wait/close inherit false parallel support, and
the executor takes its exclusive gate (`tools/src/tool_executor.rs:122-124`,
`core/src/tools/parallel.rs:213-217`).

The official internal test at `multi_agents_tests.rs:3422-3466` uses direct
`Op::Shutdown` and a held status receiver. That is source evidence for genuine
status handling, rather than an executable public app-server scenario. Before
adding a native test, establish a supported ordinary sequence that registers a
wait observer before shutdown, or retains a shutdown runtime for later public
observation. A sleep, favorable race, retry-until-selected result, scripted frame
or modified upstream runtime cannot supply this barrier. No confirmed upstream
defect follows solely from the unresolved oracle.

## Other producer boundaries

Ordinary command launch/watchers supply UnifiedExecStartup and user-shell tasks
supply UserShell (`runtimes/unified_exec/launch.rs:44`, `process_manager.rs:591`,
`async_watcher.rs:367,427`, `tasks/user_shell.rs:201,279,303,344`). The completion
event preserves its supplied source (`tools/events.rs:584-600`). Agent is also
a declared default and can be copied from legacy data; those facts are decoder
and retention evidence. Established explicit app-server Agent presentation
assignments belong to excluded outcomes (`bespoke_event_handling.rs:338,392,771`).
They are not repurposed for an ordinary5332 test.

The [public/private projection boundary](native-projection-boundaries.md) and
[collaboration source record](prediction-and-collaboration-source-boundaries.md)
remain applicable to5303-5306/5310/5335. Direct V2 analytics inspection confirms
private ToolCallAnalytics terminal states; public message/followup/interruption
effects use different activity/output. No equal-value or inherited-row credit
is assigned to the missing persisted enums.

For5483, `ext/web-search/src/tool.rs:130-145` emits None on start, while162-186
derives/emits Some(action) on completion. Legacy end conversion copies that
completed action. Existing streamed/standalone search cases retain their exact
start/completed distinction; authored null completed items would be retention
fixtures, not stock completion production.

## Source evidence and limits

The generated experimental read-schema SHA256 is
`6fb3b1feeb9c94ff982e6b69de8d78a3881c6adbe93d9a9b504204d1dc5881d2`;
no standalone archive JSON member is claimed. Archive SHA256 is
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
These decisive complete files freshly match their extracted/archive bytes:

| File relative to pinned `codex-rs/` | SHA256 |
| --- | --- |
| `core/src/tools/handlers/multi_agents/wait.rs` | `51f07a8ce45180d5e7efc8b92a924969d9948350c7780326b70ab3f81b191221` |
| `core/src/agent/control/watch.rs` | `8de160e3e314ef4e51ce4a3c8383a3375d1204ab237ea0a25ad861ffa7d62dac` |
| `core/src/agent/control/legacy.rs` | `e5111e6fa1d44902a747fdeb4dada2ce0047d13cf69e6cf840e57d9a8eea70d6` |
| `app-server-protocol/src/protocol/v2/item.rs` | `e3ca6b9b880d815a16ff956b701beb9690abc222fb70a5b7e697e1c0ff91e099` |

The complete scoped report, including every exact pointer/node hash and prior
test/source references, is `/tmp/samgita-ordinary-thread-items-next.md`, SHA256
`874da72bf0e18626864e9f7326198bd01779a843dbf8e824263b4ac65721f53f`.
Other cited sources were read at the extracted pin and retain their separately
recorded earlier bindings. This review executed no native/functional/security/
permission tests, audits or external calls. No row is silently made blocked or
complete. Required producer qualification and full compatibility remain open.
