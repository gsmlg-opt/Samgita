# Packaged defaults cannot appear in native config/read metadata

V449 records a source-proven limitation at `main`
`16710c23cd6199e982c456ff88059055809bd72a`, targeting Codex `rust-v0.163.0`,
source `83086188ae0614bd882818ff1aa23f3194962012`. Five ConfigReadResponse
contracts become **blocked**, with no new passing-test or transport credit.
The schemas remain unchanged. No fixture, modified binary or serializer-only
case substitutes for an actual native producer.

The immutable upstream [read constructor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/config_manager_service.rs#L118)
unconditionally excludes PackagedDefaults from both output collections:

1. The sole production ConfigReadResponse constructor calculates origins, then
   retains only entries whose source is not PackagedDefaults (lines 151–166).
2. When includeLayers is true, it filters every PackagedDefaults layer before
   converting the collection (lines 167–173). When false, layers is absent.
3. The layer converter preserves the source variant. No other variant maps to
   PackagedDefaults. The sole request processor only augments config.features.
4. Typed payload/outgoing serialization and the external/in-process routes wrap
   that already-filtered response; they do not rebuild origins or layers.

The loader really creates this source from embedded defaults and the executable
path, or from an explicit packaged-defaults file. Its values may influence the
effective configuration. That influence is separate from emitting its source
metadata: both loading paths converge before the same unconditional exclusions.
cwd, includeLayers, feature settings, additional layers or another ordinary
transport cannot make this metadata branch observable through the pinned read.

Whole-workspace references were classified into the one constructor, processor,
typed dispatch, source conversion, serialization and consumers. Test-only
from_value uses, schema examples and the different exec-server
EnvironmentConfigReadResponse are not alternate emitters. Relevant modules and
filters have no cfg alternative. Other converter callers produce write metadata,
not this response. This is a construction/serialization invariant, rather than
an inference from an empty response or failed search. It does not runtime-qualify
other operating systems or transports.

## Exact scope and evidence

Only these `schema:v2/ConfigReadResponse.json#` owners are source-blocked:

| Index | Pointer | Node SHA256 |
| --- | --- | --- |
| 3581 | `/definitions/ConfigLayerSource/oneOf/0` | `081019e6b870ca50271f543c398ec7a5c6f26685a728d6241013139c26cfbeb2` |
| 3582 | `/definitions/ConfigLayerSource/oneOf/0/properties/file` | `17985e2482ebd79bf8c0710e964af31ba4e1c04fedc44a9fbe1b9cb6c81369c8` |
| 3583 | `/definitions/ConfigLayerSource/oneOf/0/properties/file/allOf/0` | `85b73ba1a78c40839a9e48b1e72023c66bba5c7f1922229b01a93922acea475d` |
| 3584 | `/definitions/ConfigLayerSource/oneOf/0/properties/type` | `17f284d61c1de4b9e16a91a916981f138f66720754d2053fe142c2adba1759aa` |
| 3585 | `/definitions/ConfigLayerSource/oneOf/0/properties/type/enum/0` | `40ca354a4c74d5f47403095268c8adda2238d29b29bdcb4e3cdafbf1a799eae8` |

All 5,259 extracted Rust files byte-match the official source archive, SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Sixteen whole production files bind the complete chain and module declarations.
The canonical ConfigReadResponse export matches its generated pin, SHA256
`4ec77e1a3eed746037149799c3b6bb8fe7b4b593e5930fc9f410e6282de9df50`;
all five physical nodes are recomputed and matched. Other ConfigLayerSource
copies and write responses receive no credit.

Source report `/tmp/samgita-v449-candidate.md`, SHA256
`bcca2156f17144ba99ecffac1cb8cda6bcdf386d25faff9e29cf9e2482a78082`;
binder `/tmp/samgita-v449-bind.py`; whole-source/node binding
`/tmp/samgita-v449-binding/source.json`, SHA256
`f6445826d7ea4fe5ad8bb88d76a3a453f2779f247c6f6d08b01502f53b43c764`;
evidence SHA256
`b0d476b137b9fd9be5b51e992f80913154067ae8ed4d2caeb746d7b1e6e24023`.
All 417 V447 tested source hashes and nine successful command-log hashes remain
exact. No new runtime, test, provider or model process runs for this source-only
unit. Inventory consistency and diff whitespace are checked after documentation.

Contracts: **5,263 implemented / 1,281 missing / 77 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
The prerequisite is an upstream-supported real emitter or an explicitly accepted
immutable target/contract change. Neither is supplied or assumed. No local
workaround, upstream edit, scope waiver, security/permission test or audit, broad
suite, hosted workflow, publication or deployment occurs. A11, legacy/external/
platform and full-goal/release gates remain incomplete. Rollback reverts only
these five limitation records and this documentation. Continue independently
reachable native filesystem ID coverage.
