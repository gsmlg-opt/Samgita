# Native plugin and thread result fields

## Suggested plugin interface reload

V471 extends the existing local-plugin search fixture with a second ordinary
actual-native case. `plugin/installed` explicitly includes an uninstalled local
suggestion by name; it does not install it. The suggestion must retain
`installed: false` and `enabled: false`. At each of five warm states, both that
inventory and `plugin/search` repeat twice: declared dark-logo A, replacement B,
omitted logo with interface retained, omitted entire interface, and restored A.
A distinct cold native process repeats A twice through each API. Marketplace
category stays omitted so no category fallback can synthesize an interface.

Independent literal identity/source/full-interface projections require the
absolute owned A/B paths, explicit null composerIcon/logo, and the distinction
between an interface containing null logoDark and an explicitly null interface.
Source manifests/assets, config, catalog and fixture inputs remain byte-exact
except for prescribed reversible manifest edits. No loaded thread, rollout,
inference, plugin installation or content execution occurs. The provider is an
unused local dependency; original app-server responses come from the exact pin,
without rewriting or constructing native-success frames.

Exactly seven previously missing physical owners gain scoped evidence:

| Owner | Schema after `v2/` | Exact pointer after `#/definitions/` |
| --- | --- | --- |
| 4546 | `PluginInstalledResponse.json` | `PluginInterface/properties/composerIcon/anyOf/1` |
| 4553 | `PluginInstalledResponse.json` | `PluginInterface/properties/logo/anyOf/1` |
| 4555 | `PluginInstalledResponse.json` | `PluginInterface/properties/logoDark/anyOf/0` |
| 4628 | `PluginInstalledResponse.json` | `PluginSummary/properties/interface/anyOf/1` |
| 4774 | `PluginSearchResponse.json` | `PluginInterface/properties/composerIcon/anyOf/1` |
| 4781 | `PluginSearchResponse.json` | `PluginInterface/properties/logo/anyOf/1` |
| 4859 | `PluginSearchResponse.json` | `PluginSummary/properties/interface/anyOf/1` |

The whole-file source binding covers eight official source files and all seven
canonical nodes, checked independently in each available stable/experimental
export. `plugins.rs:822–865,915–939` selects installed **or explicitly suggested**
entries. Its `188–212` converter preserves optional interfaces; `99–119` copies
visual resources. `core-plugins/src/marketplace.rs:530–573` reads local manifest
metadata and `966–976` defines category fallback. The manager's current-context
listing and `plugin/src/manifest.rs` supply the actual metadata/resource mapping.
Binding `/tmp/samgita-v471-plugin-binding/source.json`, SHA256
`1069ca0054b4b362b829e142c231caae8b5435a4de112167e59ee31d5826465b`.
The immutable source/executable/archive pin below is unchanged.

The existing case retains its exact 22 original request/response exchanges.
The new case requires exactly 32 per direction, each original response captured
before Session decoding and matched to its one request ID. The existing capture
bound remains 32/direction, 4KiB outgoing/64KiB incoming and 1MiB combined; all
event/RPC/test bounds, per-phase restoration and checked owned shutdown remain.
Fixed process YOLO is setup only. No security, permission, approval or credential
assertions run. No runtime/shared-helper change or bound increase is introduced.

The first focused command accidentally replaced PATH instead of prepending the
verified Elixir/OTP paths, hiding Python: **2/2 setup failures**, before any native
process. Preserved log `/tmp/samgita-v471-plugin-reload-501432.log`, SHA256
`8ce2f0d3660a393fe0aab12c95815d7ef45981f5cf40d7addf1883c3fa468b18`.
Correcting only the command environment gives **2/0**, seed `501432`:

```sh
mix test test/native_plugin_search_logo_test.exs --warnings-as-errors --seed 501432
```

