# Native search creator and runtime roots

This ordinary functional qualification starts from
`2d6b3b77a05dd20f8d33d4e58632f299257aff11` on `main`. The independently
consumable driver controls the actual pinned Codex process; a loopback fixture
supplies two assistant-only model responses. No native response, search result,
database row or rollout is fabricated. Production code is unchanged.

## Target and exact scope

Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`;
source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
The unchanged provider hashes to
`a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8`.
The new `native_search_creator_roots_test.exs` hashes to
`dbde579db44323ba2e5170c676af59c6df6f3eac05e8dc0f3d11dce4b15fce9f`.

Only these physical `v2/ThreadSearchResponse.json` owners become scoped
implemented; no enclosing endpoint, sibling, alias or null branch is promoted:

| Owner | Pointer | Canonical node SHA256 |
| --- | --- | --- |
| 6145 | `/definitions/Thread/properties/originator` | `139fbd8b5b1ad496c6f4ab2cedec23fdcb1546bf1069c53d23fd16829b722075` |
| 6172 | `/definitions/ThreadEnvironment/properties/runtimeWorkspaceRoots` | `5b284be489d611fb82881913c53cf6ab1aafb5eb1048aaa911e5289c9f75475f` |

The request/response requirement rows receive supplemental evidence only.
Recorded originator identifies the creating client; it is independent of the
current reader, Project association and analytics source. Loaded environment
roots describe the current runtime selection. A cold search does not recreate
an environment or start work.

## Observable native journey

Three fresh native processes initialize with literal ordinary names
`owned_search_creator_a`, `owned_search_creator_b`, and
`owned_search_reader_c`. Two real paginated histories share an owned cwd but
use different explicit ordered root vectors: `[a-second, a-first]` and
`[b-only]`. Original request bytes and IDs remain exact.

Creator A's warm search returns A and its prescribed roots. Creator B's mixed
search returns A/B with their original respective creator names, while only B
has a loaded environment. Two independent `project/import` operations change
the associations without relabeling either creator or changing the roots.
The cold reader's first search returns both histories with null environments
and leaves the loaded list empty. Explicitly resuming A with its prescribed
roots restores only A's runtime selection and retains creator A. Every stage
checks both broad and `sourceKinds:[vscode]` content searches: ten actual search
requests, without query polling.

Complete known IDs, snippets, names, paths, Project associations, environments
and loaded/unloaded status are checked independently. Native turn/item IDs,
full original turns and SessionMeta remain intact. The provider journal stays
at exactly two calls; resume/search/import add no inference. Owned directories,
configuration, catalog, provider and support sources retain their bytes.
The exact eighteen captured frames comprise three initializes, two starts,
ten searches, two imports and one resume, in the prescribed order.

## Source-backed oracle correction

The initial native run failed the post-resume whole-file equality assertion.
A diagnostic retained that assertion and showed the complete original prefix
plus precisely one `thread_settings_applied` event. This is native behavior:
[session initialization](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/mod.rs#L1716)
unconditionally persists that checkpoint for a resumed root and flushes at
1724–1725. It is not conditional on changing roots.
[thread_settings.rs](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/thread_settings.rs#L135)
constructs the event; `rollout/src/recorder.rs:994–1001` opens the old file for
append without replacing SessionMeta.

The corrected oracle requires the full original byte prefix, exactly one
appended event, consecutive ordinal, valid timestamp, the original thread ID
and prescribed functional model/provider/cwd/roots. Complete turns and original
SessionMeta remain equal, then subsequent queries/read/close must preserve the
new checkpoint bytes exactly. Permission behavior is not asserted. Both red
runs and the corrected **1/0** run are retained. Two strict nesting findings
are retained as well; extracting the existing runtime assertions resolves them
without changing behavior, limits or gates.

Creator propagation is traced through
`initialize_processor.rs:130–132,166–183`,
`core/src/thread_manager.rs:1941–1980`, `local/helpers.rs:181` and
`thread_processor.rs:6435–6441`. Explicit roots pass through native start,
configuration and environment selection into
`thread_enrichment.rs:43–59`, `request_processors.rs:620–633` and
`v2/environment.rs:14–30`. Fifteen complete production sources match their
pinned archive members. Official exports770 and input descriptors15 remain
exact. Source-only review is separate from actual native evidence.

## Final checks and limits

The two reviewed ordinary modules pass **2/0 at501432 and987654**. Driver
compile/format, strict Credo550, fixture syntax and inventory consistency pass.
The384-source guard matches with all383 previous sources unchanged. The
earlier87schema/148ordinary-driver repeats, outside consumer and root/static/
assembly evidence retain source equivalence, without a fresh-run claim here.
No mixed/broad suite, prohibited test/audit or hosted workflow runs.

Runner/logs: `/tmp/samgita-v382-run.py` and
`/tmp/samgita-v382-functional-checks/final/`. Source/archive and exact node
evidence: `archive-evidence.json` in that directory's parent. Initial red source,
red log, diagnostic and corrected native log are retained under
`/tmp/samgita-v382-native-*`; strict failures remain in `before-style-fix/` and
`before-status-extraction/`. The binding records these hashes and exact owners.
Capture24frames/8KiB, response65KiB, snapshot/event1MiB and event256 bounds,
5s calls,20s turns and60s case deadlines are unchanged. All three owned native
processes require completion, closed Port and absent PID; failure cleanup and
process-group ownership remain intact. Fixed YOLO settings are launch setup.

Requirements remain **462 implemented /12 missing /11 blocked**; contracts
become **5,067 implemented /1,488 missing /66 blocked**, zero verified.
Strict completeness continues to fail. Nonnull search `extra` and
`threadSource`, other provenance/runtime/transport/backend/OS variants, legacy
emitters, A11 and unavailable/prohibited final verification remain incomplete.
Nothing is published or deployed. Rollback removes this isolated test and exact
evidence only; preserve existing runtime, cleanup and historical records.
