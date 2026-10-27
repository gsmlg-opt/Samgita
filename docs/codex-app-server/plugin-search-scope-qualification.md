# Positive local plugin search scopes

This ordinary functional unit starts from
`2ce52852e7e9301b01623a29ae25dc2507605e8d` on the existing `main`. The
new [test](../../apps/samgita_codex_driver/test/native_plugin_search_scope_test.exs)
uses the actual pinned Codex process and two inert local catalogs. No plugin
is installed or executed, and no model turn occurs. Production code, shared
fixtures, schemas and locks remain unchanged. Fixed YOLO is startup configuration;
no security or permission behavior is exercised.

Target: official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Final test SHA256:
`fa92814577ed59be376f142f7dba9bfe1221c856718b1ea420a3d567e498d376`.

## Genuine positive discriminator

The [pinned local scope classifier:276–295][scope] treats a catalog named
`codex-official` as global, and an ordinary differently named catalog as personal.
The fixture uses that literal local classifier with an independently named
`owned-personal-orbit` catalog. This provides positive local global/personal
results; it does not contact or qualify an official hosted catalog. No managed
catalog directory, requirements, trust rules or credentials are changed.

The [native discovery path:126–183][discovery] enumerates supplied cwd roots,
loads their actual marketplace files and filters by the requested scope.
[Filesystem discovery:446–527][filesystem] reads those manifests on each listing.
The [native ranker:313–355][ranking] independently prescribes display-name exact,
internal-name exact, prefix and keyword ranks. Reversed manifest declaration
order cannot supply the expected result order. Nine complete relevant source
files match their unique members in the immutable archive.

For each matrix, actual global, personal and omitted-scope requests retain
identical search text/cwds. Complete prescribed candidate identity/content
projections require exact marketplace names/manifest paths, plugin IDs/names,
keywords, source paths and display names. Whole native result maps and encoded
RPC frames remain captured; restored and cold results must match in full.
Discovery metadata is not used to infer activation or execution authority.

| Native source state | Global result | Personal result | Omitted scope |
| --- | --- | --- | --- |
| Both manifests present | Two prescribed global plugins | Two prescribed personal plugins | Exact four-plugin rank order |
| Global manifest held outside discovery | Empty | Same two personal plugins | Same personal result |
| Global restored | Original global result | Original personal result | Original union |
| Personal manifest held outside discovery | Same two global plugins | Empty | Same global result |
| Personal restored | Original global result | Original personal result | Original union |
| New native process, both restored | Original global result | Original personal result | Original union |

Each held file's bytes/hash remain exact, and an `after` block restores it on
failure. Every remaining directory/file must match the independently saved tree;
the restored complete tree and configuration must equal their originals.
No watcher timing, stale-cache assumption, sleep, polling or retry is involved.

The existing `local_plugins_after_initialize` helper temporarily disables local
plugins for startup, then restores the owned query configuration. Fixed YOLO
and recommended-plugin disabling are separate CLI arguments. A permanent CLI
`features.plugins=false` override is intentionally absent because it would
disable the actual feature under test after restoration. This is the existing
ordinary local-catalog fixture pattern, with no production configuration change.

## Exact owners and final checks

Only these three independently bound physical owners gain scoped implemented
evidence:

| Owner | Exact ID after `schema:v2/PluginSearchParams.json#` |
| --- | --- |
| 4744 | `/definitions/PluginSearchScope/enum/0` — global |
| 4746 | `/definitions/PluginSearchScope/enum/2` — personal |
| 4751 | `/properties/scope/anyOf/0` — supplied nonnull scope |

Workspace **4745**, remote-only limit **4749**, null **4752**, ClientRequest
aliases and whole method/response families remain unqualified. The omitted
control does not qualify explicit null or a positive workspace backend.

The focused native case passes **1/0**. The final four-file ordinary block
includes this test, the existing local-plugin filter case, serviceName provenance
and native creation snapshots. It passes **4/0 at each seed 501432 and 987654**,
without exclusions. Scoped format, driver compile with warnings as errors,
root strict Credo (**554** files) and inventory consistency pass. All six
commands complete; the **389**-file source guard remains stable, with all **388**
prior sources unchanged. No failure or implementation repair is introduced.

Exactly **24** unique correlated RPC pairs include eighteen searches, two
initializations, two native diagnostics and two empty loaded-thread queries.
Native executable identity is checked in each process. Capture remains bounded
to 32 frames per direction, 4KiB outgoing/65KiB incoming and 1MiB combined;
events/snapshots retain 256-event/1MiB limits. RPC/init bounds stay 5s and the
case 60s. Model requests stay empty, no rollout is created, and the workspace
remains empty. Both process closes require owner completion, closed Port and
absent owned native PID; registered failure cleanup remains intact.

Requirements remain **462 implemented /12 missing /11 blocked**; contracts
become **5,081 implemented /1,474 missing /66 blocked**, with zero verified in
both. Strict completeness still exits **1**. Previous larger matrices and
outside-consumer evidence retain their original unchanged-source identities;
no new aggregate or consumer run is inferred.

Final command arrays, logs and source guard are under
`/tmp/samgita-v390-functional-checks/final/`, runner
`/tmp/samgita-v390-run.py`; `archive-evidence.json` binds the immutable source
and exact nodes. Focused source/logs are under `/tmp/samgita-v390-native/`.
The finite source-only selection and final review are
`/tmp/samgita-v388-next-functional-gap.md` and
`/tmp/samgita-v390-final-review.md`.

Prohibited tests, audits, mixed broad suites and hosted workflows remain unrun.
A11, unavailable upstream producers, external/backend/OS/platform success and
full compatibility/release gates remain incomplete. No package is published or
service deployed. Rollback removes only this test and its exact evidence mapping;
no historical or production state is changed.

[scope]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/plugins/search.rs#L276-L295
[discovery]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/plugins/search.rs#L126-L183
[filesystem]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/marketplace.rs#L446-L527
[ranking]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/plugins/search.rs#L313-L355
