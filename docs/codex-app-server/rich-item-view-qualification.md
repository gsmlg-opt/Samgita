# Rich paginated turn item projections

A real completed dynamic-tool turn now distinguishes the three canonical views:
Summary returns the original user and final assistant items; Full additionally
retains the completed tool item; NotLoaded returns no items. The same independent
oracle passes warm list, warm resume bootstrap and unloaded cold list queries.
Base: `d1dae06a895e0f570101838db04d15f41df84230`.

This closes the canonical richer-filtering gap left by the assistant-only
[unit-object fixture](turn-items-view-input-qualification.md). It adds a focused
native test and evidence; no speculative production change is required. That
earlier fixture's object-specific richer filtering remains unqualified.

## Native trigger and independent oracle

Target is official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Nine complete sources match their unique archive members.

The unchanged local Responses fixture emits one function call, accepts its
result, then emits the deterministic final assistant response. The real native
app-server creates the correlated `item/tool/call`, original item events,
timestamps, stored rows and query results. The fixture supplies no app-server
response or stored history. One explicit `Session.respond` supplies the synthetic
tool result; the actual second provider request must contain that exact result
and call ID. There are exactly two inference requests and no external tool or
search execution.

Original user, tool and assistant items derive independently from real
`item/completed` events, paired with their `item/started` events. Native item-list
entries must equal those complete records, including original IDs and ordered
timestamps. The original full turn must contain those exact three items,
completed state, null error and valid native turn timing.

Each actual page must equal the complete original turn row with only `itemsView`
and selected `items` changed. Summary must exclude the actual tool ID; Full must
retain its original arguments, content, success, duration and identity. Other row
fields remain exact. Comparing two API responses is not the sole oracle.

## Storage, restart and bounded traffic

Pinned `thread_processor.rs:3334–3399,3406–3445` implements the paginated path:
Summary reads stored selected items; Full reads shells then hydrates their
items. `segment_paging.rs:64–157` joins first-user/final-agent identities, and
`thread_history/read.rs:129–141` returns those Summary items or no NotLoaded
items. Warm resume bootstrap dispatches through this same paginated consumer at
`thread_processor.rs:3476–3489`. The separate legacy in-memory selector does not
establish this SQL behavior.

All three canonical views reach warm list and warm resume bootstrap. Resume
keeps inline turns empty and returns the independently checked initial page.
After closing/reaping that owned PID, a distinct pinned native process performs
all three list queries before history hydration. Loaded-list stays empty;
there is no cold resume in this scenario.

Original full turns, item entries/timestamps, preview, rollout bytes, config,
catalog, provider journal and support/test source snapshots remain exact. Reads
add no inference, pending interaction, uncertainty, gap or execution events.
A synchronous history read observes persistence without claiming fsync; mutable
native SQLite/WAL files are not required to remain byte-identical.

Capture is exactly **11/24 successful selected request frames**, each at most
4KiB: one thread/start, one turn/start, six list and three warm resume. Other
setup/read/status traffic and the single tool response are outside that explicit
allowlist. The60s case,5s request/initialize, bounded20s waits,256-event/1MiB
collector,1MiB snapshots and existing owned-process cleanup remain enforced.

## Qualification and limits

The new initial native case passes **1/0**. The affected ordinary view/dynamic
tool group passes **9/0 at501432 and987654**, with format, warning-free driver
compile, strict Credo540 and inventory consistency. Its371-source guard remains
exact; all370 sources from the previous **87 schema /138 ordinary driver twice**
checkpoint remain byte-identical, including runtime, providers,15 descriptors,
770 official exports and outside consumer. No unchanged package/assembly check
is claimed as a newly executed test. Broader required final matrices remain
incomplete under the user's verification restriction.

Logs/commands/source guard: `/tmp/samgita-v369-functional-checks/final/` and
`/tmp/samgita-v369-run.py`. Source report and independent review:
`/tmp/samgita-v369-ordinary-gap.md`, `/tmp/samgita-v369-final-review.md`.

Supplemental evidence attaches only to the two request/response pairs and
thirteen exact already implemented owners: canonical view variants688–693,
explicit non-null selection657/658/6452/6453, one-turn data6461 and present warm
bootstrap6031/6032. No state, physical owner or count promotion occurs. Counts
remain **5,038 implemented /1,517 missing /66 blocked** contracts and **462
implemented /12 missing /11 blocked** requirements, zero verified. The strict
completeness gate still fails.

This does not qualify null/default/object variants, multiple-user/final selection,
active/error/interrupted histories, cursor continuation, legacy storage, fork
lineage, other transports/OS/providers or full method/field graphs. Blocked queue
response view variants are not promoted by unrelated list evidence. Prohibited
tests/audits, mixed broad suites and hosted workflows remain unrun/incomplete;
A11, producerless legacy paths and external/platform success gates remain open.
No publication, deployment, platform migration, redispatch or Task acceptance.

Rollback removes this test and its supplemental evidence together; runtime,
history and prior qualifications remain intact. Next qualify explicit medium
verbosity and hosted-search context size through real provider request effects
and owned cold configuration reads, without external search execution.
