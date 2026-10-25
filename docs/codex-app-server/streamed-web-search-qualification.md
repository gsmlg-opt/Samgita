# Native streamed web-search items

The [omitted/null continuation](#omitted-and-null-options) extends the original
four-item checkpoint below to sixteen actual native items. Counts remain
unchanged; it supplements ten already implemented physical field owners.

This unit qualifies exactly ServerNotification owners **2526, 2791, 2792,
2793, 2794, 2798, 2800 and 2803**. The immutable target remains Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, binary
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

One Responses-only provider emits four genuine streamed output-item pairs:
search with an explicit primary query, search with only a query list, open-page,
and find-in-page. URLs are inert synthetic result data. The stock executable
creates every app-server event and native history record. This profile proves
handling of provider-supplied actions; it does not perform browsing or establish
external search/backend compatibility.

The independent oracle requires exactly one native start and completion for
each stable item ID, in provider order. Starts contain an empty display query
and the `other` action. Completions contain the prescribed final actions:
the explicit primary overrides differing query-list values; absent primary
uses the first query plus ` ...`; open uses the URL; find uses the quoted
pattern and URL. Optional primary query is explicitly null in the fallback
case. No expected display/action value is taken from the output under test.
Thread/turn identities bind actual provider input and both notification kinds.
Native begin/end milliseconds must fall within the host-observed turn interval.

Full saved history and selective reads must retain final items, including
duplicate/request-order handling and absent-item queries. Confirmed owned-process
shutdown precedes a distinct process whose first content operation is selective
read. Full cold history and selective entries must equal the original final
records, with empty loaded lists and unchanged rollout, config, catalog and
one-request provider journal. Workspace and uncertainty checks remain intact.
These are orderly process-restart checks, not power-loss or production-cutover
qualification. Event collection remains bounded to 256 events/1 MiB/20 seconds;
requests use 5 seconds. Existing process-cleanup behavior is preserved.

The pinned [stream consumer](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/turn.rs#L2801)
creates the initial item and handles the final action. The
[deduplicator](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/stream_events_utils.rs#L369)
suppresses a duplicate start when `output_item.done` arrives. The
[display conversion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/web_search.rs#L3)
defines primary/fallback/open/find formatting. Session emission and the
[history projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/thread_history_projection.rs#L78)
preserve the final snapshot and timestamps. Eleven complete source files
byte-match the retained immutable source archive; all eight exact schema nodes
and the export match pinned provenance. Independent source review found and
corrected a provider `response.created`/`response.completed` ID mismatch.

Base commit: 7091e3a. The initial restricted-PATH command fails **5/5** before
native startup because Python is absent from that command's PATH; restoring
the inherited PATH fixes the environment. The first executable draft fails
because its developer-message oracle omitted native `type:message` and generated
`msg_` identity. The corrected complete-map oracle requires both, retaining the
literal instruction content. The focused owning test then passes **1/0**;
combined with the four dynamic-declaration cases, seeds 501432/987654 pass
**5/0**. Neither deadlines nor assertions are weakened.

Source/node evidence: `/tmp/samgita-v290-streamed-web/source-evidence.json`,
SHA256 `7bf5010964bf9512e180d2e53c46e91f6be4c3081b448c251f4cfda6cc50df8c`.
Adjacent manifest-binding.json records only the eight original/current owners
and final executable-source hashes. Focused logs are
`/tmp/samgita-v290-streamed-web-501432.log` and
`/tmp/samgita-v290-focused-987654-final.log`.

These eight owners become **implemented**, giving **4,749 implemented /
1,813 missing / 59 blocked** contracts; requirements remain **462 implemented /
12 missing / 11 blocked**, zero verified. No enclosing union, alias, structured
results, null action, other transport/OS/backend or full-method promotion occurs.
The final combined functional checkpoint is recorded in
[qualification](qualification.md). Runtime, shared helpers and dependencies are
unchanged. Security/permission tests, audits and broad/hosted workflows remain
unrun. A11, source-unreachable alternatives, external/platform acceptance, full
compatibility and release remain incomplete. No publication or deployment.

## Additional physical owners

A separate read-only review identifies **19** further missing physical owners
directly exercised by the same actual assertions. This is independent owner
mapping, without hash/reference propagation or another runtime scenario:

| Owners | Actual native assertion |
| --- | --- |
| 2521–2523 | Notification webSearch item branch, action field and non-null action branch |
| 2525 | Literal stable provider IDs retained in ordered start/completion pairs |
| 2527–2529 | Explicit results:null and exact webSearch type field/literal |
| 2790 | Both final search-action shapes |
| 2795–2797 | Final openPage branch and exact type field/literal |
| 2799, 2801, 2802 | Final findInPage branch and exact type field/literal |
| 2804–2806 | Exact other branch/type/literal in initial placeholders only |
| 5482, 5486 | Actual warm and first-cold thread/items/read non-null final action and explicit results:null |

Notification expectations compare complete native maps with fixed literal
provider IDs/actions. The response owners are mapped from separately executed
`thread/items/read` calls and complete independently prescribed final-entry
equality. `other` is never inferred to be a persisted final action. Populated
results, results contents, action:null owners 2524/5483, null queries arrays and
null URL/pattern alternatives remain unqualified at that checkpoint. The
continuation below covers the specified nullable options. No other export
inherits evidence.

All nineteen nodes and both exact exports match pinned provenance; the eleven
complete producer files again match the archive. Supplemental source evidence:
`/tmp/samgita-v290-streamed-web-additional/source-evidence.json`, SHA256
`53a3a6dd0ea66dce7d0baed9b9c19b7f9a66abec1fac7838437152cdf6e7d695`.
Adjacent manifest-binding.json records only these original/current owners.
The combined web unit now maps **27** owners, giving **4,768 implemented /
1,794 missing / 59 blocked** contracts at this checkpoint. Requirements and
zero-verified status do not change; all broader gates above remain incomplete.

## Integrated functional checkpoint

The final explicit 31-file matrix extends the prior 28-file checkpoint with
this file, native_dynamic_tool_exposure_test.exs and
native_subagent_search_provenance_test.exs. Both seeds 501432/987654 pass
**57 tests / 0 failures**, warnings as errors, in **94.837/95.204** command
seconds. Scoped format, warning-free compile, strict Credo on **482** sources,
outside actual-binary consumer **1/0**, eight provider AST checks and the
**261-source** unchanged-byte guard pass. All eight commands complete.

Exact commands/environment and logs: `/tmp/samgita-v291-run.py` and
`/tmp/samgita-v291-functional-checks/functional/`. Results/source SHA256:
`e2527bc7afa8aff449c95af99b924cdde60fd7f4fe3d3c96bfd8d4134ea33464` /
`08b55e7c6bfaf291f92b3402274d9fb1c1b2eadfcc130526dc568aa2e65df2a5`.
The source guard binds all three added units and retained executable sources;
no broad/hosted or prohibited check is inferred. No release gate changes.

## Omitted and null options

Twelve additional literal Responses items exercise six omitted/null input
groups. The original four items and every existing helper/oracle remain.
Expected final action maps are independently prescribed and contain explicitly
present null options; expected display strings are literal source-backed values.

| Two provider input cases per group | Native final options | Display |
| --- | --- | --- |
| Search primary with queries omitted/null | Prescribed primary, queries:null | Prescribed primary |
| Search fields all omitted/all null | query:null, queries:null | Empty string |
| Open-page URL omitted/null | url:null | Empty string |
| Find pattern only, URL omitted/null | Prescribed pattern, url:null | Quoted prescribed pattern |
| Find URL only, pattern omitted/null | Prescribed URL, pattern:null | Prescribed URL |
| Find fields all omitted/all null | url:null, pattern:null | Empty string |

Pinned protocol models.rs:2064–2092 accepts both provider representations.
core/web_search.rs:3–29 defines each display, event_mapping.rs:228–239 converts
the action, and v2/item.rs:992–996 preserves the nested options. This is Codex's
provider-option normalization, without driver-invented defaults. The separate
standalone extension is not exercised, so action:null stays unqualified.

Exactly five notification owners **2791/2792/2798/2800/2803** and five actually
queried ThreadItemsReadResponse owners **5663/5664/5670/5672/5675** receive
supplemental evidence. Both exported nodes are individually checked. Existing
private Unix-socket evidence remains; the response owners additionally record
the actual Linux stdio profile. No state promotion, alias propagation or new
owner count occurs. Empty query-list behavior and other profiles remain open.

All sixteen items require complete native start/final map equality, exact
order/IDs, independent timestamps, saved history and every selective read,
including first cold content selection. Complete rollout/config/catalog/journal
bytes and exactly one provider request remain unchanged through native
replacement. The 256-event/1 MiB/20-second collection, 5-second requests and
checked cleanup are unchanged. Initial focused seed 501432 passes **1/0** with
no draft failure or assertion adjustment.

Base commit: fcf26cf. Eleven whole producer files again byte-match the immutable
archive; all ten exact nodes and exports match provenance. Source/node evidence:
`/tmp/samgita-v292-functional-checks/source-evidence.json`, SHA256
`87c139e27768f0dad816e9eb75dd24223c4cbbe2c489d08a00fe4793d57e238e`.
Adjacent manifest-binding.json preserves all original records and planned
tests, adding only supported evidence/limits/transport. Final test/fixture
SHA256: `bcbfdf6d8c5c90d302fcb31b3d3490c69a539ccf4a40458f7f93d48b4fbd2117` /
`d20e693c04f35311e909ad59388b6dd0844c1b6dc6a22e5930fe92df881d1a9d`.

Contracts remain **4,793 implemented / 1,769 missing / 59 blocked**, requirements
**462 implemented / 12 missing / 11 blocked**, zero verified. The final combined
matrix is recorded in [qualification](qualification.md). Security/permission
checks, audits and broad/hosted workflows remain unrun. A11, upstream-unreachable
paths, external/platform success, complete compatibility and release remain
incomplete. No publication or deployment.

The final same 31-file functional matrix passes **57/0** at seeds
501432/987654 in **95.324/94.871** command seconds. Scoped format, warning-free
compile, strict Credo, outside actual-binary consumer **1/0**, eight fixture
ASTs and the 261-source byte guard pass; all eight commands complete. Exact
commands/environment: `/tmp/samgita-v292-run.py`. Logs/source:
`/tmp/samgita-v292-functional-checks/functional/`. Results/source SHA256:
`d0f97485c7795329dd442babd91df490c3c22eaace376addf435894472aa41bc` /
`e12d199b8be154fbda259a92fa763c6235dff51f9bdfd8a3557de4c263c147a3`.
Inventory consistency passes and strict completeness still exits **1**.
