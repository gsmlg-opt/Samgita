# Ordinary child/tool hooks and native control correlation

V495–V499 extend the permitted ordinary functional selection on `main`, based
on `b550077`. The executable is unchanged official Codex `rust-v0.163.0`,
source commit `83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Local Responses peers supply model items only; all app-server messages and
process effects come from stock Codex. This is scoped implemented evidence,
not complete compatibility, external provider or production acceptance.

## Ordinary child hooks

`native_subagent_hook_test.exs` creates one real MAv2 root and one child with
four finite model responses. The provider holds the child response after the
actual SubagentStart command has recorded its genuine stdin. Before release,
the driver must receive both original Start notifications and the root's next
model request. A separate parent-scoped `thread/list` resolves the child's UUID.
After release, both root and child terminals are required. The child's causal
chain is turn start, Start pair, completed assistant item, Stop pair, turn end.
Native child history, parent activity and the exact returned child answer are
checked independently; parent completion alone cannot prove child delivery.

Two exclusive command records retain native session/agent/turn/cwd/model fields
and distinct exited PIDs. **The session ID belongs to the root; the agent ID and
notification thread ID belong to the child.** `core/src/session/session.rs:663–670,
946–952` explicitly separates those identities. `core/src/hook_runtime.rs:151–160,
449–460,1055–1062` supplies them independently. The root identity is bound to
its preceding real model request, and the child to the independently queried
thread and actual provider metadata. Complete started/completed maps preserve
native run labels, source/order/scope, times, duration, status and empty entries.
Original ingress bytes, schema, generation and cardinality are checked again
after query/drain. Unchanged invocation records and exited owned PIDs are
checked again after owned-process cleanup.

The first draft incorrectly equated root session and child agent identities.
Its native **2-test/2-failure** run is retained at
`/tmp/samgita-v495-v496-focused-501432.log`; the bounded diagnostic is
`/tmp/samgita-v495-v496-diagnostic-501432.log`. The correction preserves exact
identity equality against the appropriate independent owner; it does not relax
to nonempty strings, invent a child or alter native source. The initial source
reviews missed this distinction; the final source review corrects that finding.

Production ownership also includes `core/src/tools/handlers/multi_agents_v2/spawn.rs`,
`core/src/agent/control{,/spawn}.rs`, `core/src/session/{session,turn}.rs`,
`hooks/src/events/{session_start,stop}.rs` and the native child-listener path in
`app-server/src/{lib.rs,request_processors/thread_processor.rs}`. Startup listener
attachment is asynchronous; actual receipt is required rather than assumed.

## Ordinary tool hooks

`native_tool_hook_test.exs` runs one finite native `exec_command` with inert
PreToolUse/PostToolUse commands. The pre record must exist before execution;
only the actual command shell writes the exact Unicode printf file/stdout.
The post hook verifies that effect and its native `tool_response`. Three
provider requests and a normal continuation prove native consumption of the
function result and retained history. The command PID and both hook PIDs must
be distinct and gone; exclusive records and effect bytes survive cleanup.

Full original hook, command-item and turn envelopes retain exact IDs, times,
payloads, `itemsView` and final summary. A finite stored command can publish its
completed item through an independent watcher. The observation therefore waits
positively for that item, all four hook notices and the turn terminal, and checks
each native causal chain without inventing an order between watcher completion
and PostToolUse. `tools/registry.rs:701–837`, `hook_runtime.rs:188–329`,
`tools/handlers/unified_exec/exec_command.rs:506–518`,
`unified_exec/{process_manager,async_watcher}.rs` and
`hooks/src/events/{pre_tool_use,post_tool_use}.rs` own those behaviors.

The first draft's terminal turn expected `notLoaded` with empty items. Stock
Codex supplied the final assistant message, so the corrected complete expected
map requires `summary` and that exact message. Required item timestamps,
original bytes, native effect assertions and all deadlines remain intact.

## Original user-input status and process control IDs

`native_search_input_wait_test.exs` retains its ordinary Plan-mode question,
opaque response, selected answer, two-turn history and cold read. Before
answering, it now positively awaits both the real input request and original
`thread/status/changed` with exactly `activeFlags: ["waitingOnUserInput"]`.
It requires no order between the independent producers. An independent bounded
raw status ledger binds the full delivered envelope, generation, known thread,
timestamp interval and unchanged original bytes across both closed sessions.
Native `request_user_input.rs:45–151`, `bespoke_event_handling.rs:829–874` and
`thread_status.rs:201–220,270–289,354–461` provide the actual producer chain.

`native_command_control_values_test.exs` and `native_process_values_test.exs`
retain their existing real kernel PTY dimensions, exact stdin/stdout/files,
selected termination and vanished-PID checks. Their successful-send capture now
retains original request bytes; ingress capture records original native responses
before Session decoding. Exactly one request and response must preserve each
selected numeric/Unicode ID and its type, including a negative command ID.
The entire request validates against the pinned experimental ClientRequest
document; the complete native control reply must equal `{id: original, result:
{}}`. Successful receipt does not substitute for command effects or process exit.
There are no additional native controls, processes, turns or model requests.

`app-server-protocol/src/rpc.rs:13–21` admits string/signed-i64 IDs;
`app-server/src/message_processor.rs`, `request_processors/{command_exec_processor,
process_exec_processor}.rs`, `command_exec.rs` and `outgoing_message.rs` preserve
the typed original ID through the real control handler and reply route.

## Evidence and limits

Exactly ten physical contracts gain scoped implemented evidence:

| Owner | Demonstrated value/operation | Owning test |
| --- | --- | --- |
| 2217/2218 | subagentStart/subagentStop | native_subagent_hook_test.exs |
| 2207/2211 | preToolUse/postToolUse | native_tool_hook_test.exs |
| 2469 | waitingOnUserInput | native_search_input_wait_test.exs |
| 1049/1054/1059 | command write/terminate/resize request ID | native_command_control_values_test.exs |
| 1074/1079 | process kill/resizePty request ID | native_process_values_test.exs |

No shared type, alias, enclosing request or whole-method promotion follows.
The ledger becomes **5,464 implemented / 1,041 missing / 116 blocked contracts**;
requirements stay **462 implemented / 12 missing / 11 blocked**, zero verified.

In the pinned Devenv Elixir1.18.5/OTP27 environment, the first four owning files
pass **5/0** at seeds501432/987654; process values passes **3/0** at501432.
The initial strict-Credo failures (complexity, nesting and arity) are preserved
in `/tmp/samgita-v495-v496-strict-initial.log` and
`/tmp/samgita-v495-v498-functional-987654-credo.log`. Extracted helpers preserve
every assertion, map and bound. The corrected block passes **5/0** and full
strict Credo in `/tmp/samgita-v495-v498-refactored-501432.log`.
The final combined-source command is:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py \
  --output /tmp/samgita-ordinary-v495-v499-qualified
```

