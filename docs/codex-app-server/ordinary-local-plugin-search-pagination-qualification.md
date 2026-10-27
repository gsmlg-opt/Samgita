# Ordinary local plugin-search pagination

V517 continues after pushed `2dfbc29` with stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The new test uses two sequential owned native processes and an authored local
marketplace with 18 distinct plugins. It starts no thread or turn, issues no
install or tool execution, and makes zero model requests. Its unchanged local
model peer is not an app-server substitute.

## Native behavior

All requests use the same nonblank normalized query, personal scope and local
catalogue. All 18 authored keywords match at the same pinned rank. The complete
ordinary identity/source/display-name projection is compared by identity,
without inventing a tie order or copying expected values from a response.

| Request extras | Exact local result |
| --- | --- |
| Cursor and limit omitted | All 18 candidates |
| `cursor: null` | All 18 |
| `limit: null`, `0`, `1`, `17` or `1001` | All 18 for each request |
| `cursor: ""` | Empty |
| `cursor: "owned-next"` | Empty |

Every reply has `nextCursor: null`. Temporarily moving only the owned
marketplace file makes an omitted-cursor search empty; restoring the exact
bytes restores all 18 candidates. A distinct cold native process repeats the
omitted/empty/null cursor controls. Whole source-tree, config, fixtures, empty
workspace/model journal and absence of rollout files remain unchanged before
and after confirmed owned-process shutdown.

The pinned [search processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/plugins/search.rs#L72-L183)
passes the normalized requested limit only to the remote query. Any present
cursor string bypasses local discovery, including an empty string. Local
first pages have a separate cap of 100; the remote default of 16 does not
truncate these 18 results. `Option<String>` and `Option<u32>` explain the
missing/null distinction. Local no-truncation does not qualify the remote
limit/default/clamp success path.

Seven complete native producer/loader/converter files equal the immutable
official archive; five test-helper/provider hashes and driver/stdio hashes
are bound. Independent review artifact `/tmp/samgita-v517-final-review.json`,
SHA256 `25ca646b668063388722cbfd5ae137fda7183cd8d5bc8706fe37a2a5fb8de328`.

## Verification and limits

The initial compile exposed a module-attribute do-block binding error in the
unexecuted scratch draft. Parenthesizing that comprehension and formatting
corrects it. The exact corrected file is reconstructed from only that parse
fix and two formatter wraps; all 56 original assertion source lines remain
unchanged and ordered. The earlier source-only review missed this syntax
issue and was not executable acceptance.

The actual-native owning case then passes **1/0**, seed `501432`, in 1.7 seconds;
strict Credo passes across 597 files. Command from the independent driver in
the verified Devenv environment, with the pinned binary and fixed yolo setup:

```sh
mix test test/native_local_plugin_search_pagination_test.exs --warnings-as-errors --seed 501432
```

| Artifact | SHA256 |
| --- | --- |
| Initial compile failure `/tmp/samgita-v517-focus-501432.log` | `64c6205a5b2bad913ab52dc8ddf955f0179cd51afefcc3d2b333d3efe0ac4178` |
| Passed focus `/tmp/samgita-v517-focus-r1-501432.log` | `d1d2a25a410ecdbba7656dc359b450813d0dee42191f68a50fad5cda6e67299f` |
| `/tmp/samgita-v517-credo.log` | `2744dc643fb40e1278169e42aa8a8c0fda6dc8e69e6fe38d30c732708d74668b` |
| Formatted test module | `c8bc5989328829c171391eabd008600db6cb1a92f14c1cea5d4bef615dc0dc2c` |

Exactly 20 original correlated RPC pairs and 14 native searches are required.
Bounds: 60-second case, 5-second RPC; 32 frames per direction, 4/64 KiB per
outbound/inbound body and 1 MiB combined; 64 source-tree entries/1 MiB aggregate
with 60 authored entries; 256 events/1 MiB. The hold always restores in `after`.
Confirmed owner death, completion flag, closed Port and absent native PID are
required. No sleep, retry, relaxed bound, private-state mutation or forged
app-server response is used.

Only already implemented owners **1464/4747/4870/4871** gain supplemental
string-ID/local-cursor/ordinary-data/null-next-cursor evidence. Owner **4749**
and its complete metadata remain unchanged and **missing**: carrying a limit
whose remote effect was not exercised earns no promotion. No shared alias,
full PluginSummary, nonnull remote cursor or other transport is inferred.
Counts remain **5,491 implemented / 1,000 missing / 130 blocked** contracts and
**462 implemented / 12 missing / 11 blocked** requirements, zero verified.
Final combined-source functional results follow below.

Rollback removes only this test, its selector entry and supplemental evidence.
No production runtime, database, historical record or external service changes.
Security, credential, authentication, authorization, approval and permission
tests/audits, broad suites and hosted workflows stay unrun and incomplete.
A11, unreachable emitters, external/OS success, full compatibility and release
remain incomplete. Nothing is published or deployed.

## Final combined-source functional qualification

All **14 reviewed steps** pass on the final V517 executable source:

| Check | Actual result |
| --- | --- |
| Explicit 65-file ordinary native selection, seeds `501432`/`987654` | **126/0 each**, 217.413/217.864 seconds command time |
| Selected neutral WebSocket overflow/replay cases, seeds `455834`/`501432`/`987654` | **3/0 each**, 13 other mixed-file cases excluded |
| Outside-umbrella actual-native consumer | **1/0**, without Repo/Phoenix/umbrella |
| Driver/root warning-free compilation and format | Pass |
| Inventory consistency, strict Credo, Dialyzer, assets | Pass |

All **1,684** guarded source hashes match before, after and at final binding.
Reviewed fingerprint:
`caa478bf2101fec27fbc4e851144edaf0c7bf87502f560131047aff215fcf5b6`.
The binding rechecks every result/log hash and expected count, all seven
immutable producer/loader files, binary/archive pins, five helper/provider
files, two driver runtime files and the five canonical owner nodes. Relative
to `2dfbc29`, only evidence/test/limitation metadata changes in the four
supplemented rows; all 485 requirements, other 6,617 contracts and missing
limit owner4749 remain identical. No state or count changes occur.

| Artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-v517-qualified/results.json` | `1f776e6aa0cf558d22f1bbb3aa08e47d0ee85a9b809141bb0143d5159d30a5e7` |
| `/tmp/samgita-ordinary-v517-qualified/source.json` | `9abc14ecb9d5ca2d8289e5ca6f4995139b1e75019d4125762de565f1f39470ed` |
| `/tmp/samgita-v517-final-binding.json` | `56fc2056314e50b84f2e083b4350bc942848c03e3bb7ddf69cacf03d6d457b10` |

Reproduce from the root after reviewing the named selection:

```sh
python3 -B scripts/codex/check_ordinary.py --list
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output <new-evidence-directory>
```

These results qualify this ordinary selection. Prohibited/broad/hosted tests,
audits, full compatibility, A11, unsupported emitters, external/OS success and
release gates retain their incomplete status. No package publication or
deployment is claimed; automatic CI remains suppressed on delivery.

Next ordinary work is selective inherited-item reading across a paginated
fork cutoff, parent revert and first-cold recovery. A source-reviewed scratch
draft exists; it is not integrated, compiled or executed. Its inspected-path
emitter findings do not establish global upstream unreachability. It earns no
acceptance or schema promotion before real native qualification.
