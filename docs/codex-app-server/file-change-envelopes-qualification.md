# Real added-file lifecycle and repeated diff snapshots

V415 starts from `main` `86fd4f769787d47b962af62e060b6dfa52b7d208`.
Only physical owners2316/2618/2883/2951 gain scoped implemented evidence:
complete Add kind, FileChange ThreadItem, turn/diff/updated wrapper and
item/fileChange/patchUpdated wrapper. Their implemented descendants stay unchanged.

Pin: official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
New ordinary provider/test files use direct fixed YOLO, no historical namespace
controller or permission behavior, and only owned temporary files/processes.

## Actual patch, independent bytes and complete native maps

A finite loopback provider emits one freeform apply_patch call as two literal
Unicode argument fragments, then a final assistant answer in its second and
last request. It constructs model SSE only; stock Codex produces all native
app-server messages and executes the patch. The initially absent added file
must become a regular file containing exactly `owned added λ🙂\n` (19 UTF-8
bytes); `untouched.txt` retains `owned untouched\n`, with an exact two-file
workspace. Assertions run again after checked shutdown.

Independent complete maps prescribe Add kind and both canonical FileChange
items, fixed tool ID, inProgress/completed status and absolute owned target.
Streamed patchUpdated instead retains the patch's literal relative target.
Only two source-prescribed preview cohorts are allowed: final-full, or an
empty Add preview followed by final-full. Every original wrapper is checked;
missing notices, extra cohorts or mismatched paths/content fail.

The complete net diff has literal headers, new-file mode100644,40zero old OID,
standard Git blob SHA1 over the prescribed bytes, `/dev/null`, relative target
and exact `@@ -0,0 +1 @@` hunk. Its new blob is
`58ad43b832b0e0e9e28477b018e8da682c77754a`. No native/driver renderer or observed
diff supplies the expectation. Tool results independently require the actual
matching custom_tool_call_output, ctco_UUIDv7, successful tool text and bounded
elapsed time before the final answer. Both actual provider requests, literal
SSE journals, identities/markers and exact five-method native request inventory
remain checked.

All selected original incoming JSON frames are captured before Session decode.
Complete wrappers, kind/current generation, schema, host-clock brackets,
strict sequence order, final raw-ingress equality and ready/empty/uncertain/gap
state are asserted. Identical payloads remain distinct captured events.

## First-run failure and source-grounded correction

The first real case failed **1/1**,1.7 ExUnit seconds, because the new test
expected one diff and received three. Earlier preview/FileChange assertions
passed. `/tmp/samgita-v415-focused.log` retains that failure; no timeout or
production behavior is changed.

Pinned `core/src/tools/events.rs:599–648` emits a net diff after canonical
patch completion. Separately `core/src/session/turn.rs:3108,3275–3310` emits
the current tracker on every successful model response completion, after
draining its in-flight tools. The tracker is outside the sampling loop and
`turn_diff_tracker.rs:114–116` clones its cached diff. Thus this one patch/two
response profile produces exactly three identical full diff maps. There is
no reset or second patch execution.

The corrected test requires all three complete independently expected maps,
with canonical completion before diff1, diff1 before diff2, final assistant
completion between diff2/diff3, then turn completion. Original ingress must
retain all three in this order; no deduplication/nonempty shortcut replaces
count or content. `/tmp/samgita-v415-focused-repair.log` passes **1/0**.
Source diagnosis `/tmp/samgita-v415-diff-cohort-diagnosis.md` SHA256:
`0dc8cd5a63385100956a552668bc533baa1300133ba96d95062c214f02176229`.

Other producer sources are `apply_patch.rs:83–173`,
`invocation.rs:180–249`, `item_builders.rs:342–376`,
`event_mapping.rs:422–429` and `bespoke_event_handling.rs:1139–1146,1256–1292`.
Seventeen whole source files and four exact canonical nodes match the immutable
archive. Upstream's own inspected diff expectation confirms the one-line hunk;
no upstream test or security test is executed.

## Final permitted verification and limits

Runner `/tmp/samgita-v415-run.py` uses established isolated
Elixir1.18.5/OTP27.3.4.17, two schedulers, pinned executable and no inherited
Mix build/deps/partition overrides. Exact commands/cwd/status/durations/log
hashes and reviewed23-module membership are in
`/tmp/samgita-v415-functional-checks/final-eof/{results,source}.json`.
Seven Python syntax checks, scoped format, warning-free driver compile, root
strict Credo and inventory consistency pass. Focused **1/0** at501432 takes
2.271 command seconds; **39/0** at501432/987654 takes63.814/64.564 seconds,
with no exclusions. All406 sources are stable; all404 prior bytes are unchanged.
Limits remain128messages/2MiB,1MiB requests,64KiB/8SSE events,5s startup/RPC,
20s turn and60s case. Checked owned owner/PID/Port cleanup is preserved.

The pre-commit whitespace gate found a trailing empty fixture line. Removing
it and updating the pinned fixture digest leaves behavior unchanged; the full
final-eof matrix above rechecks the final bytes. Earlier `final/` results remain
historical. No commit or publication used the rejected whitespace version.

Test/provider SHA256:
`150c8ee8f9984111a18a90e6c91630c1967e4569957b5246edee756f706dd2e6` /
`95fca287be034b34a40519377a24d8a7385d7b4c5b2ac1c207f5c410f2ae02b5`.
Source evidence SHA256:
`bcc532d73fb01a25413b77495bba56a369581e411515b56c7d28399533104875`.
Results/source-guard SHA256:
`2874e8544bacddeb578d4a427139e3567c14dd083fa5b8e58517f7d3fbec4944` /
`e51f8a4d78b4e9a0b0d6214ac9ba1cfe8cb85765b56d5e5694edb2324a1d2400`.
Binder `/tmp/samgita-v415-bind.py` and
`/tmp/samgita-v415-binding-final-eof/evidence.json` SHA256:
`725d04eb17fb340efa83e436f5d115fbf4150816c5c65ba19fa896404b30936b`.

Ledger: **5,161 implemented /1,394 missing /66 blocked** contracts;
requirements stay **462 implemented /12 missing /11 blocked**, zero verified.
Add-only does not qualify update/delete/move, errors/cancellation, other
emitters/aliases, OS/transports, remote providers or complete platform behavior.
Pinned `v2/item.rs:1518–1521` explicitly states the deprecated
item/fileChange/outputDelta is no longer emitted; it stays blocked, with no
synthetic native-success substitution. Prohibited tests/audits, mixed broad
suites and hosted workflows remain unrun. A11, unreachable producers,
external/platform/full-goal/release gates remain incomplete. No publication,
deployment, migration or sibling edits. Rollback removes these two new files
and four bindings, preserving all runtime/history. Continue controlled ordinary
child-resume status and persisted item evidence.
