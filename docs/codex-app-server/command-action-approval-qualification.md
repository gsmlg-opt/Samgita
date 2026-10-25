# Native command-action approvals

The new three-case profile exercises stock `rust-v0.163.0` approving and executing
one prescribed Read, ListFiles or Search command. It uses the same immutable
[source and executable pin](design.md), an owned native Unix socket, a synthetic
Responses dependency and real stock `cat`/`ls`/`rg`. It does not counterfeit
app-server messages or qualify a live provider, other OS/backend, A11 or the
complete approval lifecycle.

## Behavior and authority

Before an explicit answer, each case asserts the complete native approval params,
independently prescribed action fields, exact thread/turn/item/cwd identities,
timestamp bounds, available decisions and current handle generation/reference.
No command journal, output or completion may exist yet. The only response is
one `accept` for that pending handle; no policy amendment or generic automatic
responder is used. Duplicate use of the settled handle must fail explicitly.

Owned launchers validate the exact argv, cwd, namespace, immutable input bytes
and stock executable hash, create an exclusive execution record, then invoke the
real stock tool. Actual stdout/stderr/exit pass through unchanged. The test checks
one invocation, exact output and unchanged inputs, one native resolution, the
response digest and precisely two provider requests. It forbids credential/rule
files, extra requests, warnings and automatic review. Read paths are absolute;
ListFiles/Search display paths retain the pinned native parser's semantics.

Warm full history supplies only the native store barrier. Exact command/output
expectations are prescribed independently. After closing the client, explicitly
restarting the owned native process and proving PID replacement, the first cold
content read uses `thread/items/read` without resume/hydration. It must equal the
warm selection, leave the loaded-thread list empty and preserve command/provider
journals byte for byte. It cannot execute another command. Native/controller/
namespace/launcher/stock PIDs must disappear; the close control acknowledges only
after owned shutdown. Existing Stdio owner-death cleanup and all deadlines remain.

## Source-derived corrections and retained failures

The original isolated candidate failed before startup because it omitted the
absolute owned `CODEX_HOME` required by Stdio. Supplying that isolated reference
preserves the existing environment guard; no host credential environment is
inherited. The first external layout also omitted the neutral path dependency;
that harness-only compile failure preceded any native execution.

The next run reached native approval but failed complete-map equality. Omitting
`prefix_rule` disables only a requested amendment. The native
[policy fallback](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/exec_policy.rs#L428-L436)
still [derives a suggestion from the first heuristic prompt](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/exec_policy.rs#L906-L935).
An [unfamiliar owned shell](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/exec_policy/executable_identity.rs#L14-L94)
is evaluated before the inner command. The corrected oracle derives its exact
proposal and decision list from fixture-created shell identity and fixed argv,
never from the received approval. It still selects only `accept`, verifies no
rule file exists, and retains exact action assertions. A log is corroboration,
not the oracle; the archive-verified chain is in the v128 diagnosis.

A further run executed all three real commands with correct stdout/actions/exit,
then failed the completed-source expectation. The
[pending approval placeholder](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/bespoke_event_handling.rs#L758-L776)
uses Agent, while the [actual executor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/unified_exec/process_manager.rs#L580-L597)
uses UnifiedExecStartup. [Completion conversion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L921-L949)
preserves that source. The final test asserts pending `agent` and completed/
persisted `unifiedExecStartup` separately. No production driver, upstream source,
command, effect assertion or timeout changed.

Original failures remain in `/tmp/samgita-v125-candidate-check/`,
`/tmp/samgita-v126-candidate-check/`, `/tmp/samgita-v127-candidate-check/` and
`/tmp/samgita-v131-candidate-check/`. The bounded source-backed recovery in
`/tmp/samgita-v132-command-action-recovery/` passes the complete **3/0 twice**,
checks 1,227 protected source hashes and records 36 disappeared owned PIDs.

## Integrated results and physical owners

The current-checkout owning block includes the three new cases, the retained
independent two-command approval case and both search/citation profiles. It
passes **6/0 twice**, seeds `501432`/`987654`, in 11.6/11.9 seconds. Root/driver
warning-free compile/format, strict Credo on **452 files**, **38 tooling tests**,
inventory consistency and the eight-file source guard pass. The first integrated
static attempt fails the explicit-try readability rule before native execution;
using the equivalent function-level `after` retains mandatory Stdio closure.
The final complete block reruns all checks without exclusions.

From `apps/samgita_codex_driver` with the pinned `CODEX_BINARY` and private
namespace prerequisites:

```sh
mix test test/native_command_action_approval_profile.exs test/native_independent_command_approvals_test.exs test/native_web_search_items_profile.exs test/native_memory_citation_profile.exs --warnings-as-errors --seed 501432
mix test test/native_command_action_approval_profile.exs test/native_independent_command_approvals_test.exs test/native_web_search_items_profile.exs test/native_memory_citation_profile.exs --warnings-as-errors --seed 987654
```

Final commands/logs/guard are `/tmp/samgita-v137-command-integration/`; result/source
SHA256 are `f216ed07b5d0f844cea32dea9c2bdc628e07ed6ca9a1936fbbd39241460e4e59` /
`586b4b8c6bc90bae0518f9d41607781f33856ee7c3a2474fc341e81142be828c`.
All **55** native profiles have explicit required hosted invocations; hosted and
full new-source local results remain separate gates.

Exactly **22** canonical `CommandExecutionRequestApprovalParams.json` owners gain
scoped implemented evidence: 17 Read/ListFiles/Search nodes from the new live
approval assertions and five Unknown/nonempty-array owners from retained exact
live approval assertions. The retained test/fixture hashes also match both
774-case frozen-v107 runs. Current integration reruns that owning case. Original
rows/node hashes are preserved in the v123/v130 maps; no alias, history-only
sibling, nullable/omitted branch or unrelated decision field gains promotion.

Requirements remain **462 implemented / 12 missing / 11 blocked**; contracts are
**4,537 implemented / 2,025 missing / 59 blocked**; zero verified. A11,
source-unreachable legacy requests, other unavailable emitters and real
external/backend/OS success stay incomplete. No publication or deployment.
