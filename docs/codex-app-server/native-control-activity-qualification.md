# Native independent approvals, request IDs and activity history

Status: **29 precise owners implemented; full compatibility incomplete**. Target:
Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
Linux executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

| Behavior | Evidence and limits |
| --- | --- |
| Two independent pending command approvals | Both native callbacks coexist before a reply. Explicitly declining B leaves A's exact handle/timer pending and all effects absent. Explicitly accepting A produces only prescribed A file bytes, stdout and exit status. Separate native resolutions/digests, stale handles and canonical history are checked. No amendment is accepted. |
| Native request identity | Empty/Unicode/decimal-looking string IDs, zero, negative integers and both signed i64 limits return exact typed response IDs. Integer `7` and string `"7"` settle separately; local ID reuse rejects explicitly. No provider request occurs. This does not qualify native string server-request producers. |
| Server-request fields | Native IDs, full input/permission/current-time params, option descriptions and headers have literal or independently correlated oracles in six existing complete owning files. Command replay uses authenticated borrowed WebSocket; Plan input uses isolated UDS; other selected cases use stdio. |
| Started/Completed subagent activity | A model-only fixture requests a real v2 child. Native management and child history independently supply generated IDs. Exact activities, ordering, timestamps and selective warm/first cold reads are checked after the original process is reaped. The fixture emits model tool calls, never app-server events. Interacted/Interrupted remain outside this unit. |

The activity fixture explicitly supplies `encrypted_function_args: []`, selecting
the pinned router's ordinary plaintext path. This provides no real-provider
encryption/decryption or encrypted-message evidence. Tasks, project acceptance,
production credentials and external services are untouched.

## Failed oracles preserved and corrected from source

The first complete candidate run had **27 tests / 1 failure**: Elixir
`OptionParser.split/1` is not an inverse for native Rust shlex command display.
Pinned shlex 1.3.0 doubles these scripts' backslashes in double quotes. Strict
fixed display expectations now derive from the unchanged scripts; commands,
newlines, effects and every lifecycle check remain intact. The diagnostic
compiles the checksum-matched cached crate; no upstream code is modified.

The next complete run also had **27/1**, at the exact params assertion. The
test expected a full-argv proposed amendment, but the pinned executable applies
its unfamiliar-shell identity rule:

