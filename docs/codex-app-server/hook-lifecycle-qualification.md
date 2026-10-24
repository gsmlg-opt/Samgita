# Native hook lifecycle qualification

Six actual-binary cases pass at seeds `501432` and `987654`, 9.6/9.8 seconds
after the configuration and static-check corrections below. Python AST,
namespace preflight, warnings-as-errors compile, format and strict Credo pass.
These are selected native synchronous hook observations; complete compatibility,
external integrations and A11 remain incomplete.

Target: Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
## Implementation scope

| Component | Repository path |
| --- | --- |
| `isolated_hook_lifecycle_fixture.py` | `scripts/codex/isolated_hook_lifecycle_fixture.py` |
| `native_hook_lifecycle_profile.exs` | `apps/samgita_codex_driver/test/native_hook_lifecycle_profile.exs` |
| `hook-lifecycle-qualification.md` | `docs/codex-app-server/hook-lifecycle-qualification.md` |

The installed profile resolves its fixture relative to the repository. CI selects
it explicitly. No runtime driver API or native schema is changed by this unit.

## Exact source contract

All paths below are relative to the pinned `codex-rs` source checkout.

| Source | Consequence |
| --- | --- |
| `features/src/lib.rs:1345-1350` | The stable default-on feature key is `hooks`; the draft explicitly enables it. |
| `hooks/src/engine/discovery.rs:660-735,800-821` | Native discovery computes keys/current hashes, enabled state and trust. Exact current hash approval is required; disabled or untrusted ordinary hooks are excluded. |
| `app-server/tests/suite/v2/hooks_list.rs:386-429`; `thread_goal_empty_responses.rs:122-133` | The native `hooks/list` metadata can be reviewed and written as `hooks.state.<key>.trusted_hash` through `config/batchWrite`, with reload, before a new thread starts. |
| `core/src/session/mod.rs:5438-5471` | Session hook configuration retains normal trust, feature, source and selected-shell gates. Hook shell arguments derive with `use_login_shell=false`. |
| `core/src/hook_runtime.rs:128-177`; `core/src/session/turn.rs:333-335` | Pending SessionStart hooks run on the first actual turn. A listed or newly created thread is not execution evidence. |
| `core/src/hook_runtime.rs:677-701`; `hooks/src/events/user_prompt_submit.rs:83-112` | The user prompt reaches the hook as serialized stdin, including native session/turn IDs. It is not a shell command. |
| `core/src/hook_runtime.rs:875-927` | Only non-builtin synchronous runs emit public started/completed lifecycle events. Async execution does not qualify this pair. |
| `app-server/src/bespoke_event_handling.rs:1147-1165` | Native core events map to actual app-server `hook/started` and `hook/completed` with native thread ID, optional turn ID and converted run. |
| `app-server-protocol/src/protocol/v2/hook.rs:96-171`; `v2/shared.rs:26-53` | Public run fields and enums use camelCase, including `sessionStart`, `userPromptSubmit`, `running`, `completed`, `blocked`, `failed`, `stopped`. |
| `hooks/src/engine/mod.rs:155-168`; `dispatcher.rs:80-104,230-265` | Run identity is deterministic from event label, display order and source path. Preview/completion timestamps are sampled separately; the draft does not require equal startedAt values or globally unique run IDs. SessionStart scope is thread; UserPromptSubmit scope is turn. |
| `hooks/src/events/user_prompt_submit.rs:138-250` | Exit 0 `{}` completes; exit 2 plus nonempty stderr blocks; exit 7 fails without blocking model continuation; valid `continue:false` stops processing. Output entries distinguish feedback, error and stop. |
| `core/src/session/turn.rs:379-390,950-980` | A blocked/stopped sole user input returns before inference. Failure without a control effect can continue. Hook status does not imply Task acceptance or any platform transition. |
| `hooks/src/engine/command_runner.rs:214-318,385-433` | Native executes configured shell commands with serialized stdin, bounded hook deadline and captured output; hooks are not ordinary model-tool sandbox requests. Explicit fixed scripts and namespace confinement are therefore necessary for this fixture. |
| `app-server/tests/suite/v2/plugin_reconcile.rs:111-115,231-277` | Upstream tests distinguish hook registration from actual turn-driven hook execution and started notices. This draft uses user config only; it does not claim plugin-reconcile behavior. |

## Observed six-case behavior

Each case creates an exclusive cryptographically named scratch root, fresh native
process, isolated HOME/CODEX_HOME/TMPDIR, exactly two fixed command hook definitions
and one synthetic user turn. Native `hooks/list` must contain exactly those two
user-source hooks, exact generated command strings, no plugin/managed entry and no
warnings/errors before any approval or turn. An unexpected host/managed/project
hook causes failure before the first turn; the fixture never grants blanket trust.