All **14/14** reviewed commands pass: **59 files / 109 actual-native cases**
at both seeds501432/987654 (186.4/185.8s test times), all three selected
WebSocket cases at455834/501432/987654, outside consumer **1/0**, inventory,
driver/umbrella warning-free compile, scoped/root format, strict Credo,
Dialyzer and assets. All **1,676** source hashes are unchanged; fingerprint
`551a8b4e6cabc49ac41355d0141baa022130bdec13bbc70690cf19f5ae62ce37`.
This also closes the earlier compaction/SessionEnd helper-correction matrix
checkpoint. No prohibited or hosted checks are part of this selection.

| Final record | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-v495-v499-qualified/results.json` | `28e4ef1fdfa3a984cbced6160c36af77830e356d9f2715bc19b377a9bf364a1a` |
| `/tmp/samgita-ordinary-v495-v499-qualified/source.json` | `b46ac1ba5f10f0f67369ebcd98a3f9be34cb3e67e6a72122413e785b5179f6ed` |
| `/tmp/samgita-v495-v499-binding/source.json` | `2f95e39ebd6f1fbe8b9fb41e844fd2c36f53a39dde0cf70d6da92d786e2f0d74` |

The binding checks **73 complete immutable producer files**, ten exact
canonical schema nodes and final owning test/fixture/helper bytes against the
unchanged final source. The integrated source review's one documentation timing
correction is incorporated: original frame comparison precedes shutdown;
invocation-record and owned-PID checks repeat after shutdown. No runtime
assertion was changed to satisfy that wording.

The new hook cases retain60s case/20s journey/5s observations,1s inert hook
timeout,128 frames/events,2MiB capture,64KiB incoming frame/hook stdin/journals,
8KiB outbound,1MiB provider request and4KiB process records. The held child
response has the original10s finite gate and release-before-join cleanup.
Command capture retains16x4KiB outgoing plus16x4KiB/64KiB ingress; process
capture retains32x4KiB outgoing plus32x4KiB/128KiB ingress. Status capture is
16x64KiB/1MiB. Overflow fails explicitly. No assertion skips, retries, sleep
or timeout increases obtain success. Existing stdio completion/reaping and
verified native/provider/command identity checks remain unchanged.

YOLO is fixed positive setup. No security, credential, authentication,
authorization, permission or approval test/audit, broad suite or hosted workflow
runs. Those retained gates are unrun/incomplete, and pushes suppress automatic
CI. A11, source-unreachable legacy producers, remaining hook modes/faults,
external/OS profiles, full compatibility and release remain incomplete. No
publication, deployment, live credential or database change occurs. Rollback
removes this test/fixture/evidence unit without changing persisted data.
