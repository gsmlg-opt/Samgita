# Native independent approvals, request IDs and activity history

Status: **27 precise owners implemented; full compatibility incomplete**. Target:
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
