# Native source-kind and local plugin filters

Two new actual-binary profiles qualify explicit query inputs against persisted
native threads and ordinary local plugin metadata. Positive special-source
producers and remote catalogs retain separate incomplete acceptance profiles.

Pin: `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux x86_64 musl/stdio.
Binary SHA256:
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

## Populated native thread filters

`native_thread_source_filter_values_test.exs` creates two genuine native threads
with one completed ordinary assistant turn each. Their independent source oracle
is `vscode`, the combined binary app-server's actual source. Real start/turn IDs,
canonical SessionMeta, complete user/assistant history maps, an eight-field row
projection and literal snippets establish the populated data set. Synchronous
full native reads provide durability barriers; exactly two provider requests
are retained unchanged.

For both `thread/list` and `thread/search`, each explicit singleton `cli`, `exec`,
`appServer`, `subAgentReview`, `subAgentCompact`, `subAgentOther` and `unknown`
excludes those known nonmatching rows. Each `[literal,"vscode"]` OR query returns
exactly both independently known IDs, correct source/content/provenance and null
next cursor. Each full client request is captured only after successful real
send and must match its original map; native responses must correlate with the
original request ID. There are exactly64 selected frames, at most4096 bytes each.

A distinct cold native process repeats the baseline and all filters before
hydration/resume. Loaded threads remain empty and provider requests remain two.
Source/history/config/catalog/provider/journal bytes remain unchanged. Turn/case
deadlines, event/file/row bounds and finite owned process cleanup are retained.

These are explicit input acceptance, populated exclusion and mixed-OR effects.
Positive rows for the seven absent kinds and discrimination among those absent
producer kinds remain unverified. No SessionMeta/SQLite rows or source labels
are fabricated. Native `threadSource` attribution is separate from SessionSource;
`appServer` means core Mcp, not every app-server transport. The combined binary
hardcodes VSCode for ordinary app-server starts. A separate executable's source
flag cannot qualify this artifact.

Subsequent [genuine Exec evidence](native-exec-source-qualification.md) adds a
real CLI producer and positive cold list/search discrimination for owner675.
[Genuine Review child evidence](native-review-source-qualification.md) later
adds its own positive producer/discovery for owner678. The exclusion-only limits
above describe this original profile; the five other absent producer kinds gain
no positive evidence from those later tests.

The later [genuine terminal Cli profile](native-cli-source-qualification.md)
adds positive evidence for existing owner673 through the stock TUI and native
cold discovery. Compact/Other/Unknown and the distinct appServer artifact
retain their own incomplete positive-producer profiles.

Pinned source identifies real CLI/TUI, Exec and Review producer possibilities.
The bounded Compact constructor search is **not global unreachability proof**;
ordinary manual compaction retains the current session. Other/Unknown producers
also remain unqualified. This test supplies no legacy production evidence and
does not turn those remaining profiles into successes.

## Ordinary uninstalled local plugin metadata

`native_local_plugin_filter_values_test.exs` creates seven inert local plugin
manifests and a normally named local marketplace. There are no configured plugin
activation entries or executable plugin contents. The existing owned-startup
helper temporarily disables startup plugin work, then restores the original
catalog configuration; actual positive catalog responses prove query-time
selection. Fixed-yolo CLI configuration is ordinary setup only.

Explicit `plugin/list` with `marketplaceKinds:["local"]`, owned `cwds` and
`forceRefetch:false` returns the prescribed marketplace name/path/display metadata,
all seven independently prescribed plugin ID/name/keyword/source/display
projections and no load errors. Explicit `personal` search returns six expected
matches in independently fixed name/display/keyword rank, despite the fixture's
reversed declaration order. A separate description-only query returns empty.

Explicit `global` and `workspace` searches exclude this known ordinary personal
catalog, each with exact empty data/null nextCursor. These are local-exclusion
profiles. Positive built-in/global and remote workspace results remain unverified;
the two identical empty local responses cannot establish every scope-swap
discriminator. No fixture impersonates an official/bundled marketplace identity.

Complete actual outbound/inbound JSONL bytes/maps and native response IDs are
bounded and checked. Outbound capture occurs only after successful transport
send; overflow remains explicit. A distinct cold native returns byte-equivalent
full result maps. Two list and eight search calls, retained source/config/catalog/
empty provider journal, zero turns/inference and confirmed owned shutdown are
required. The existing assistant witness is unused for inference.

Remote kinds `vertical`, `workspace-directory`, `shared-with-me` and
`created-by-me-remote` remain uncalled/missing. Native source selects real remote
catalog paths or skips feature-disabled paths for them; feature-disabled empty
replies do not demonstrate their meaningful success. Listing's background local
refresh request is empty with no configured plugin keys. Installation, execution,
remote catalogs, security and permission behavior are outside this profile.

## Exact physical ownership and source evidence

Only11 independently resolved canonical ClientRequest nodes become scoped
implemented. Parent/ref nodes, other exports and equal-hash siblings inherit no
qualification:

| Owners | Definition and enum indexes | Exercised literals |
| --- | --- | --- |
| 673/675/676/678/679/681/682 | `ThreadSourceKind`,0/2/3/5/6/8/9 | cli/exec/appServer/subAgentReview/subAgentCompact/subAgentOther/unknown |
| 273 | `PluginListMarketplaceKind`,0 | local |
| 278/279/280 | `PluginSearchScope`,0/1/2 | global/workspace/personal |

Both actual thread list/search request graphs resolve `sourceKinds.items` to
the exact ThreadSourceKind nodes. Actual plugin list/search graphs resolve the
kind-array items and scope union to their exact nodes. Each physical node hash
equals its own immutable schema owner; the whole export SHA256 remains
`92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352`.

Twenty-seven complete Rust files equal their unique immutable archive members.
Source-kind closure covers protocol types/projection, real filters, request
processor/storage/search and producer distinctions. Local plugin closure covers
actual list/search handlers, matching/ranking/scope predicates and local refresh
preconditions. Native assistant classification is independently fixed through
`image_preparation.rs:126–160` and `annotated_content.rs:48–98`, preserving whole
history equality with `content_item_kinds:["unknown"]`. Selected source anchors:
`filters.rs:6–81`, `thread_processor.rs:2774–2835,5772–5864`,
`cli/main.rs:1288`, `plugins.rs:549–739`, `plugins/search.rs:128–160,287–307`,
`marketplace_context.rs:94–149` and `manager.rs:3031–3042`.

## Final functional evidence and limits

Base: `22f33af35e5f464efe220e1df7d31515c653fc8d`. Environment:
Elixir1.18.5/OTP27.3.4.17, `MIX_ENV=test`, `ERL_FLAGS='+S 2:2'`, pinned
`CODEX_BINARY`, independent driver build/dependency/config paths.

The plugin module passes1/0, then both owning modules pass **2/0** at seed501432.
Initial strict Credo exits8 for one nested incoming-capture reducer before the
matrix starts. Extracting that reducer into a bounded helper preserves all
assertions, send/receive/error behavior and limits; final strict Credo passes
on505 sources. No test timeout or assertion is weakened.

The final **55-file matrix passes109/0 twice**, seeds501432/987654, command times
184.460/186.170 seconds. Scoped format, warnings-as-errors compile, strict
Credo, outside actual-binary consumer **1/0**, thirty fixture ASTs and the
**306-source guard** pass. All304 prior sources remain byte-identical; only two
new focused test modules are added.27 whole archive files,11 independent physical
nodes, actual request graphs and the final binding pass.

Exact commands/allowlist/logs are retained by `/tmp/samgita-v333-final-run.py`
and `/tmp/samgita-v333-functional-checks/functional-final/`; the initial static
failure remains in that checkpoint's `functional/`. Source and manifest binding
scripts are `/tmp/samgita-v333-source.py`, `samgita-v333-promote.py` and
`samgita-v333-final-binding.py`.

| Artifact | SHA256 |
| --- | --- |
| Functional results | `f7c130b32527d118f67b3c440e08575072c5e80bdd699d318680c3c88c914cd5` |
| Source guard | `64bfa68e386d4cd49159a968679d28d3d0b2b57f400085a5599dd01b0cbe64ea` |
| Source evidence | `b28ee7f17781fe1849da20a5c456f9f9b8eaf9694bded67a24add1b4c5f8c88b` |
| Manifest | `0aacf80db83fd2d0ad66cfc587b1b5b360fbbf11ba15215b82e17cc3a4460221` |

Inventory consistency passes; strict completeness exits1. Requirements remain
**462 implemented /12 missing /11 blocked**; contracts become **4,996 implemented
/1,559 missing /66 blocked**; **zero verified**. Actual native processing of owned
local fixtures is separate from real external provider/catalog success.
Prohibited security/permission/authentication/authorization/approval tests/audits,
broad suites and automatic hosted workflows remain unrun. A11, legacy/external/
OS/platform profiles, complete compatibility and release remain incomplete.
No publication, tag or deployment is made.
