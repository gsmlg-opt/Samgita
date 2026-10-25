# Native standalone web-search lifecycle

This unit exercises the stock standalone `web.run` executor, separately from
the [Responses-supplied web items](streamed-web-search-qualification.md).
The target remains Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

`native_standalone_web_search_test.exs` uses one explicitly owned Codex process
and its replacement, with fixed yolo settings. The provider fixture implements
only Responses SSE and the pinned provider-relative `POST alpha/search` API.
It never emits app-server frames, edits native rollout/history, or visits the
inert result URLs. These local backend responses establish native executor and
client behavior, not a real search service's availability or result accuracy.

## Activation and independent oracle

The custom local provider explicitly declares
`supports_standalone_web_search = true`; configuration enables
`standalone_web_search` and cached search. No provider renaming, impersonated
OpenAI account or external service is needed. Pinned
[extension.rs:42–50](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/web-search/src/extension.rs#L42)
selects the executor; core
[spec_plan.rs:1199–1207](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/spec_plan.rs#L1199)
and its registration path select `web.run`. The actual provider requests must
advertise that namespace and function.

Five prescribed Responses calls cause four sequential native searches, then
one final assistant answer. Complete search commands, request order, model,
root session identity, user context, exact previous function results and
thread/turn correlation are asserted. Native output IDs require their `fco_`
UUID shape, uniqueness and stability across subsequent provider calls.
User context retains exactly the native content-kind/turn metadata; its
creation time is independently bounded by host-observed turn times and must
stay identical across all four backend requests.

| Command | Completed native action | Backend results |
| --- | --- | --- |
| Two literal queries | Search with null primary and exact query list | Two opaque objects, including a future result type and nested null/boolean/integer/Unicode values |
| Open a literal URL at line 7 | Open-page with exact URL | Explicit empty array |
| Find in a non-URL reference | Find-in-page with null URL and exact pattern | Results field omitted by backend |
| Time query | Other | Explicit null |

Each actual native start must contain the same literal call ID, empty display
query, **action:null** and results:null. Each completion must contain its
independently prescribed complete item and display string. Exact start/end
pair ordering, thread/turn identity, native timestamps and one completed turn
are checked. Structured results, empty arrays and null remain distinct.

The current producer is
[tool.rs:133–146](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/web-search/src/tool.rs#L133),
which emits `None` before its backend call. Completion at
[174–189](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/web-search/src/tool.rs#L174)
contains `Some(command_action)` and the backend's opaque results.
[Extension forwarding](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L1002)
preserves the item. Results are `Option<Vec<JsonValue>>`, not an invented
driver-specific result schema.

Full warm history and actual `thread/items/read` calls require all four final
items. Individual selections, duplicate/reversed requested IDs and absent IDs
are checked. After confirmed native shutdown, the replacement's first content
operation is selective read; full history follows. Completed items, timestamps,
rollout/config/catalog/provider/search-journal bytes and empty loaded-thread
lists remain unchanged, with exactly five inference and four search requests.
This proves orderly process replacement, not power-loss durability or live
deployment recovery. Requests stay bounded to 5 seconds; event collection stays
bounded to 20 seconds, 256 events and 1 MiB. Existing owned cleanup is retained.

## Exact owner boundary

Only missing notification owner **2524** becomes implemented.
Already implemented results fields **2527** (ServerNotification) and
**5486** (ThreadItemsReadResponse) gain separate, directly executed evidence for
opaque populated/empty/null results. No alias or equal-hash propagation occurs.

Selective-read owner **5483** remains missing. This test observes a real null
start notification; its completed items all contain actions. The current
[selective projection:78–105](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/thread_history_projection.rs#L78)
stores completed items. Historical
[WebSearchBegin conversion:669–687](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/thread_history.rs#L669)
retains a null shape, but does not establish a current cold-selective producer.
That entry needs its own demonstrated path; no global unreachability claim is
made from these selected paths.

Twenty-two inspected producer/conversion files byte-match the retained immutable
archive. The exact three changed owners and unchanged 5483 match their pinned
exports and canonical nodes. Shared source evidence, including the citation
unit's distinct nodes, is `/tmp/samgita-v293-functional-checks/source-evidence.json`.

## Verification record

Base commit: `a5f8b7f`. The first draft fails compilation because the `assert`
macro binds a following comprehension incorrectly; extracting the expectation
fixes that test syntax. The next runs expose two omitted native metadata
expectations: generated `fco_` IDs, then retained user-message metadata.
Pinned `protocol/models.rs:1428`, `session/mod.rs:3532–3552` and
`ext/web-search/history.rs:66–87` explain those fields. The repaired oracle
checks complete maps, ID stability and independently bounded metadata instead
of stripping observed fields. Initial logs remain at
`/tmp/samgita-v293-standalone-web-501432{,-repair1}.log` and
`/tmp/samgita-v293-web-citation-501432-repair2.log`.

The owning file passes **1/0** at seeds 501432/987654 after repair. The final
explicit **33-file** functional matrix, including the separate citation unit,
passes **59/0** at both seeds in **98.841/103.031** command seconds.
Warning-free compilation, scoped formatting, strict Credo on 484 sources,
the outside-umbrella actual-binary consumer **1/0**, ten provider AST checks
and the **265-source** unchanged-byte guard pass; all eight commands complete.
Exact environment/commands/logs are in `/tmp/samgita-v293-run.py` and
`/tmp/samgita-v293-functional-checks/functional/`. Results/source-guard SHA256:
`3e691c4ea9b7abc6b65d5cade9efb4768a0892ca04eae0a69bdba18fee5c6d73` /
`634e03d603525587f8cd33b49cdea34b4cb9df9f9120280dafbcf6e73d115844`.
Adjacent final-binding.json checks precisely seven promotions and two
supplements, unchanged requirement records, schema identity and missing 5483.

Combined counts are **4,800 implemented / 1,762 missing / 59 blocked**
contracts and unchanged **462 implemented / 12 missing / 11 blocked**
requirements, zero verified. Inventory consistency passes; strict completeness
still exits **1**. Security/permission tests, audits, broad suites and hosted
workflows remain unrun under the user's restriction. No owner is fully verified
by this local profile. A11, unavailable external/OS profiles, unresolved legacy
emission paths, complete compatibility, publication and deployment remain
incomplete. No runtime, shared helper, dependency or configuration source changes.