Test SHA256 `41306510595c8c2671ad8090def53886d621c276b936cbfcb8a3894d48737b5c`;
final log `/tmp/samgita-v471-plugin-reload-final-501432.log`, SHA256
`8a244cced2d1a8618affd5d0ddf5397a457e198a1d72ae3aad6c2ab310557601`.
The reviewed selection remains 43 files and grows to 68 cases. Final combined
source passes **68/0** at each seed `501432`/`987654` (112.742/113.042 seconds),
three selected WebSocket cases at each of three seeds, and the outside consumer
**1/0**. All **14** reviewed steps pass: scoped/root format, warning-free driver
and umbrella compile, inventory consistency, strict Credo, forced Dialyzer and
assets included. Assets retains the known Bun version warning with exit zero.
All **1,660** guarded sources remain exact throughout the run.

Final commands/logs `/tmp/samgita-ordinary-v471/`; results/source SHA256
`d4b26e297eae37be0f83272001421b55e2ffe91df0a19bcddea0a82172a7a9c0` /
`e91e1249a89d5b97464767743a2eed73dbbbefd85f4fe041b6efe6e9948cb7c8`;
plan SHA256 `93a6bc90dd9cc93ed5172a372bcabc83f0ae936aca2cfb33680abf21fe391df4`;
reviewed fingerprint
`68be417c3eaf46b88104f0fcaeff045e8e77493f4185d63633db424d1044bf26`.

Contracts: **5,309 implemented / 1,200 missing / 112 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified. Other
optional branches, policies, full methods, OS/transport/backend/external success,
prohibited/broad/hosted checks, A11, full compatibility and release remain
incomplete. No publication or deployment. Earlier evidence below retains its
original source/counts; it does not qualify this new lifecycle.
Continue the existing ordinary five-case turn plugin override profile with
fixed process YOLO before binding its separate initial thread-result owner.

## Earlier V397 scope

V397 starts from `72d8776fc6757f86ec661ef31638baa365cb8b93` on `main`.
Three independently prescribed ordinary result contracts gain scoped evidence:

| Owner | Physical experimental schema node | Actual oracle |
| --- | --- | --- |
| 4783 | `PluginSearchResponse.json#/definitions/PluginInterface/properties/logoDark/anyOf/0` | Distinct declared absolute dark-logo paths, removal/restoration and catalog discovery |
| 6039 | `ThreadResumeResponse.json#/properties/multiAgentMode/allOf/0` | Literal `explicitRequestOnly` in four loaded resume results |
| 6371 | `ThreadStartResponse.json#/properties/runtimeWorkspaceRoots` | Exact two ordered vectors in direct start results |

