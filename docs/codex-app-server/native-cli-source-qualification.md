# Genuine terminal Cli source discovery

The pinned combined Codex binary's ordinary TUI now produces a real persistent
`cli` thread that the driver discovers through native list/search and history
APIs after normal exit. This supplements physical owner673,
`ClientRequest.json#/definitions/ThreadSourceKind/enum/0`, already implemented
by the earlier input/exclusion profile. No owner or requirement becomes verified.

Pin: `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux x86_64 musl.
Binary SHA256:
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

## Actual producer and ownership

`native_exec_source_values_test.exs` retains its original Exec case and shares
the discovery assertions with a new Cli case. The latter launches the exact
binary's ordinary TUI, `--no-daemon --no-alt-screen` and an inert initial prompt.
There is no replacement app-server, alternate artifact or source-label override.
The model dependency supplies one ordinary answer; actual provider metadata,
canonical first SessionMeta, completed user/assistant records and native history
independently identify the real thread, turn and source.

The new test-only `native_cli_tui_fixture.py` is a bounded PTY relay beneath the
unchanged Stdio owner. It keeps that owner's session/group, gives its native
child actual PTY slave stdin/stdout/stderr and establishes a 40x120 terminal.
No child session/group or controlling terminal is acquired. The exact patched
crossterm dependency borrows terminal fd0; its size/query paths can use fd1.
Thus this profile needs neither a controlling-terminal workaround nor fake
terminal-query responses. No Sigma/Synapsis service or additional listener starts.

The relay reports `ready` process identities, base64 `output` chunks and actual
`exit` status as separate JSONL control records. Keyboard input uses explicit
base64 `input` records. Raw terminal bytes never enter native JSON-RPC framing
or impersonate the owner's NUL cleanup acknowledgement. Limits are explicit:
16KiB PTY chunks, 8MiB total raw output, 1MiB queued output, 16KiB input lines,
8KiB decoded input chunks, 64KiB queued input, 120s maximum lifetime and a 2s
exit-drain bound. Overflow/I/O failure is a failed profile with nonzero exit.
The owning test imposes stricter file/event/output bounds and its existing
20s producer deadline. Exceptional cleanup remains with the outer owner;
exceptional cleanup does not establish successful TUI completion.

The actual native OSC9 notification for the prescribed answer is the completion
barrier. Only after receiving it does the test send one `/quit` plus Enter.
The native child must exit0, PTY output must drain to EOF, the relay must report
that status last, the outer owner must confirm cleanup, and both child and relay
PIDs must disappear. No interruption, forced termination or successful exit
alone substitutes for durable completion. Relay fault branches are not newly
qualified by this normal-exit test.

## Discovery, persistence and corrected oracles

An independent ordinary app-server creates a genuine `vscode` control, for
exactly two local model requests in total. Two distinct fresh native readers
each query `cli`, `vscode` and their OR combination through both list and search
before loading any execution. Independent source/ID sets, full eight-field rows,
literal snippets and complete native history maps discriminate the producers.
Native raw user-message IDs remain distinct from the public durable UserMessage
IDs. Full cold paging preserves IDs/content and all retained rollout/journal
bytes; no additional inference or loaded thread appears.

The first two development runs received native completion but failed ordinary
exit. A bounded terminal-tail diagnostic showed `/quit` in a multiline draft:
the native rapid-input detector consumes Enter into a paste burst. The public
`tui.disable_paste_burst=true` setting selects ordinary immediate keyboard
submission. No sleep, deadline increase, extra Enter or quit retry is introduced.
The next run reached discovery and exposed a legitimate first-start config edit.
The final oracle requires exactly the original config plus
`screen_reader_detection_done = true` in its TUI section, then freezes the whole
result for all subsequent readers. All other input/config bytes remain exact.
None of these failed runs is erased or counted as acceptance.

Pinned source anchors include `cli/src/main.rs:1095–1140`,
`tui/src/lib.rs:690–736`, `tui/src/daemon_startup.rs:66–83`,
`tui/src/notifications/osc9.rs:28–55`,
`tui/src/bottom_pane/chat_composer.rs:3606–3621`,
`config/src/types.rs:838,863–867` and `tui/src/screen_reader.rs:79–101`.
Thirty-five whole Codex files equal their unique immutable archive members.
Twelve whole crossterm files equal the exact patched revision
`ed1cdab335221515706178d68495bba2aed1924f`; archive SHA256
`3530cd377d080722f631c6566e5edb4844ab8be8f4b185d6be4a2bbba5591531`.
The physical schema node and both actual request graphs are checked independently.

## Checks and remaining gates

Baseline: `d8a559cf73451c8b06f74bb7a537893f126d7d13`.
Elixir1.18.5/OTP27.3.4.17, `MIX_ENV=test`, `ERL_FLAGS='+S 2:2'`, pinned
`CODEX_BINARY` and the driver's independent build/config/dependency paths.

The affected three-file block passes **4/0 twice**, seeds501432/987654:
`native_exec_source_values_test.exs`, `native_review_source_values_test.exs`
and `native_thread_source_filter_values_test.exs`. Scoped format,
warnings-as-errors compilation, strict Credo on507 sources, outside actual-binary
consumer1/0, the relay and existing inline launcher's ASTs pass. The 309-source
guard matches before/after; only the owning Exec test changes among the prior
308 sources. All307 unrelated sources, including production cleanup, are exact.
The previous 57-file111/0 matrix remains historical, not rerun on this source.

Exact commands/logs: `/tmp/samgita-v340-run.py` and
`/tmp/samgita-v340-functional-checks/final/`. Source comparison and manifest
binding use `/tmp/samgita-v340-source.py` and `/tmp/samgita-v340-bind.py`.
Initial failures remain in `/tmp/samgita-v340-owning-initial.log`,
`samgita-v340-cli-input-diagnostic.log` and `samgita-v340-owning-paste-setting.log`.

| Artifact | SHA256 |
| --- | --- |
| Functional results | `35cf34173376389219ce444372061c87952be303b3975a6040e6517e341aa4e8` |
| Source guard | `13aa74b49199ccab8f28f185446eb94bfa3586a7e29d41d2563ae9e5c45cfcdb` |
| Whole source/schema comparisons | `57e2e87831cbf89969a91d5b0a2753724d0b5dd8f27e6663d5803086579ba626` |

Only owner673 receives supplemental evidence. Inventory consistency passes;
strict completeness remains exit1. Counts remain **4,996 implemented /1,559
missing /66 blocked** contracts and **462 implemented /12 missing /11 blocked**
requirements, zero verified. Other source producers, TUI configurations, OS and
transport profiles gain no qualification. Fixed yolo is ordinary owned-fixture
setup only. No security, credential, permission, authentication, authorization
or approval test/audit runs. Broad and hosted workflows remain unrun under the
user restriction. A11, legacy/external/platform success, full compatibility,
publication, release and deployment remain incomplete.
