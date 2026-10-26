# Native section-rank reverse pagination

The native integer-rank cursor path now has positive reverse-anchor and
continuation evidence in both directions, warm and unloaded cold. This does not
repair the separate [created_at precision defect](thread-list-fields-qualification.md).
The whole backwardsCursor owner5702 remains **missing**.
Base: `ab48a58f57640bcd03c241a4a7f76538e88d9067`.

## Genuine rank producer and cursor consumer

The unchanged target is `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Six complete source files match their unique archive members.

Public section creation and moves supply the independent oracle. Three genuine
paginated histories each contain one actual native user/assistant turn. Append
first/second/third, move third before first, then append first. Expected ascending
rank order is third/second/first; descending reverses it. No timestamp waits,
direct database access, cursor parsing, fabricated rank or storage edit is used.

`state/runtime/thread_section_order.rs:104–249` persists those public moves using
rank gaps. `thread_processor.rs:2697–2736` selects the section storage branch and
derives backwardsCursor from the first row. Its integer +/-1 anchor path at
`5902–5914` returns before the timestamp branch. `list_threads.rs:129–245` retains
that rank cursor and `state/runtime/threads.rs:1509–1568` applies the integer
keyset comparisons. This is an independently exercised native branch, without a
client workaround for the timestamp defect.

For each direction, three limit1 forward pages must return exactly the three
independently expected IDs with terminal null nextCursor. The middle page's
**unchanged native backwardsCursor** then enters the opposite-direction request:
its first row must include that middle anchor; its own unchanged nextCursor must
return the original preceding row and terminate. This proves positive anchor
inclusion and continuation, beyond cursor formatting or null-only behavior.

After closing/reaping the producer, a distinct pinned native process repeats
all ten pages before full-history hydration. Loaded-list stays empty. Stable
IDs and native cursors match their independently checked warm pages. Each actual
row retains section, entered time, path, preview, provider, cwd and empty inline
turns. Independent readStates metadata is preserved without a whole-response
shape claim.

Original full turn/item records, rollout bytes and section metadata remain exact
through the final cold retained-history reads. Config/catalog, source snapshots
and the three-entry provider journal remain exact through final close. The test
does not separately assert rollout bytes after the final cold close. Native PIDs
must disappear; model-peer cleanup uses the unchanged TurnFixture rather than a
new test-specific monitor. Existing StdioSessionFixture fallback is retained.

There are exactly **20 list pages,32/40 selected captured request frames** at
most4KiB each, three inference requests and two owned native PIDs. Existing60s
case,20s turns,5s request/initialize,256-event/1MiB collector and1MiB snapshots
remain bounded. Original caller maps/bytes/IDs and cursors are preserved.

## Checks and remaining contract

Initial native **1/0**, affected rank/section/sort group **4/0 at501432/987654**,
warning-free driver compile, format, strict Credo542 and inventory consistency
pass. All373 guarded sources remain stable; all372 prior sources are exact,
including the previous **87 schema /141 ordinary driver twice**, independent
consumer, runtime/provider/15-descriptor/770-export and root/static/local assembly
checkpoint. Those unchanged checks are retained by source equivalence, without
being described as newly executed checks.

Logs/commands/guard: `/tmp/samgita-v371-functional-checks/final/` and
`/tmp/samgita-v371-run.py`. Source report and independent review:
`/tmp/samgita-v371-ordinary-gap.md`, `/tmp/samgita-v371-final-review.md`.

Supplemental evidence attaches only to the list request/response and exact
backwardsCursor property. No state/count promotion occurs: **5,040 implemented
/1,515 missing /66 blocked** contracts; **462 implemented /12 missing /11
blocked** requirements, zero verified. The strict completeness gate still fails.
The timestamp branch, rank ties/rebalance/concurrent moves, other transports/OS,
external services and full compatibility remain incomplete. Prohibited
tests/audits, mixed broad suites and hosted workflows stay unrun; A11 and legacy/
external/platform gates remain open. No tag, publication or deployment.

Rollback removes this test and its supplemental evidence only. Preserve the
runtime, every prior history/test, the failing timestamp evidence and owner5702's
missing state. Continue remaining reachable ordinary field/effect variants.