- [Configured-shell selection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/unified_exec/process_manager.rs#L1493-L1530) uses the turn/session shell. Merely setting `SHELL` does not select the private test executable as the configured shell.
- [Executable identity](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/exec_policy/executable_identity.rs#L14-L96) evaluates the unfamiliar private shell first as a singleton. Its apparent inner commands cannot grant the executable trust.
- [Amendment derivation](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/exec_policy.rs#L916-L1028) rejects the requested `printf` prefix because it cannot approve that executable, then chooses the first heuristic prompt.

Only the two expected amendment arrays and their now-unused helper change to
the independently known private-shell singleton. Exact params equality remains;
the fixture, actual requested commands, pending barriers, denial, acceptance,
history, effects, cleanup and deadlines do not change. The isolated consumer's
initial missing-Python environment failure and all failed r2/r3 logs remain in
`/tmp/samgita-v40-candidate-consumer-20261025/evidence/`.

## Terminal scoped checks

The ordinary disposable consumer runs all **nine complete owning files at both
seeds 501432/987654: 27/0 each, zero exclusions**. Its source/dependency guards
match and owned processes are stopped. Final isolated verification:
`evidence/r4/final-verification.json`, SHA256
`70739d78e989a3e89eca65378886a628ed93c86166b5b01ce73d2412136dd3f1`.

After integration the same complete block passes **27/0 twice**, zero exclusions,
in the repository's OTP27/Elixir1.18.5 environment. Namespace/sandbox checks,
warning-free compile, formatting, strict root Credo, all **38 tooling
regressions** and inventory consistency pass. The **1,499-file source guard** and
immutable executable guard match. Only the obsolete candidate comment/docstring
are removed during integration; behavior is unchanged and retested.

```sh
PATH="$PWD/.devenv/profile/bin:$PATH" ERL_FLAGS='+S 4:4' \
  python3 -B /tmp/samgita-native-control-v40-20261025.py
python3 -B /tmp/samgita-bind-native-control-v40-20261025.py
python3 -B scripts/codex/inventory.py --check
python3 -B -m unittest discover -s scripts/codex -p 'test_*.py'
git diff --check
```

Exact commands, nine-file membership, test hashes, original rows, canonical
nodes and log hashes are retained in `/tmp/samgita-native-control-v40-20261025/`
and the adjacent owner index. Terminal binding report:
`/tmp/samgita-native-control-v40-terminal-20261025.json`, SHA256
`2240948d1119d67bc886f5baed19262f35911fc7919a0da1c28bd301c8399f04`.

Only **11 server-request + 13 activity + 2 RequestId + 1 command-params** physical
owners become implemented. Requirements remain **462 implemented / 12 missing /
11 blocked**; contracts become **4,410 implemented / 2,152 missing / 59 blocked**,
with **zero verified**. The broad approval-decisions lifecycle stays missing.
No whole-wrapper, sibling, alias or deployment qualification is inherited.

The [terminal v38 full local/hosted matrix](repair-qualification.md) predates
this executable change. Complete new final-source driver/profile/platform,
consumer and pushed hosted checks remain required. The retained GitHub aggregate
failure, A11, upstream-unreachable legacy/output emitters and real
external/backend/OS success remain incomplete. No tag, publication, production
migration or deployment.

## Interacted and Interrupted continuation

The next native scenario completes the four activity-kind literals through
`collaboration.followup_task` and `collaboration.interrupt_agent`. The pinned
[message tool](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents_v2/message_tool.rs#L42-L101)
produces Interacted; the
[interrupt tool](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents_v2/interrupt_agent.rs#L33-L112)
produces Interrupted. The v1 `send_input` tool is not this v2 producer.

An idle completed child receives a real followup. Its second captured model
request must contain the native NEW_TASK envelope before the fixture permits
the parent to issue interruption. That child response remains held; no synthetic
success can win the interruption race. Native tool output must report
`previous_status: running`, and independent child history must contain a distinct
second turn with `status: interrupted`. An activity notification alone is not
sufficient evidence that a running child was interrupted.

The test requires all four exact activity pairs and their order before parent
completion, generated child IDs resolved independently through management/history,
full warm and first-content cold selective entries, seven unchanged provider
requests, an empty workspace and reaped native processes. Both original activity
and new interaction files pass **2/0 at both seeds 501432/987654**, zero exclusions,
first in the isolated consumer and then after original-checkout integration.
No behavioral repair, deadline increase or assertion removal was needed.

```sh
PATH="$PWD/.devenv/profile/bin:$PATH" ERL_FLAGS='+S 4:4' \
  python3 -B /tmp/samgita-native-subagent-v41-20261025.py
python3 -B /tmp/samgita-bind-native-subagent-v41-20261025.py
python3 -B scripts/codex/inventory.py --check
```

Warnings-as-errors compilation, formatting, strict Credo, all 38 tooling
regressions, inventory and the **1,501-file/executable guards** pass. Exact
source/audit/consumer evidence:

- `/tmp/samgita-v41-subagent-interaction-audit.json`, SHA256 `b09ed90f38441415814826b755ce5dfa0e95c6fc38a81a5918e46dbcc31d4ce9` (31 immutable source anchors; its creation-time UNRUN status is retained).
- `/tmp/samgita-v40-candidate-consumer-20261025/evidence/v41-subagent-r1/handoff.json`, SHA256 `56ef56678578330064ff5e19b4fde14d1f93c24951ce8bde2ebe95ad2a9d8513` (later isolated native passes and shutdown evidence).
- `/tmp/samgita-native-subagent-v41-terminal-20261025.json`, SHA256 `c36f38eb7067f628365bb993dcc8981563e9c3dd89aa78b3ceae6543a414a80a` (integrated commands, hashes and exact two owner rows).

Only zero-based rows 5436/5437, `SubAgentActivityKind` enum/1 and enum/2,
become implemented. Contracts are **4,412 implemented / 2,150 missing / 59
blocked**; requirements remain **462 implemented / 12 missing / 11 blocked**,
with **zero verified**. Encryption, external providers, deployment profiles,
full aggregate/hosted qualification, A11 and source-unreachable requirements
retain their incomplete states. No release or deployment.

## Direct live-notification owners

The retained two-seed native activity evidence also supports **15 original
physical owners in `ServerNotification.json`**, independently of the selective
history schema: zero-based rows 2399–2402 and 2510–2520. Both `item/started`
and `item/completed` resolve through their own notification payloads to the
`subAgentActivity` item. The unchanged interaction test compares each complete
live payload against exact ordered activity values and independently obtained
child IDs. It asserts the model string and null arms, the populated `medium`
reasoning string and explicit null arms, IDs, kind and item discriminator.
`ReasoningEffort` is a nonempty string at this physical node; this evidence does
not turn it into an enum or qualify every possible string.

The source-only audit checks every original row, inventory-canonical node/hash,
pinned source export, producer/projection/serializer excerpt and terminal native
log. Both earlier source guards differ from this checkout only at the declared
MCP direct test, MCP dependency fixture and manifest; all activity-owning inputs
still match. The v40 complete nine-file block remains **27/0 twice**, and the v41
complete two-file block remains **2/0 twice**, at seeds 501432/987654. This is
retained evidence indexing, not a new execution of the latest complete source.

```sh
python3 -B /tmp/samgita-bind-native-activity-v43-20261025.py
python3 -B scripts/codex/inventory.py --check
python3 -B -m unittest discover -s scripts/codex -p 'test_*.py'
git diff --check
```

Audit: `/tmp/samgita-v43-native-activity-live-owner-audit.json`, SHA256
`662c153e52591b8937647cf45ae61c2055f222cb22549d61c9ac18449694cf31`.
Binding report: `/tmp/samgita-native-activity-v43-terminal-20261025.json`, SHA256
`c02ded98ac256a68ae25ef33f37ea5583cca939c31b0b1f7ab53b44389fcaab6`.
Only the fifteen named owners become implemented. Requirements remain
**462 implemented / 12 missing / 11 blocked**; contracts become **4,434
implemented / 2,128 missing / 59 blocked**, with **zero verified**.
Optional omission, other transports, whole value domains, external/backend/OS
success and A11 retain their unqualified states. Complete final-source local
and pushed hosted checks remain required. No publication or deployment.
