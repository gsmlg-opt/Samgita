# Compaction history input alias

The default driver validator now accepts the pinned native input alias
`compaction_summary` in `thread/resume.history`. Only the input contract changes;
the original caller tag stays intact, and native Codex serializes, persists and
consumes canonical `compaction` history. Base:
`c60ecd9f8bd450d8d3312704504a913d6b6afca3`.

## Source and reproduction

The immutable target remains Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Its archive SHA256 is
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

`protocol/src/models.rs` declares `#[serde(alias = "compaction_summary")]` on
`ResponseItem::Compaction`. The normal typed request decoder reaches this enum
through `ThreadResumeParams.history`; the supplied-history handler copies the
decoded items into a new native history. The official JSON exporter omits the
input alias. Six complete source files match their pinned archive members.
This is a real ordinary request path; no legacy notification emitter is invented.

Before the repair, the four-case dedicated protocol module fails **three** cases.
The new actual-native profile generates a genuine compaction checkpoint, changes
only its submitted tag, then fails at local `thread/resume` validation. Its initial
location-selected command reports **4 discovered /1 failure /3 excluded**; only
the one new case runs. After the repair, both full owning modules pass **4/0**.
Logs remain at `/tmp/samgita-v351-{protocol,native}-{before,after}.log`.

## Implementation and actual-native oracle

`Schema.Input` augments the exact canonical Compaction input branch's type enum
for `thread/resume`. Every required field, nullable type, metadata constraint and
experimental history-presence rule stays intact. Other variants, output contracts
and original wire values remain unchanged. The earlier legacy dynamic-tool
supplement remains separate and retains its existing behavior.

The generator derives the alias from complete pinned `models.rs`, verifies source
and official-export structure, and emits a second labeled input descriptor.
Inventory generation/checking and package provenance include it. All **770 official
JSON exports**, previous pinned artifacts and the original dynamic-tool descriptor
keep their hashes. The standalone package ships the complete source reference;
it does not compile or execute its Rust tests.

The unchanged Responses fixture supplies the checkpoint's opaque functional data,
not app-server or persistence records. The real binary owns compact/start events,
checkpoint IDs, supplied-history import and continuation. The added profile:

- Captures the genuine native checkpoint and changes only `type` to the alias;
  restoring that key must recover the original complete checkpoint.
- Imports through normal default validation on a different cold PID. Native must
  persist the original canonical items and IDs with no alias row, synthetic
  CompactedItem, metadata restamping, inference or tool work during import.
- Continues once and requires the exact canonical checkpoint in actual provider
  input, `history_initialization:"supplied_history"`, the prescribed answer,
  exactly three total provider requests and no new compaction trigger.
- Checks canonical imported records after completion and process closure, unchanged
  source history/config/provider bytes and the existing owned-process cleanup.

This qualifies one current-client alias with omitted checkpoint metadata. It does
not claim native alias emission, decryption, a production database migration,
every historical compaction format, a third native rehydration, an independent
outgoing-byte recorder or real backend acceptance. Structural optional-metadata
cases and wire equality have separate protocol coverage.

## Final permitted checks

All eleven final commands pass at seeds `501432` and `987654`:

| Check | Final result |
| --- | --- |
| Five reviewed protocol modules | **21/0 twice**, no exclusions |
| Eleven reviewed ordinary driver modules | **54/0 twice**, no exclusions; 62.805/63.106s |
| Driver composition | 25 actual-binary cases and 29 scripted Session fault cases per seed |
| Outside-umbrella consumer | **1/0**, local input-supplement checks and actual native initialization/list |
| Package compile/scoped format | Pass with warnings as errors |
| Root strict Credo | Pass on **513 sources** |
| Python AST/inventory consistency | Six files parse; inventory passes |
| Before/after executable-source guard | **322** stable files; **312** other previous sources unchanged |

The first final-matrix attempt stops on strict Credo's unchanged nesting limit.
Extracting the branch transformation into `response_input/1` keeps the same enum
guard and tag update; no assertion, deadline or schema constraint changes. The
failed five-command result stays recorded. The complete final matrix reruns on
the final helper and passes. Session, process cleanup, providers and earlier
legacy dynamic-tool tests remain unchanged.

Exact command arrays/environments: `/tmp/samgita-v351-run.py` and `-final-run.py`.
Artifacts: `/tmp/samgita-v351-functional-checks/`. Immutable source evidence:
`/tmp/samgita-v351-source.py`; manifest binding: `-bind.py --verify`.
The separate strict completeness command exits **1**, not a passing result.

| Artifact | SHA256 |
| --- | --- |
| Initial stopped `results.json` | `20dc1af77c775ee2f66392626ad018aa7b5066cbc0351d2e09bdc016de19ab67` |
| Source and reproduction evidence | `3e2cbfea46cb93c24bd0e7f6c856d41a186cba9cbb137d1b79103550104db805` |
| Final `final/results.json` | `c1925bb332e6982c41240735d414304983d8c48d0b8064d2a0c3780fa39398eb` |
| Final `final/source.json` | `e4d6b0da0f47a98e6e46ec58946223c2b692b372826caae3144beac401e21c4f` |

## Migration, rollback and remaining gates

There is no database migration or historical-data rewrite. Existing uncertain
operations and platform journals remain untouched. Native already accepts the
alias and writes canonical data. Rolling back restores the prior local alias
rejection; preserve all histories and uncertain operations, and never redispatch
possibly executed work as part of rollback.

Four requirement records receive supplemental evidence only. No state or physical
schema owner is promoted: contracts remain **5,018 implemented /1,537 missing /66
blocked**, requirements **462 implemented /12 missing /11 blocked**, **zero
verified**. An alias absent from official JSON does not create an invented physical
schema owner. Broad default/negotiation requirements remain missing.

Ordinary owned launches use fixed YOLO settings. Security/credential/authentication/
authorization/permission/approval tests, audits, mixed broad suites and hosted
workflows remain unrun and their gates incomplete. No populated-database/platform
result is promoted on this changed schema. A11, producerless legacy paths,
external/OS/platform profiles and full compatibility remain incomplete. No tag,
publication or deployment occurs.
