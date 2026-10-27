# Ordinary synchronous MCP Hook and unsupported handler boundaries

V501 follows `a653cba` on the existing `main`. Official Codex remains
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, binary
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Only the stock executable emits app-server lifecycle events. The new local
peers supply model responses and an ordinary stdio MCP dependency. Driver,
neutral core, platform data and pinned upstream implementation are unchanged.

## Real local PostToolUse observer

`native_mcp_hook_test.exs` and `mcp_hook_fixture.py` exercise one native finite
printf command, an ordinary command PreToolUse observer and a synchronous MCP
PostToolUse observer. The thread's actual MCP runtime must emit its original
starting/ready notifications and complete real tools/list discovery before the
first turn. Readiness does not stand in for invocation or processing completion.

The real MCP peer receives exactly one tools/call with nine independently
prescribed arguments, including native thread/turn/tool-use identity and the
exact command input/output. It checks the prior hook record, kernel process
record and actual shell-created Unicode file before recording the observation
and returning inert text `{}`. Its bounded journal preserves actual request
bytes, decoded objects, original IDs and exact transmitted replies. The test
waits separately for the committed tools/call reply record; transport output
alone does not imply a committed journal. Atomic snapshot replacement prevents
partial journal reads.

The complete native hook pairs must retain `handlerType: "mcpTool"`, sync mode,
source, display order, status, empty entries, exact IDs and timing, with original
pre-Session ingress bytes and schema validation. The actual command still
requires exact stdout/file, exit0, complete item maps and distinct exited PIDs.
Both turns, three finite provider requests, final assistant summary and frozen
configuration/input bytes remain required. The independent command watcher and
post observer retain their separate causal chains without an invented total
order. The MCP peer must remain live through both turns and disappear after
confirmed owned native shutdown; no EOF/shutdown-notification guarantee is
invented. Existing owner/Port/PID teardown remains intact.

The production path is explicit in the immutable source:

