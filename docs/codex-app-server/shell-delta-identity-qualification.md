# Native shell output correlation and read-only cold history

This adds one ordinary functional case on immutable Codex `rust-v0.163.0`,
source `83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Base repository commit: `b023813`. Every protocol frame comes from the real
app-server. Two owned printf scripts run in its temporary workspace; no model
request occurs. Samgita, Repo, PostgreSQL and external providers do not start.

## Independent identities and effects

Only exact owners **3426/3427**,
CommandExecutionOutputDeltaNotification.threadId/turnId, receive new evidence.
One explicitly created paginated thread receives two sequential captured
thread/shellCommand calls. Each script prints its own prescribed marker and
appends its own line to an owned synthetic effect file. Each RPC returns the
native empty acknowledgement, not a fabricated execution result.

For each operation, exactly one genuine turn/started notification supplies the
expected turn ID independently of the output deltas. The expected thread ID is
the one requested before either operation. Every nonempty actual output delta
must carry those exact IDs and the independently observed item/started ID.
Concatenated deltas equal the prescribed output. The two actual turn IDs and
item IDs must differ. Started/completed items retain their userShell source;
final item exit code is zero and aggregated output matches the literal marker.
Every delta lies after item/started and before item/completed; item completion
precedes turn completion.

After each operation the effect file contains exactly the prescribed prefix of
two distinct lines. Full native history has both original turn IDs in order,
completed status and the complete exact final items. Confirmed native exit then
precedes a new initialized process using the same synthetic home. Cold full
history is exactly equal, loaded-thread lists remain empty before/after the
read, the effect file and configuration bytes are unchanged, the model request
journal remains literal `[]`, and capture still contains exactly two shell
requests. Restart/read therefore cannot silently rerun a command.

Capture is bounded to 16 frames/4096 bytes. Collection is bounded to 256
events/1 MiB and twenty seconds; each command has an explicit five-second
native execution bound. Pending/uncertain/gap state remains empty. Both owned
native PIDs must disappear after close, and registered cleanup retains the
original connection for teardown. No retry, sleep increase or shared-helper
change is introduced. Yolo is fixed launch/thread setup without policy
assertions or permission scenarios.

## Immutable producer chain

The actual
[request handler](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L2544)
submits RunUserShellCommand. Its
[standalone task](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tasks/user_shell.rs#L116)
emits the turn lifecycle and configures StdoutStream with the real turn sub_id
and command item call_id. The
[core reader](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/exec.rs#L1218)
emits nonempty chunks using those IDs. The
[bespoke handler](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/bespoke_event_handling.rs#L1199)
forwards the actual conversation_id/event_turn_id to the
[native mapping](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/event_mapping.rs#L438),
which copies them into the output notification. Standalone output persistence
explicitly materializes rollout history before its task completes.

All five complete production files match the immutable archive. Both exact
property nodes match inventory and the export matches pinned provenance.
Independent source review finds no remaining actionable issue. No scripted
Codex peer, synthetic protocol event or fixture-seeded history supplies evidence.

## Qualification boundary

The final twenty-six reviewed functional files add this test to the explicit
list in the [project unit](project-create-change-qualification.md#qualification-boundary).
Both mix test commands use warnings as errors and seeds 501432/987654; each
passes **44 tests / 0 failures**, in **78.001/77.873** command seconds. Scoped
format, warning-free compile, root strict Credo on 478 files, outside actual-
binary consumer **1/0**, three Python AST checks and the **252-file** unchanged-
source guard pass. All eight commands complete.

Exact commands/environment/logs/final-source hashes:
`/tmp/samgita-v275-functional-checks/functional/`. Results/source SHA256:
`7359eb25e1a1f74ef3f1ee6ec06bc260e5dbf8e4d51fe7f65d33cf2196b941b1` /
`f5e3f3abf25497c9d9175b8cd013aee165fb2691db34bb6f866ce8c19abbc16a`.
The adjacent source-evidence.json SHA256 is
`020e92cd9a8d671537dd1f8a2a9c5cce4601aa25db2536efb2ed8ee456a0b2b8`;
owning test SHA256 is
`4657b20fde6f749bb7e4a64804719b87382729b6553cf68cd15ee5a1491c3666`.
manifest-binding.json preserves the two original/current rows and binds final
test, immutable source proof and matrix hashes.

The v273 focused actual-native case passes **1/0**, seed 501432, 1.536 command
seconds. Source review then identifies nested if/if/with in the capture helper;
the v274 strict-Credo check reproduces its depth-three violation and exits 8,
before either native matrix or outside consumer runs. Extracting the same inner
body to capture/3 preserves all bounds/assertions/deadlines. The final v275
block above qualifies that corrected source. No native runtime test fails.

Inventory --check passes; all 485 requirement records and every schema identity/
planned test remain intact. Contracts become **4,729 implemented / 1,833 missing /
59 blocked**; requirements remain **462 implemented / 12 missing / 11 blocked**,
zero verified in both inventories. The unchanged strict completeness command
with --require-verified still exits **1** for unverified requirements; it is a
failed full-compatibility gate and executes no security tests.

This qualifies the selected Linux/stdio standalone user-shell producer only.
No model-tool command, active-turn auxiliary command, cancelled/failed command,
fragmentation/backpressure variant, remote reconnect, other OS/transport,
alias, whole method or enclosing notification inherits this evidence. Existing
requirement records, planned tests and schema identities remain unchanged.

Security/permission tests, related audits and broad/hosted workflows remain
unrun. Full compatibility, A11, source-unreachable legacy emission, real
external/platform acceptance and release remain incomplete. No publication,
production migration or deployment occurs.