| Case | Trust/config state | Expected native lifecycle | Expected synthetic Responses calls |
| --- | --- | --- | --- |
| success | Exact native key/hash approval | SessionStart completed pair; UserPromptSubmit completed pair | 1 |
| untrusted | No approval | No execution sentinel or lifecycle pair | 1 |
| disabled | Exact hash approved, enabled=false | No execution sentinel or lifecycle pair | 1 |
| blocked | Approved; fixed stderr reason + exit 2 | SessionStart completed; UserPromptSubmit blocked with exact feedback entry | 0 |
| failed | Approved; fixed exit 7 | SessionStart completed; UserPromptSubmit failed with exact error entry | 1 |
| stopped | Approved; fixed continue=false JSON | SessionStart completed; UserPromptSubmit stopped with exact stop entry | 0 |

Before the first actual turn, both listing and thread creation must leave provider
count zero, both script sentinels absent, and lifecycle notices empty. Successful
execution cases must produce exactly four native lifecycle notices, matching
thread/turn correlation, per-pair identity and ordering, source metadata, scope,
running/completed timing fields and expected output entries. Each sentinel comes
from the actual fixed hook process and independently records its native input IDs,
namespace and PID. Terminal native turn observation and a subsequent native thread
read form the observation boundary; no arbitrary sleep is evidence of absence.

## Owned resources and confinement

The Python controller enters new user and network namespaces with `unshare`, brings
up only loopback and checks both IPv4 and IPv6 route tables for no default route.
The fixture fails closed if any of `/etc/codex/config.toml`,
`requirements.toml` or `managed_config.toml` exists; a fresh CODEX_HOME alone does
not exclude system configuration. The profile checks namespace IDs differ from the caller. Each hook checks it still
runs inside those exact namespaces. This is network isolation, not filesystem
isolation; the fixture relies on reviewed fixed scripts, fresh configuration and
the provider never issuing model tool calls. No project hook, supplied command,
external model, real credential, account or paid task is involved.

The native binary SHA256 is checked in both profile and controller. The controller
creates one literal Python hook program inside the exclusive scratch root. Commands
contain only the absolute Python executable, that owned script, owned root, fixed
event and enum scenario, shell-quoted as fixed arguments. Hook stdin is bounded to
64 KiB and parsed as JSON; prompt text is compared to a literal and never evaluated,
interpolated into a command or dispatched as code. Each script exits immediately,
does not fork/detach and writes an exclusive per-event sentinel.

Native stdin/stdout attach directly to the driver pipes. The controller never
reads, rewrites or manufactures app-server messages. Its loopback HTTP peer only
returns a fixed assistant message through deterministic Responses SSE. Extra
inference, wrong requests or provider errors fail qualification. Native stderr is
discarded rather than exposed as evidence or credential-bearing logs.

The driver owns the controller/namespace/native process group. Normal and failure
cleanup terminate only these owned processes; the controller uses short bounded
native termination and provider shutdown, and ExUnit cleanup checks owned PIDs
and recorded hook PIDs disappear before scratch removal. These assertions passed
on each native run without enlarging the existing stdio owner's shutdown grace.
No shared runtime or sibling service is touched.

## Reproduction, corrections and validation

The first six native cases failed at the unchanged `timeoutSec == 5` assertion.
The fixture had written public-response spelling `timeoutSec` into TOML, whereas
`config/src/hook_config.rs:163-181` uses serde name `timeout`.
`hooks/src/engine/discovery.rs:741-764` consequently defaulted to 600 seconds.
Changing only the fixed fixture TOML to `timeout = 5` fixes that mismatch; the
five-second assertion remains and now also checks exact statusMessage.
Two test helpers then exceeded strict Credo complexity. Extracting the same
metadata, identity and lifecycle assertions into bounded helpers fixes lint;
no assertion, native bound or production behavior was weakened.

From the independent driver directory in verified Devenv, with `MIX_ENV=test`
and the pinned `CODEX_BINARY`:

```sh
mix compile --warnings-as-errors
mix test test/native_hook_lifecycle_profile.exs --seed 501432
mix test test/native_hook_lifecycle_profile.exs --seed 987654
mix format --check-formatted test/native_hook_lifecycle_profile.exs
```

Both tests pass **6/0**. Root scoped `mix credo
apps/samgita_codex_driver/test/native_hook_lifecycle_profile.exs --strict`
passes. Initial native failure is preserved at
`/tmp/samgita-hook-lifecycle-initial-timeout-field-20261024.log`;
final scoped logs are `/tmp/samgita-hook-lifecycle-*-20261024.log`.
Only two actual notices and 35 positive run/entry/enum/notification contracts
gain scoped `implemented` evidence; no entry is fully verified.

The later [notification owner index](notification-owner-supplement-qualification.md)
adds the exact stop/feedback/error enum literals from these existing independent
full-entry assertions. It introduces no runtime/test change or verified state.

Async hooks, builtin hooks, other hook events, plugin reload/reconcile, MCP/prompt/
agent handlers, modified-hash recovery, timeouts, spawn errors, managed policy,
real project integrations and external/platform success profiles remain
unqualified. In particular, an async sentinel cannot substitute for a notification
pair suppressed by the source gate. This profile makes no full compatibility,
publication, release or production-readiness claim.

