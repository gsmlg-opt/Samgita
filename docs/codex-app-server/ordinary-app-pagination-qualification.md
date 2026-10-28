# Ordinary Apps pagination and explicit refresh

V538 continues V537 from `5e27ddc` against stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
It adds five actual calls to the existing ordinary catalog case and changes
one local dependency bound. Production driver, schemas and platform data are
unchanged. Fixed YOLO and every original business/cleanup oracle remain.

## Independent native behavior

The original warm full, cached full and first-cold full reads retain their literal
descriptive metadata projections and negative/positive/Unicode V537 IDs.
Between the cached read and warm shutdown, the test adds:

| Request | Expected page | nextCursor | Native updates | Directory GETs so far |
| --- | --- | --- | ---: | ---: |
| Null cursor, limit0, forceRefetch=false | Alpha | `"1"` | 1 | 2 |
| Cursor`"1"`, limit1 | Beta | `"2"` | 0 | 2 |
| Cursor`"2"`, null limit | Gamma | null | 0 | 2 |
| Cursor`"3"`, null limit | Empty | null | 0 | 2 |
| forceRefetch=true, limit100 | Complete original list | null | 1 | 4 |

The cold full read then refetches the two real backend pages, reaching six GETs.
The fixture retains the same independent out-of-order two-page directory and
opaque Unicode backend continuation token. It neither knows the client page
cursor nor constructs app-server messages. Zero normalizes to one; null limit
uses the native remaining list; a cursor equal to total yields an empty page.
Force-refresh success requires the actual extra two-page backend read, rather
than merely an equal result from cache.

Every native update retains the full descriptive list independently of the
result page. Both captured original frames and drained Session events must have
the exact expected count before matching each pair and projecting metadata.
Cached nonzero pages require zero updates. The original three updates plus the
new zero-start and force-refresh updates total five. Eight calls, eighteen
outgoing envelopes and sixteen unique request/reply pairs are exact.

The complete simple AppsListParams and scalar nextCursor schemas are checked;
mixed whole AppInfo arrays and loaded-thread context receive no credit. Only
physical owners **3325/3326/3327/3330** become scoped implemented. Invalid cursor
behavior, other aliases and full absent/null/default lifecycle202 remain open.

## Source, review and bounds

Five whole official files/twelve excerpts match the immutable archive. They
trace parameter defaults, real asynchronous dispatch, numeric cursor handling,
cache selection, notification predicates, pagination and both directory/MCP
force-refresh paths. Both entire standalone parameter/response schema exports
are archive-byte-equal; the distinct experimental ClientRequest root remains
subject to V537's explicit method-index mapping.

Independent review finds no actionable defect. Exact inverse edits restore the
entire V537 list draft and V536 helper. The helper changes only directory cap4
to6 for the two new explicit refresh reads; final exact sequence/count assertions
still reject redundant requests. Existing HTTP128/MCP32/journal256, capture/event
and 60-second case/5-second operation bounds stay unchanged. No timeout increase,
sleep, retry or removed assertion is used. Formatting preserves the complete AST.

## Focused evidence

The first real-native run passes **1/0**, seed `501432`, in 1.9 seconds:

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-v538-focused.py
```

The recipe runs `mix test test/native_ordinary_catalog_metadata_notification_test.exs --warnings-as-errors --seed 501432`
from the independent driver in the verified test environment. The final
combined-source reviewed matrix also passes below.

A separate root/default-dev formatter invocation fails during dependency BEAM
type checking in `Telemetry.Metrics.ConsoleReporter.terminate/2`. Its excerpt
and command are preserved below. The scoped standalone/test-environment formatter
passes; no dependency/compiler/build-directory repair was attempted. The dev
failure's origin is unestablished and remains outside this functional batch.

| Artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-v538-source-evidence.json` | `ce5b37be323f0cb070ffcb472d54da1abad79d7c7b47a0b0fe8979120a1fd892` |
| `/tmp/samgita-v538-independent-review.json` | `51c51b71053f9a8bc26be6e21c9b60ebe76047ea45eaf6d8e4ac8e1d60e7ee0b` |
| Final formatted list test | `b0ea5a8ef9403bf253274e18e52b3116bebab332f791894d24669fc39174467f` |
| Final local dependency | `cd21e46bca341400798105d77707b3768f9a00ecde3025afe787df7be8c3cbd6` |
| `/tmp/samgita-v538-focused-501432.log` | `170f4bdf61a02d840f1dd7065978c597ae98ab183596d629375cbf1240a83840` |
| `/tmp/samgita-v538-root-dev-format-failure.txt` (excerpt) | `226d641a8d74de604e8e014fde1ccf49caf4f327ba731c78784d0259f8c1db4c` |

## Final combined-source functional qualification

All **14 reviewed steps** pass against one unchanged final source:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v537-v538-final
python3 -B /tmp/samgita-v537-v538-final-bind.py
```

The **75 files / 138 actual-native cases** pass at seeds `501432` and `987654`.
The three selected WebSocket cases pass at `455834`, `501432` and `987654`
(`16 tests, 0 failures, 13 excluded` each). Outside-umbrella consumer **1/0**,
driver format/compile, inventory consistency, umbrella compile/format, strict
Credo, Dialyzer and assets pass in the verified test environment. This result
does not repair or establish the origin of the separate root/dev failure above.

All **1,698 guarded sources** stay identical across commands. Exactly four
guarded inputs change from V534–V536: the two tests, helper and manifest;
**1,694** previous sources remain exact. The runner changes only its normalized
fingerprint declaration; all fourteen commands and selected counts stay exact.
Only the six physical V537–V538 rows gain scoped implemented evidence, with no
requirement/global verified promotion. Final binding rechecks all commands,
logs/counts, focused results, selected schema mappings, earlier frozen artifacts
and **16 unique** complete official source files. Source groups include the
six-file/eighteen-excerpt ID route, five-file/twelve-excerpt pagination route and
fifteen earlier complete producers. Shared files are counted once in the union.

| Final evidence | SHA256 |
| --- | --- |
| Reviewed fingerprint | `db792e9fea2d47ba840444929643229515407a25249936d308dd6d48c653eb21` |
| `/tmp/samgita-ordinary-v537-v538-final/source.json` | `0b72912d13d287375371720542dfba136eaf5679bc2a620a7d672279e445cff8` |
| `/tmp/samgita-ordinary-v537-v538-final/results.json` | `8b51e07638ec6f31a7dd6045ddf62b4831437451558350b6050b3bdc917e5db0` |
| `/tmp/samgita-v537-v538-final-binding.json` | `9baf6d33b3df2674c8b0bea277b2ca635117409b855ec8a5e1fd089cab85503f` |

## Rollback and limits

Rollback restores the prior list test/helper, these four rows and reviewed
fingerprint. V537's separate ID changes must be preserved if it remains enabled.
No migration or historical data deletion is involved. V537–V538 together leave
**5,577 implemented / 914 missing / 130 blocked** contracts; requirements remain
**462 implemented / 12 missing / 11 blocked**, **zero globally verified**.
Local dependency evidence is not real backend/platform acceptance. Other OS/
transports, A11, unavailable emitters, complete compatibility and release remain
open. Prohibited tests/audits and hosted workflows remain unrun; no publication
or deployment occurs.
