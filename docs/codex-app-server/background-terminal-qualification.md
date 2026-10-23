# Background terminal lifecycle qualification

Five local native scenarios pass with two seeds against the immutable target
below. The provider is an isolated deterministic fixture. This evidence does
not establish full Codex compatibility, hosted qualification, publication,
real provider integration or deployed behavior.

## Immutable target and boundaries

Target: Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

The explicit profile is
`apps/samgita_codex_driver/test/native_background_terminal_profile.exs`.
The owned model fixture is `scripts/codex/background_terminal_fixture.py`.
The profile must be invoked explicitly by the qualified private-namespace job;
its `*_profile.exs` name avoids discovery by a general test job with a different
namespace environment. Existing namespace preflight is mandatory. No fallback
to host networking is permitted.

The provider supplies deterministic Responses SSE. Native Codex handles
`exec_command`, `write_stdin`, background-terminal methods and every observed
app-server notification. This exercises core unified-exec. The separate
`command/exec` and `thread/shellCommand` paths are not substitutes and are not
called by this profile.

Native and provider processes have an owned disposable HOME, CODEX_HOME,
workspace, temporary directory and shell, inside a private Linux user/network
namespace with loopback only and no IPv4/IPv6 default route. Environment
inheritance is explicit. No existing provider credential, account, task,
platform database, external service or sibling repository is involved.

Only a fixed Python reader may execute. The launch argument vector and
working directory are checked before accepting each native launch approval.
The reader validates namespace, records its own OS PID, disables PTY echo,
never evaluates input, accepts only two fixed lines and has a bounded lifetime.
It requests Linux parent-death termination. Controller/native/namespace owner
and command PID disappearance are checked during cleanup.

The controller records its actual `sys.executable`; startup requires literal
equality with the test's approved `System.find_executable("python3")` path.
A mismatch fails before a command turn. Neither path comparison nor approval
matching canonicalizes or broadens to another interpreter.

`write_stdin_approval` remains true. Escalated fixed launches and nonempty
writes receive only exact one-shot `accept` replies. Stdin approval checks
the original item ID, current turn, actual native session ID, original
environment, distinct callback, no additional permissions and exact input
tokens. Unexpected requests fail. The negative case uses offered `cancel`,
which maps to core Abort and interrupts the current write turn. It does not
require a follow-up provider inference or model-visible tool rejection.

Native launch approval proposes an execpolicy amendment containing only the
owned shell path. The profile requires that exact suggestion but returns only
one-shot `accept`; it never selects an amendment or session-wide decision.
Stdin approvals must have no proposed amendment. A suggestion is not an
applied policy change.

## Executable observations

| Scenario | Expected observation | Runtime evidence |
| --- | --- | --- |
| Empty and validation | Empty list, clean submission ACK, absent terminate false; malformed IDs/cursor/params rejected; local and native experimental gates distinct | Passed both seeds |
| Two owned core sessions | Actual output-derived logical IDs; exact command/item/cwd; numeric ordering, limit zero -> one, cursor after removed anchor; per-thread ownership; targeted terminate leaves survivor | Passed both seeds |
| Clean | ACK followed by bounded empty-list and OS-process disappearance; repeat clean; no new command or model invocation | Passed both seeds |
| Cross-turn stdin | Original execution in A; Unicode input, live empty poll and final input in B; original item/session and current turn correlation; final interaction precedes command completion/exit zero | Passed both seeds |
| Cancel stdin approval | Current turn interrupted, no consumed input/interaction, original background reader remains; explicit terminate cleans it | Passed both seeds |

Session IDs are extracted from actual correlated native `function_call_output`
using the anchored line `Process running with session ID <integer>`. They are
cross-checked against list entries and item IDs. OS PID markers only prove
owned process lifecycle; they never supply protocol session IDs. There is no
assumed `1000` or other fixture-selected protocol process ID.

Pinned list responses always set `osPid`, `cpuPercent` and `rssKb` to null.
The tests assert those nulls; no resource measurement is claimed.

Clean `{}` proves submission of `Op::CleanBackgroundTerminals`, not synchronous
process reaping. Termination is established separately through bounded live
list checks and OS process disappearance. Repeat terminate false is asserted
only after initial execution has yielded and process removal is observed.

Native terminal interaction requires a real handler-supplied interaction
context and either nonempty stdin or a still-live response process ID. Empty
poll on a live process emits an interaction. The final nonempty write can emit
even when it ends the process. Its item ID belongs to the original exec call,
while its turn ID belongs to the current write turn.

## Pinned upstream source anchors

Paths below are relative to the immutable `codex-rs/` source tree.