All owned commands and fixture/native/hook processes completed. Deliberate
mid-turn assertion-failure cleanup, async behavior and full hosted/aggregate
qualification are separate from these passing scoped checks.

## Warning versus model context

Two additive fixed UserPromptSubmit cases retain all original six scenarios,
trust checks, exact hash approval, four native lifecycle notices, source/
thread/turn/run identity, sentinels, provider counts and owned PID cleanup.
SessionStart's complete entries are now also required to equal an empty list.
No command deadline, process bound, sandbox or production behavior changes.

The warning command returns only `systemMessage` with an independently prescribed
literal. Native completion must contain exactly a warning entry with that text;
the hook and turn complete and the full one-request provider input must not
contain that warning. The context command returns only the supported
`hookSpecificOutput:{hookEventName:UserPromptSubmit,additionalContext:...}`.
Native completion must contain exactly a context entry with the prescribed text,
and that same text must appear exactly once as developer `input_text` in the
single provider request. Neither path blocks inference. The synthetic provider
returns a fixed assistant response; it never manufactures hook lifecycle notices.

Pinned `hooks/src/schema.rs:87-101,426-450` and
`engine/output_parser.rs:266-280` define these supported outputs.
`events/user_prompt_submit.rs:158-179` emits Warning;
`events/common.rs:37-50` emits Context and adds model context.
`core/src/context/hook_additional_context.rs:15-33` plus
`context-fragments/src/fragment.rs:35-53,88-110` preserve developer role/body.
The existing public hook conversion/emission then supplies actual native notices.
The two exact primary enum owners are
`schema:ServerNotification.json#/definitions/HookOutputEntryKind/enum/0`
(`warning`, SHA256 `3098b1b8dd83b8f920733a176c78e2f9c8851f3e9a24096a7e824bb737032ea8`)
and `/enum/3` (`context`, SHA256
`9189214417cfb663f6046a5e5bec53486e1cfbf5a5c41119f66fe34ee8281edc`).
Aliases, other hook events, asynchronous behavior, live project integration and
fully verified states are not inferred. Combined actual checks and exact command
logs are recorded in the repair ledger; final full local/hosted gates stay open.

The full eight-case hook-first control passes **8/0**. The complete21-file
native owning block passes **127/0 twice**, seeds501432/987654, including the
unchanged rate-limit and original hook cases. Compile, format, strict Credo433
files and the executable/config/workflow source guard pass. Exact commands/logs
are `/tmp/samgita-native-repair-continuation-v6-20261025/`, with hashes in
[repair qualification](repair-qualification.md#scoped-continuation-after-636b2ad).
Only warning/context's two exact physical enum owners gain new implemented
behavior here; the separate three-literal source index changes no test behavior.

## Stop continuation and selected persisted HookPrompt

The ninth scenario uses one explicitly trusted synchronous Stop hook, two fixed
assistant responses and exclusive first/second invocation records. The first
Stop receives `stop_hook_active:false` and the prescribed draft; its literal
block reason becomes one HookPrompt fragment. The second receives true and the
prescribed final answer, and returns an empty result. A third provider request
or hook invocation fails the fixture. Existing eight scenarios, deadlines,
namespace/route checks, trust rules and owned-process guardians remain.

Pinned `hooks/src/events/stop.rs:312-323,391-398` produces continuation text and
the real hook run reference. `core/src/session/turn.rs:737-754` records and emits
the native prompt before continuing the same turn; `v2/item.rs:881-887,1071-1076`
projects its complete fragment. UserPromptSubmit additionalContext remains
developer context, and its earlier stopped scenario is not this Stop path.

The test prescribes the complete prompt type and literal feedback, binds only
generated item/run identities, and checks the ten-step draft/hook/prompt/final/
hook/turn order. This pin reuses the handler run ID across invocations. A real
`thread/read(includeTurns:true)` store barrier precedes singleton
`thread/items/read`; the selected complete item must equal that independent
oracle. Exactly two model requests, one injected user hook prompt in the second
request, no extra execution/uncertainty, and reaped owned PIDs are asserted.
No app-server frame is scripted or rewritten.

The initial combined run was61/1 because the new timeline comprehension treated
an assigned nil item type as a filter, discarding actual turn/hook notices.
Changing only that binding to a singleton generator retains nil entries; the
ten-step expected order and all deadlines remain unchanged. The subsequent
complete nine-file native block passes61/0 at501432 and987654. Logs are
`/tmp/samgita-native-stop-cwd-authority-v{1,2}-20261025/`; the original failed
oracle is retained. Seven exact selected-response owners gain scoped implemented
evidence. This is warm paginated Linux stdio, not other hook events, async/cold
restoration, live providers, A11 or fully verified compatibility. Final combined
and hosted checks remain separate gates.
