# Ordinary plugin template metadata and startup readiness

V534 uses stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
It joins V535/V536's ordinary app/plugin management qualification from `66775db`.
One new native case and one bounded backend dependency preserve production
driver, protocol, platform and historical data.

## Native descriptive data

Six actual `plugin/read` RPCs cover Alpha/Beta/Empty/Alpha in a warm process,
then Beta/Alpha as the first content reads of a distinct cold process. Stock
Codex returns the real metadata and every captured original app-server envelope.
Independent literal maps require populated Unicode templates, default nulls and
empty collections, explicit nulls, duplicate template IDs with different content,
and ordered duplicate materialized IDs. Remote marketplace/skill paths stay null.
No sorting, ID deduplication or materialized-ID resolution is invented.

Only template metadata, marketplacePath and descriptive skill fields are compared.
Computed plugin summaries and nonnull workspace-status reasons are excluded.
Validation covers the template data and the two exact null nodes. Six exact
detail/`scope=GLOBAL` installed-read pairs remain ordered independently of startup
traffic. Sixteen outgoing envelopes/fourteen unique request-reply IDs, original
Wire/request equality and warm capture-prefix preservation are required.

Only physical owners **4652–4659, 4661, 4662, 4672, 4732** gain scoped implemented
evidence. Nonnull reason/status owners4660/4663/4664, installation/execution,
alternate schemas and aliases receive no credit. Empty loaded-thread/workspace/
model journals, unchanged inputs and explicit native/dependency owner/Port/PID
completion remain required. No model, tool or installation operation is invoked.

## Diagnosed failures and supported startup fixture

Independent static review caught the first setup error before execution: ordinary
CLI arguments override file Plugins=true with false. The candidate was corrected
with a final fixed Plugins=true CLI argument. Nine official launch-route files
and eighteen excerpts prove append order and final table-value replacement;
fixed yolo and recommended_plugins=false stay unchanged.

The first actual-native run then failed **1/1** on an unmodeled native startup
GET `/backend-api/plugins/featured`. That log is preserved. Featured is not
requested by plugin/read; initialization/diagnostics do not join startup tasks.
Source investigation also found curated sync and other background work, so
adding only a featured response would have left the fixture incomplete.

The repaired fixed profile uses Plugins=true, RemotePlugin=true, Apps=false and
the same synthetic backend context. Official source excludes curated sync in
this mode. Empty installed snapshots skip bundle downloads/materialization; no
configured marketplaces return before Git. These are source conditions for the
owned fixture, not security or permission outcome tests.

The dependency now serves five exact successful startup query shapes: featured
(`platform=codex`), suggested (`scope=GLOBAL`), catalog (`scope=GLOBAL,limit=200`),
installed cache (`limit=200`) and installed bundles (`limit=200,includeDownloadUrls=true`).
Featured returns `[]`, suggested returns fixed empty discovery, and paginated
catalog/installed responses have empty plugins and a null continuation token.
Each kind is capped at two over the warm/cold pair and recorded separately.
Only `scope=GLOBAL` counts as a business installed read; other shapes still fail.

After writing all five startup responses for each generation, the dependency
records and emits one JSONL marker through its own stdout/Port. A framed,
4 KiB/5-second barrier consumes the exact generation before business calls and
checks all five startup rows. The marker establishes responses served; it does
not claim every native background worker completed. No app-server message is
fabricated. Unknown HTTP/fatal assertions and every original metadata/count/
schema/cold/cleanup oracle remain. No sleep, timeout increase or retry is added.

## Source, bounds and focused verification

Eight original producer files/twenty-one excerpts and the complete response
schema match the archive, including all twelve canonical owner nodes. Startup
repair evidence adds thirteen official files/forty-five excerpts tracing every
producer, exact route/response, empty pagination/materialization and readiness
conditions. Independent review approved the final formatted repair bytes.

Bounds: 60-second case, 5-second RPC/socket/barrier operations, 128 HTTP requests,
six detail/six business installed reads, ten startup reads, 256 journal entries/
1 MiB. Capture permits 128 outgoing/768 incoming messages, 4/128 KiB each and
4 MiB total; driver events 256/1 MiB, snapshots 2 MiB. The same bounded ordinary
helper provides inert synthetic setup/journal/cleanup; old mixed helpers remain
unchanged and unexecuted. No credentials/headers or policy outcomes are inspected.

The first repair rerun passes **1/0**, seed `501432`, in 1.7 seconds:

```sh
mix test test/native_ordinary_plugin_template_metadata_test.exs --warnings-as-errors --seed 501432
```

Final-source strict Credo passes across **606** files. The earlier setup and
runtime failure are preserved separately from the successful final matrix below.