The official target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
archive SHA256 `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Thirteen complete source files match their immutable archive members. Each
physical node independently matches its manifest canonical hash; no alias or
surrounding definition inherits qualification.

## Independent effects and native producers

The new [plugin test](../../apps/samgita_codex_driver/test/native_plugin_search_logo_test.exs)
uses one inert uninstalled local plugin. Literal manifests declare dark-a.svg,
then dark-b.svg, then omit the declaration, then restore exact A bytes. Two
queries per phase require the complete independent 19-field interface and
ordinary identity/source projection, including exact A/B/null values. Both
assets retain their original inert bytes throughout. Holding the marketplace
outside discovery yields an exact empty result twice; restoring it yields A
twice. A distinct cold native process repeats A twice. No expected metadata is
copied from an observed result. Deleting an asset is deliberately not a null
oracle: upstream resolves declared paths without checking existence.

Native `plugins/search.rs:126–183` enumerates local marketplace inventory;
`plugins.rs:99–120,188–213` preserves the configured interface, and
`core-plugins/src/manifest.rs:306–349` resolves the actual declaration. The
unmaterialized Git/Npm fallback path is separate. This case performs no install,
activation, hook/tool execution, model request or thread creation.

The [resume test](../../apps/samgita_codex_driver/test/native_resume_collaboration_result_test.exs)
adds one direct literal assertion to four existing results while complete Plan/
Default objects change. Actual loaded response construction at
`thread_lifecycle.rs:915–934` supplies `MultiAgentMode::ExplicitRequestOnly`;
the camelCase enum supplies its prescribed wire string. Two native processes,
two real prerequisite turns and complete retained histories remain required.
Settings/resume steps cannot add inference; the 30-RPC inventory is unchanged.
This deprecated result constant does not establish active delegation or custom
mode reachability. The previous empty-thread failure remains in V395's record.

The [creator/roots test](../../apps/samgita_codex_driver/test/native_search_creator_roots_test.exs)
now checks the complete start result before extracting its thread. Its two known
vectors `[second, first]` and `[only]` must retain exact order and values.
`thread_processor.rs:1636–1651` returns the actual configuration snapshot roots;
`v2/thread.rs:186–202` declares the camelCase output. Existing real turns,
retained history, search, projects and cold resume remain asserted. No additional
RPC, inference or shared helper is introduced.

## Bytes, bounds and final-source evidence

Plugin capture retains 22 uniquely correlated original request/response pairs,
including 14 searches. Resume retains its existing 30 original pairs. Incoming
JSON is recorded before Session decoding after JSONL delimiter removal; OS chunks
and newline preservation are not claimed. **The roots test retains original
outgoing bytes and ID-correlated decoded results only. It does not capture
original incoming response bytes.** Re-encoding is not ingress-byte evidence.

Plugin capture bounds remain 32 frames/direction, 4KiB outgoing/64KiB incoming,
1MiB combined, events256/1MiB, snapshots1MiB, RPC5s and case60s. All existing
resume/roots deadlines, complete histories, immutable inputs, per-phase failure
restoration and checked owned-process/Port/PID cleanup remain intact. No timeout,
buffer, skip or assertion is weakened.

The focused new plugin case passes **1/0**. Final selection is V396's nine
reviewed ordinary modules plus plugin-logo and creator/roots: **11/0** at both
**501432** and **987654**, no exclusions. Scoped format, warning-free driver
compile, root strict Credo and offline inventory consistency pass. Environment:
Elixir1.18.5/OTP27.3.4.17, test mode, two schedulers, pinned binary and fixed YOLO
ordinary launch setup. Real Codex processes use local deterministic dependencies;
no external model/service success is inferred.

Runner and logs: `/tmp/samgita-v397-run.py` and
`/tmp/samgita-v397-functional-checks/final/`. All393 guarded sources stay stable;
exactly two prior modules change and390 prior paths retain their bytes. Earlier
results for those edited modules remain historical. Results and source-guard
SHA256 values are `a292cc89f72e77e7f933eec70d7913339cf263b287ab6336b996e11473158962`
and `ac04fb2307340384b97d7104e42b0debc61804ed0e5267f8994167e47d90eba8`.
Source binding: `/tmp/samgita-v397-source/evidence.json`, SHA256
`1bb84cef8d3c989f50ebb79cf568c63a6b08b5474c5ed35c099e0c40e219a23c`.
Manifest binding: `/tmp/samgita-v397-bind.py` and
`/tmp/samgita-v397-binding/evidence.json`, SHA256
`918f283d9e63a14179e7c210f6428016a60cde008dc53007cefd8721f172da69`.

Only4783/6039/6371 become scoped implemented: contracts are **5,090 implemented
/1,465 missing /66 blocked**; requirements stay **462 implemented /12 missing
/11 blocked**, with **zero verified** in both. Strict completeness remains red.
No other mode, root default/empty variant, asset rendering, transport, OS or
backend inherits acceptance. Security/credentials/authentication/authorization/
permission/approval tests and audits, broad suites and hosted workflows remain
unrun. A11, unavailable native producers, external/platform success, full
compatibility and release remain incomplete. No tag, publication, deployment,
production migration or sibling change occurs. Rollback removes these test
changes and three evidence mappings; runtime and historical records remain.
Continue genuine reachable ordinary producer/effect gaps.
