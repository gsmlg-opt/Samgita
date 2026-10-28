# Ordinary app/read metadata and process-local caching

V533 continues from `b154dba` against stock `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
It adds one native case and one bounded local backend dependency. Production
driver, schemas, platform behavior and historical data are unchanged.

## Actual route and independent oracle

The real app-server receives nine `app/read` RPCs across two sequential owned
processes. Its actual processor deduplicates IDs in caller order and invokes
`codex_chatgpt::connectors`; that route projects batch metadata directly rather
than invoking the separate app/list policy evaluator. Stock Codex produces every
public reply, identifier and JSONL frame. The fixture supplies only backend
metadata, with no app-server emulator, model, MCP or tool executor.

Two independent literal app records contain Unicode descriptions, icon URLs,
distribution labels and complete tool summaries. The backend deliberately returns
canonical ordering, a modified duplicate and unrequested surplus. Exact native
response maps must preserve requested ordering, the first duplicate and complete
data, while excluding surplus and reporting partial missing IDs. Install URLs
have explicit expected local-origin/name/ID derivation; no remote icon is fetched.

Five warm reads require exactly two backend batches: metadata-only fetch followed
by promotion to tool summaries. Cached reordered reads make no request; omitting
summaries in a response must retain the richer cache. Confirmed native shutdown
precedes a distinct cold process. Its four reads require two more batches: fresh
summary fetch and an absent-only lookup, while cached order/hiding remain exact.
The four exact backend bodies, raw JSON and sequence numbers are asserted.

Original outgoing JSON, incoming envelopes, Wire decoding and request/response
schemas agree with the complete results. The warm capture remains an exact
prefix after cold execution. All nineteen outgoing envelopes and seventeen
distinct request/reply IDs are accounted for. Loaded-thread lists, workspace and
model-request journals remain empty; no turn/item/server interaction is produced.
Inputs remain byte-identical, with explicit native/dependency Port/owner/PID
completion and closed-fixture evidence.

Only physical owners **3334–3350** gain scoped implemented evidence. These are
the six AppToolSummary properties, nine ConnectorMetadata properties and the
two response properties in `v2/AppsReadResponse.json`. Separate AppInfo,
AppMetadata, notifications, templates and structurally equal aliases receive no
credit. `pluginDisplayNames` covers an empty array with plugins disabled; no
populated plugin or unobserved nullable/default alternative is qualified.

Fixed `isEnabled`, `isReadOnly` and opaque `disabledReason` are copied descriptive
data. No grant, effective access, policy enforcement or tool-executability outcome
is tested. Synthetic identity is inert setup; credential files/headers are not
inspected. Fixed ordinary yolo launch arguments are retained. The new helper
imports only V532's reviewed inert setup and bounded journal/cleanup, leaving both
V532 files and the old mixed Apps profile/helper unchanged.

## Source and execution bounds

Twelve complete production files and fifteen excerpts match the official immutable
archive. The retained AppsReadResponse JSON is also byte-identical to its archive
member; all seventeen canonical node hashes match. Sources trace native dispatch,
backend selection and projection, process-local cache, install URL construction,
declared types and original response-ID routing.

Bounds: 60-second case, 5-second RPC/socket operations, four batches/128 HTTP
operations, 64 KiB batch inputs, 256 journal entries/1 MiB and 1 MiB replies.
Capture permits 128 outgoing/768 incoming envelopes, 4/128 KiB frames and 4 MiB
total; driver events are bounded at 256/1 MiB and snapshots at 2 MiB. One local
dependency and two sequential native processes are owned and confirmed stopped.
No retry, added sleep, deadline increase or weakened assertion is used.

Independent source review found no actionable issue. The adopted helper matches
its reviewed bytes; formatting preserves the reviewed test AST. Python syntax
parses without importing/executing the helper.

## Focused evidence

The first actual-native run passes **1/0**, seed `501432`, in 1.7 seconds:

```sh
mix test test/native_ordinary_apps_read_metadata_test.exs --warnings-as-errors --seed 501432
```

Strict Credo passes across **603** source files. The final combined-source
functional selection below also passes.

| Artifact | SHA256 |
| --- | --- |
| Formatted test | `e32826f7f849c49fc9d420f2cedd236b047c16ab713e80d8de3d712fb179803f` |
| Reviewed helper | `39b9d8c7bba1934139c9234533de47e225e7d4863c0dddbb5a266757d6a5e6a3` |
| `/tmp/samgita-v533-handoff.md` | `2d60e7b81b4f66e2bcec9dad2b7389fd7cc27adef59be65a019ff7955bd3f5f0` |
| `/tmp/samgita-v533-source-evidence.json` | `e96c1ecf4abe46a2c460d6e2a7255b40e59d6a94229982c0bcc1ae0eaabe1c79` |
| `/tmp/samgita-v533-independent-review.json` | `edc66f66338d8f7fbdafe2b4cb452234623503672c53135de71641eb0ccb14f9` |
| `/tmp/samgita-v533-focused-501432.log` | `d1d2a25a410ecdbba7656dc359b450813d0dee42191f68a50fad5cda6e67299f` |
| `/tmp/samgita-v533-strict-credo.log` | `b84ff4a5e19d6ea05493faf6bf508df0511cf74fb38a7a2a774c2d8c157a21f2` |

## Final combined-source functional qualification

All **14 reviewed functional steps pass**:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v533-final
```

The **72-file / 135-case** actual-native selection passes at `501432` and
`987654` in 238.625 and 237.215 seconds. Three selected neutral WebSocket cases
pass at each of `455834`, `501432`, `987654` (13 other cases excluded); the
outside-umbrella actual-native consumer passes **1/0**. Format, warnings-as-errors
driver/umbrella compile, inventory, strict Credo, Dialyzer and assets build pass.
No runtime failure, timeout adjustment or relaxed assertion occurs.

All **1,693** guarded before/after source hashes match. Fingerprint:
`c6fb09aa5d4377adc3e1012f7db39e47cc2401936fa8ad383ac969887b651d3c`.
The final binding checks every exact command/result/log, only the two additions,
the selector change and the seventeen manifest metadata changes. All **1,689**
other earlier guarded sources remain exact. Twelve production files/fifteen
excerpts, the archive-equal response schema, all target node hashes and four
V532/mixed baseline files remain bound to their original bytes.

| Final evidence | SHA256 |
| --- | --- |
| `/tmp/samgita-v533-final-binding.json` | `008f2845b5bc48fb14dde573758cec39a3abc571d9e31c780bf09c32aed473a6` |
| `/tmp/samgita-ordinary-v533-final/results.json` | `341f551ba8fcd0b9e722b393583921b9d0e10918c680f3ccc23d8072ed1e7eef` |
| `/tmp/samgita-ordinary-v533-final/source.json` | `370336ffb42114ff5f1a6acc4067d497cd37e2c280db2e309bd0df8bf8d65c41` |

Next: independently review the bounded ordinary remote-plugin template metadata
draft, then integrate and qualify actual responses. That source-only draft has
no native acceptance or manifest promotion yet.

## Rollback and remaining gates

Rollback removes the two additions and restores these seventeen manifest rows
and the selector/fingerprint. It requires no database or production migration.
Contracts: **5,525 implemented / 966 missing / 130 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, with **zero verified** globally.

This fixture does not qualify real backend credentials/service operation, other
OS/transports, plugin/template lifecycles or complete compatibility. The user's
prohibited security/credential/authentication/authorization/permission/sandbox/
approval checks, audits, broad suites and hosted workflows remain unrun/incomplete.
A11, source-unavailable emitters, external/platform acceptance and release gates
remain open. Nothing is published or deployed.