| Artifact | SHA256 |
| --- | --- |
| Final formatted test | `65ec4c7dd746916fcf397f6806149eb4be1b5673ec31147044910b14568a58be` |
| Final helper | `8853fd4c91aa4b0c2d2004e96cc397c806e19c9332d3e0927a7da981a2cc839a` |
| `/tmp/samgita-v534-source-evidence.json` | `4aac232888795f72a2acd548836b7a0379093c2781a75934d3d6d3dea4a6c383` |
| `/tmp/samgita-v534-repair1-source-evidence.json` | `6efeb875c89f4dd6ccc9e6940ee5a2b784d63fefdacea06172ef879cc7d1e931` |
| `/tmp/samgita-v534-repair1-independent-review.json` | `3f2766d016ed047c8848110748506747ef0eeb14cb4e4c387758d39d6018ab8f` |
| Preserved first native failure | `70e366a1f50d8ae5b54e9bb612f97ee05af4fd408f2a0eea62495a1d424e7919` |
| `/tmp/samgita-v534-repair2-source-evidence.json` | `9438f27e917a291bf19c079267d1e50a6fbab8e25eebfd046b61306ae63201c7` |
| `/tmp/samgita-v534-repair2-independent-review.json` | `fcad89f0fa70e85197bc7d36fdca59f3595cae678bb4c57d329e59c578f5234e` |
| `/tmp/samgita-v534-repair2-focused-501432.log` | `d1d2a25a410ecdbba7656dc359b450813d0dee42191f68a50fad5cda6e67299f` |
| `/tmp/samgita-v534-v536-final-preflight-credo.log` | `1e337e0e3b581ffb863903e580c93bcb419adaafa4d6de697cac7efe08f84b7e` |

## Final combined-source functional qualification

The reviewed selection passes all **14 steps** against one unchanged source:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v534-v536-final
python3 -B /tmp/samgita-v534-v536-final-bind.py
```

The **75 files / 138 actual-native cases** pass at seeds `501432` and `987654`.
The three selected WebSocket cases pass at seeds `455834`, `501432` and `987654`
(`16 tests, 0 failures, 13 excluded` each). The outside-umbrella consumer passes
**1/0** without Repo/Phoenix/platform configuration. Driver format/compile,
inventory consistency, umbrella compile/format, strict Credo, Dialyzer and assets
also pass. This selection excludes the prohibited checks and does not replace
the full matrix.

All **1,698 guarded sources** are identical before/after all commands. Exactly
five source files are added; the runner and manifest change, and **1,691** earlier
sources stay exact. Only the **46 physical rows** documented across V534–V536
gain scoped implemented evidence; no requirements or global verified states
change. The final binding rechecks all command/log/count hashes, original failures,
focused reruns, selected schema nodes and **37 unique** archive-equal producer
files. Source groups contain templates8/21, launch9/18, startup13/45, removal10/15
and catalog11/21 files/excerpts. Whole experimental request/notification roots
remain distinct from the public archive as documented in the component records.

The binding recipe initially used the root schema directory for the v2 plugin
response and stopped. Selecting its already-recorded exact `archive_member`
corrects that bookkeeping path; all schema/hash assertions remain. No runtime
or repository source changed after the matrix.

| Final evidence | SHA256 |
| --- | --- |
| Reviewed fingerprint | `1b462b50ac1d8c5576c529b1ec47960479d001f0dbbd4db8956a04266819d23e` |
| `/tmp/samgita-ordinary-v534-v536-final/source.json` | `f1efdca1081facb56d7be9a0791ffc729d6d91c9859bf2d9f9060951c02e2082` |
| `/tmp/samgita-ordinary-v534-v536-final/results.json` | `157fe37e0a50b34f2c3d753daff5c80cb12b83b58f56aaa522be0939e2d89011` |
| `/tmp/samgita-v534-v536-final-binding.json` | `58e1761a2f102da723da053630218a0c9d8281e313201dc1a47e7ddb3f2be93a` |

## Rollback and remaining gates

Rollback removes this test/helper and restores its twelve manifest rows and the
reviewed selector/fingerprint. No database or production migration occurs.
V534–V536 together leave **5,571 implemented / 920 missing / 130 blocked**
contracts and **462 implemented / 12 missing / 11 blocked** requirements;
**zero globally verified**. Local dependency success does not qualify live plugin/
backend integration, real credentials, installation or other OS/transports.

The user's prohibited security/credential/authentication/authorization/permission/
sandbox/approval checks, audits, broad suites and hosted workflows remain unrun.
A11, unavailable emitters, external/platform/full-goal/release gates remain open.
Nothing is tagged, published or deployed.
