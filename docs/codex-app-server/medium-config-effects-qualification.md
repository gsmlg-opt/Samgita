# Medium configuration values in native provider requests

Two focused actual-native cases distinguish explicit medium configuration from
independent defaults, and repeat its effect after an owned cold startup. The
driver, protocol schemas, providers and existing helpers remain unchanged.
Base: `e8a7d4f7c9deaf1eab754bb10d098ea04df83a0e`.

| Exact ConfigReadResponse owner | Native configuration | Independent provider oracle |
| --- | --- | --- |
| 3639: Verbosity/enum/1 | model_verbosity medium | text.verbosity medium, overriding catalog low |
| 3642: WebSearchContextSize/enum/1 | tools.web_search.context_size medium | hosted web_search tool has search_context_size medium |

These are the two previously missing values. Low/high owners retain their
existing evidence; this unit does not rerun their mixed-scope test module.

## Genuine producer and source contract

The pin remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Twelve complete source/test references match their unique archive members.

`protocol/src/config_types.rs:90–98,412–416,439–444,493–520` declares the values
and maps context_size to internal search_context_size. The real config/read
projection is `v2/config.rs:158–163,299–305,386–409`: outer includeLayers is
camelCase; nested Config fields retain their native snake_case names.

`core/src/client.rs:1038–1053` selects configured verbosity before the private
model catalog's default; `codex-api/src/common.rs:392–410` builds the actual
provider text controls. `core/src/tools/hosted_spec.rs:14–44` and
`spec_plan.rs:690–713` construct the native hosted search tool from current
configuration. `tools/src/tool_spec.rs:39–52` omits an absent context-size field.
Matching upstream tests are source references, not newly executed tests.

The unchanged local Responses peer records actual requests from native Codex
and always returns the same final assistant text. It supplies no app-server
config response or saved history. The request parameters, not generated prose,
prove the configuration effect. No external search is requested or performed;
this does not establish real hosted-search backend success.

## Controls, cold startup and continuity

Each case uses separate otherwise equivalent control and selected homes. Both
private catalogs support verbosity and advertise a distinct low default. All
launches use fixed YOLO setup without varying or testing permission behavior.

- Verbosity: the control omits model_verbosity. Native config/read returns null,
  while the actual provider request selects catalog low. Explicit medium returns
  medium in both native config/read and the provider request.
- Search context: both homes use the same hosted-search setup. An empty
  tools.web_search table produces null context_size in config/read and omits
  search_context_size from the one provider tool. Adding only medium supplies
  that exact value in both independent native outputs.

Each control completes one ordinary text turn. The selected home completes one
turn, closes/reaps its native PID, then starts a distinct pinned process on the
same home. Cold config/history reads add no provider work and leave the original
thread unloaded. Only an explicit new thread and turn creates the next request,
which independently repeats medium. The previous journal entry remains an exact
prefix of the decoded request list; both original histories and full rows/items,
IDs/content, rollout bytes, config/catalog and source snapshots remain exact.
No resume, mutation retry or synthetic rollout is involved. Synchronous history
reads observe native state without asserting fsync or immutable SQLite/WAL files.

Per case: **three owned native PIDs, two model peers, three inference requests**
and exactly **9/24 captured selected frames**, at most4KiB each. The capture covers
three config/read, three thread/start and three turn/start calls, preserving
original bytes/maps and caller IDs. Other setup/read/status traffic is separate.
Existing60s case,20s turn,5s request/initialize,256-event/1MiB collector,1MiB
snapshots and explicit transport-owner/native reaping checks remain unchanged.

## Qualification, limits and rollback

Initial native qualification passes **2/0**. All eleven final matrix commands
pass: **87 schema /141 reviewed ordinary driver cases at501432/987654**, outside
native consumer **1/0**, warning-free compile, format, strict Credo541 and
inventory consistency. Native blocks take225.553/230.208 seconds. All372 guarded
sources remain exact, including all371 prior sources,15 descriptors and770
official exports. Root compilation/format/assets, forced Dialyzer, architecture
scanner/test and local production compile/assets/assembly also pass against the
same source. Assembly does not start the application or migrate a database.
Evidence is under `/tmp/samgita-v370-functional-checks/final/`, with
`/tmp/samgita-v370-run.py`, staged source reference
`/tmp/samgita-v370-staged-tests-review.md` and independent final source review
`/tmp/samgita-v370-final-review.md`. The exact binding script and its independent
source review are `/tmp/samgita-v370-bind.py` and
`/tmp/samgita-v370-binding-review.md`.

Only the two exact medium enum owners gain scoped implemented evidence. Counts
become **5,040 implemented /1,515 missing /66 blocked** contracts; requirements
remain **462 implemented /12 missing /11 blocked**, zero verified. Inventory
consistency passes and the strict completeness gate still fails. Full
requirements, other Config fields, null/default sibling
owners, alternate models/backends, hot reload/config-write concurrency and every
transport/OS remain separately qualified. No complete-method or verified-state
promotion follows from these two cases.

Prohibited tests/audits, mixed broad suites and hosted workflows remain
unrun/incomplete. A11, source-unreachable legacy paths, external/platform
acceptance and full compatibility remain incomplete. No tag, publication,
deployment, platform migration, redispatch or Task acceptance.

Rollback removes the new test and its exact evidence/state additions together,
restoring these two owners to missing. Preserve all runtime, native/platform
history, prior tests,15 input descriptors and770 official exports.