| Behavior | Source |
| --- | --- |
| Experimental method declarations | `app-server-protocol/src/protocol/common.rs:749-766` |
| Background-terminal wire schemas | `app-server-protocol/src/protocol/v2/thread.rs:1222-1280` |
| Clean submission/list null mapping/terminate parsing | `app-server/src/request_processors/thread_processor.rs:2480-2541` |
| Numeric cursor semantics, zero limit clamp and removed-anchor test | `app-server/src/request_processors/thread_processor.rs:6635-6660`; `app-server/src/request_processors/thread_processor_tests.rs:39-95` |
| Clean/list/targeted core termination | `core/src/unified_exec/process_manager.rs:1822-1903`; `core/src/unified_exec/mod_tests.rs:340-389` |
| Actual logical session ID rendering | `core/src/tools/context.rs:524-547` |
| Explicit shell/login argv derivation | `core/src/tools/handlers/unified_exec.rs:97-123`; `core/src/shell.rs:24-36` |
| Original command retained as hook command | `core/src/tools/handlers/unified_exec/exec_command.rs:249,409`; `core/src/unified_exec/process_manager.rs:1863` |
| Actual write handler context and errors | `core/src/tools/handlers/unified_exec/write_stdin.rs:84-132` |
| Stdin process identity checks, TTY requirement and interaction emission | `core/src/unified_exec/process_manager.rs:899-1023,1074-1133` |
| Retained stdin authority/review condition | `core/src/unified_exec/stdin_approval.rs:185-253` |
| Native stdin approval argv and offered decisions | `core/src/tools/approvals.rs:691-725` |
| Heuristic policy suggestions and forwarding into launch approval | `core/src/exec_policy.rs:900-935`; `core/src/tools/runtimes/unified_exec.rs:172-185` |
| Accept/cancel enum and Abort mapping | `app-server-protocol/src/protocol/v2/item.rs:66-106` |
| WriteStdin enum and approval wire schema | `app-server-protocol/src/protocol/v2/item.rs:1540-1630` |
| Approval correlation and exact shell-joined command | `app-server/src/bespoke_event_handling.rs:690-827`; `core/src/session/mod.rs:2918-3006` |
| Interaction wire schema and production forwarding | `app-server-protocol/src/protocol/v2/item.rs:1500-1505`; `app-server/src/bespoke_event_handling.rs:1139-1146`; `app-server-protocol/src/protocol/event_mapping.rs:450-456` |
| Upstream interaction, live poll and final-input ordering tests | `core/tests/suite/unified_exec.rs:1510-1778,2380-2482` |

## Unqualified branches

The empty poll that *observes completed execution* emits no interaction in
pinned source (`core/tests/suite/unified_exec.rs:1820-1934`). It is explicitly
deferred here: a timing-only sleep or request to an already removed process
cannot establish that branch. A deterministic owned completion barrier needs
separate source approval before adding evidence.

This unit also does not qualify restart/reconnect preservation of live
terminals, signal/resize, CPU/RSS measurement, Windows/ConPTY, external model
inference or service integration. Passing generic driver tests would not
establish those behaviors.

## Local validation and repair evidence

The coordinating owner repeated this profile with all eight new MCP cases on
the reviewed current sources. Seeds `501432` and `987654` each passed **13 tests /
0 failures**, **39.0 seconds**, with native namespace preflight, independent
warnings-as-errors compile and focused format. Log:
`/tmp/samgita-native-mcp-background-parent-20261024.log`. Shared manifest
integration adds seven entries and 24 new positive contracts; nine prior approval
fields gain evidence. Three resource fields stay missing with null-only evidence.
CI now explicitly selects the profile; these local results do not claim hosted
success or full behavior coverage.

Validation on 2026-10-24 began at shared `main` checkpoint
`b592e829149bde647f9953c8950f91d289b38455` plus the three owned files. Final
checks completed with shared HEAD
`edeaecf838784c869a954a1caba2e249d121cef0`; intervening commits belong to
independent work. No worker Git action was performed.

Commands ran serially through `devenv shell --no-tui --`. Every Mix invocation
explicitly used `MIX_ENV=test`; no development build/dependency cleanup was
performed. From the repository root:

```sh
python3 -c 'import ast; from pathlib import Path; path = Path("scripts/codex/background_terminal_fixture.py"); ast.parse(path.read_text(), filename=str(path)); print("AST parse passed; fixture not imported")'
python3 scripts/codex/check_namespace_prerequisites.py
```

From `apps/samgita_codex_driver`:

```sh
MIX_ENV=test mix format test/native_background_terminal_profile.exs
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_background_terminal_profile.exs --seed 501432
MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_background_terminal_profile.exs --seed 987654
MIX_ENV=test mix format --check-formatted test/native_background_terminal_profile.exs
```

From the repository root:

```sh
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix credo --strict --files-included apps/samgita_codex_driver/test/native_background_terminal_profile.exs
```

Final results: non-importing Python AST, namespace preflight, both compile
commands and scoped formatting passed. Seed `501432`: **5 tests, 0 failures,
21.4 seconds**. Seed `987654`: **5 tests, 0 failures, 21.5 seconds**. Scoped
strict Credo found no issues. Each scenario's cleanup callbacks verified
disappearance of its recorded controller, namespace owner, native and command
PIDs before removing its disposable directories. A final process inspection
found no owned fixture or pinned native process; existing Codex app
infrastructure was left untouched.

The initial run passed the empty/validation case and failed the other four
before approving their first command: the test incorrectly required no
proposed policy amendment. Native returned the exact owned shell path.
Pinned `core/src/exec_policy.rs:900-935` explains the heuristic suggestion;
repair 1 requires that exact launch suggestion, keeps stdin suggestions null
and retains one-shot `accept`. Both seeds then passed (21.7/21.3 seconds).
Scoped strict Credo subsequently found the test loop's arity nine exceeded
eight. Repair 2 grouped thread/turn IDs into one tuple without changing
scenarios, assertions or deadlines; the complete final commands above passed.
Cumulative Sol repair rounds: 2; Astra repairs: 0.

Hosted workflow integration, aggregate manifest checks and broader release
gates remain the coordinating agent's responsibility. Do not infer those
results from this scoped local record or tag a build with missing applicable
gates.