- [discovery.rs:584](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/hooks/src/engine/discovery.rs#L584)
  constructs the MCP handler; `engine/dispatcher.rs:188–225` executes it.
- `hooks/src/engine/mcp_runner.rs` expands complete placeholders while preserving
  JSON types; `core/src/session/session.rs:1615–1632` supplies the thread runtime.
- `core/src/hook_mcp_executor.rs` adds thread metadata, performs the genuine MCP
  call and joins returned text for the ordinary hook parser.
- `core/src/hook_runtime.rs:875–927`, app-server
  `bespoke_event_handling.rs:1147–1168` and protocol `v2/hook.rs:69–157` own the
  actual public lifecycle and complete conversion.

Only physical owner2222,
`ServerNotification.json#/definitions/HookHandlerType/enum/1`, value `mcpTool`,
becomes scoped **implemented**. Its canonical SHA256 is
`2b75cd62129859a6f23744c7e0d31ae054d280facd28d8f5505157072afc1e41`.
No remote/executor/async/error/reconnect path, catalog alias or whole MCP family
is qualified by this one success case. Nothing becomes verified.

## Prompt and Agent declarations cannot execute at this pin

These exact public alternatives become **blocked**, retaining required native
acceptance as incomplete:

| Physical owner | Canonical value | SHA256 |
| --- | --- | --- |
|2223: `HookHandlerType/enum/2`|`prompt`|`60b5693ef09527a4bcf56d65322b1fa843bbda2534ddbf928150ee3267d52e97`|
|2224: `HookHandlerType/enum/3`|`agent`|`6cf85bf41d9570deed965109eed6c05c9512f6d79e321c70f3f3d900c8d06c74`|

Both belong to `ServerNotification.json#/definitions/`. The configuration
parser admits declarations, but production
[discovery.rs:637–656](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/hooks/src/engine/discovery.rs#L637)
explicitly reports each handler unsupported and continues without constructing
an executable handler. `ConfiguredHandlerKind` contains only Command/McpTool;
the exhaustive dispatcher executes only those two alternatives. The public
notification path therefore cannot receive a native Prompt/Agent run.

The complete **5,259-file** Rust tree matches the immutable source archive.
All14 explicit Prompt/Agent references occur in seven files: declarations,
configuration/display mappings, synthetic upstream test/analytics data, or the
explicit production skip. Eleven complete producer/config files are bound to
the archive index. Independent source review reproduced the references, hashes
and exact physical nodes. Configuration/catalog serialization and constructed
test summaries cannot supply native execution evidence. No upstream source is
changed and no mock notification is counted as conformance.

Source-only artifacts:

- `/tmp/samgita-v501-unsupported-handlers-evidence.json`, SHA256
  `e833cb275c111f57aa43a875bf148a4d49854d99fd4de5fa56856660f2f85548`.
- `/tmp/samgita-v501-upstream-rust-hashes.json`, SHA256
  `71c5c75669114daba3268e3f69eb95d3dc0764ef904aa58b6d2b0e2ef4dec0b1`.
- `/tmp/samgita-v501-independent-review.md` records the bounded source review;
  actual native qualification remains separate below.

## Eager catalog journal race found by the combined run

The first combined run, `/tmp/samgita-ordinary-v501-qualified`, passed111
ordinary cases at seed501432 but stopped at step7/14: seed987654 ran111 cases
with one failure in the retained `native_mcp_status_detail_test.exs`. Its full
native catalog response had returned, but the final reply journal row was
missing at the original5s deadline. Following checks did not run; that matrix
is retained as failed evidence.

The immutable threadless producer
[codex-mcp/src/mcp/mod.rs:540–576](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-mcp/src/mcp/mod.rs#L540)
creates a temporary eager connection set, obtains its complete snapshot, then
cancels its token before the app-server sends the result. The peer can therefore
be killed immediately after its final flush. Its old flush-then-record ordering
incorrectly required work after the native owner could terminate it.

A scratch-only diagnostic holds exactly that window after the fourth reply.
It reproduces the original failure: complete independently expected native
resource/template projection, four genuine MCP requests, only three journaled
replies and an already exited peer. The unchanged5s deadline then fails. Logs
and original journal are `/tmp/samgita-v501-status-race-red.log` and
`/tmp/samgita-v501-status-race-journal.jsonl`. No stock process/source, assertion,
deadline or permission behavior was modified to obtain the diagnosis.

The retained catalog fixture now commits `reply_prepared`, including the exact
encoded bytes and decoded original-ID map, before exposing bytes on stdout.
Prepared intent alone proves no receipt; every complete native response remains
independently required. The original omitted/null/full/repeated-null journey,
per-peer four requests/prepared replies, exact IDs/methods, literal nonempty
catalogs, frozen config/workspace, no execution and owned cleanup remain. A
second case configures a self-pause immediately after the final flush and runs
the same complete journey. Its recorded mode proves the configuration, not
that SIGSTOP beat native termination in every green run. The independent red
diagnostic establishes the vulnerable lifetime window. Only owned fixture
processes receive the signal.

The new test additionally checks exact original prepared bytes, JSON-RPC keys
and frame limits. All journal/capture/deadline limits remain unchanged. The
MCP Hook fixture has a thread-owned peer that stays alive across two turns; its
actual post-flush reply records remain required and are not changed by this
threadless-fixture correction. Independent source review found no blocking
defect in the final catalog correction.

## Qualification and limits

Both focused commands, run from the independent driver in the verified Devenv
Elixir1.18.5/OTP27 test environment with `ERL_FLAGS='+S 2:2'` and pinned
`CODEX_BINARY`, pass **1 test / 0 failures**,2.2s each:

```sh
mix test test/native_mcp_hook_test.exs --warnings-as-errors --seed 501432
mix test test/native_mcp_hook_test.exs --warnings-as-errors --seed 987654
```

Original logs are `/tmp/samgita-v501-focused-501432.log` and
`/tmp/samgita-v501-focus-987654-credo.log`. Test-environment root strict Credo
passes across592 source files. Python AST parsing passes. Independent review
has no actionable source finding; final formatting changes only whitespace.

The corrected focused block includes both retained catalog cases and the new
MCP Hook, **3/0** at seeds987654/501432,4.0/4.1s. The latter also passes strict
Credo across592 source files. Logs are
`/tmp/samgita-v501-status-journal-green-987654.log` and
`/tmp/samgita-v501-status-journal-green-501432-credo.log`.

The final command
`devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v501-final`
passes **14/14** reviewed checks: **60 files / 112 actual-native cases at both
seeds501432/987654** (192.8/192.3s), selected WebSocket cases at all three seeds,
outside consumer **1/0**, inventory consistency, warning-free driver/umbrella
compilation, format, strict Credo, Dialyzer and assets. All **1,678** guarded
sources remain identical; final fingerprint is
`f3a3c9646c616d9056e1238975b37a5ce079211d06c7e4d403045f8fcf707ce4`.

| Final record | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-v501-final/results.json` | `00b965c6e793fd36e0e3119dec5583186286a8e564f29e0d3767079237c8ceb1` |
| `/tmp/samgita-ordinary-v501-final/source.json` | `9eaa1158946430b05530c9b4bbf86edc66f3f43a8b2da6b2ad9b651bdc14ed39` |
| `/tmp/samgita-v501-binding/source.json` | `398ca41571e0e17f5d473176c3eb637bd5f172619e14451047e56b0158d62d5f` |

The binding verifies16 complete producer files against the immutable5259-file
archive index, all three precise canonical owners and final owning test/fixture/
launch bytes against the passing source. It retains the failed first matrix,
deterministic red diagnostic and both focused correction logs. Final-source
success follows the causal repair; the failed run is never counted as passed.

Per-case bounds stay60s/20s/5s/1s for test/journey/observation/hook or MCP call;
native capture stays128 frames and2MiB aggregate with64KiB inbound frames.
The new MCP journal is bounded to64 rows/128KiB aggregate/16KiB per row, with
64KiB wire frames. Overflows fail explicitly. No assertion, deadline, retry,
ordering rule or cleanup is weakened.

Regenerated contracts: **5,465 implemented / 1,037 missing / 119 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**, zero
verified. Fixed never/danger-full-access is fixture setup only. No security,
credential, authentication, authorization, permission or approval test/audit,
broad suite or hosted workflow runs. Their retained gates, A11, upstream-
unreachable legacy behavior, external/OS success profiles, full compatibility
and release remain incomplete. No publication, deployment, production migration
or credential change occurs. Rollback removes this test/fixture/evidence
extension without changing persisted records.
