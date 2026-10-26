# Personality unit-object inputs

Default validation accepts native Personality objects for `none`, `friendly` and
`pragmatic`, with null or empty-map payload. Actual fresh instruction construction,
later updates and warm/cold resume retain their distinct native semantics. Base:
`b828bda05e4ad12d96aa64da54ab5bf657c78b08`.

## Pin, discrepancy and correction

Target is unchanged: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Eleven complete relevant source files match the immutable source archive. Existing
lock-pinned serde source, crate and license references are checked separately.

`protocol/src/config_types.rs:314–336` declares three lowercase unit variants.
The real internally tagged ClientRequest buffers nested params through pinned
serde 1.0.228; known one-key unit objects accept null or empty-map payload. Exact
schema-reference traversal reaches Personality from `thread/start`,
`thread/resume`, `thread/settings/update` and `turn/start`, with no active-turn
settings or fork route.

The dedicated protocol regression initially reports **5/3** and the two expanded
native modules **11/11**, all native failures local `schema_violation` at object
input. After correction these report **5/0** and **11/0**. Logs:
`/tmp/samgita-v356-{protocol,native}-{before,after}.log`. The original invalid-style
diagnostic still uses wire-only validation deliberately; all new object cases use
normal default validation. No deadline/assertion/capture bound is relaxed.

The sixth input descriptor preserves the full original canonical schema,
including its deprecation description, inside an input-only union with three
disjoint required-key object branches. Unknown/multiple keys and non-unit payloads
remain errors. Required IDs, null/omission semantics and existing experimental
status stay intact. Composition tests include every overlapping dynamic-tool,
compaction, ModeKind, MultiAgent and summary correction.

The first generator check omitted the canonical deprecation description from its
exact expected shape and rejected the existing export. The comparison was corrected
to include that unchanged description before generation. All **770 official JSON
exports**, output schemas and every previous pinned artifact remain unchanged.
Canonical physical owners 270–272 were already scoped implemented; no object owner
or state promotion is invented.

## Native behavior

The unchanged assistant-only Responses fixture supplies literal text. Actual Codex
owns decoding, configuration, instruction rendering, selected snapshots, native
history and process restart. Eleven ordinary native cases use fixed YOLO:

- Six fresh object profiles start from pragmatic configuration. The original
  thread/start map is captured; an independent summary-only snapshot barrier shows
  the canonical selected personality without inference. Exactly one deliberate
  turn produces the complete prescribed developer instructions: stripped for enum
  `none`, literal for friendly/pragmatic. Outer null remains absence of override;
  it is not the present enum value `none`.
- Both original scalar profiles preserve all nine original cases and add the six
  objects, with fifteen exact turn requests each. Selected canonical metadata may
  change while provider instructions retain the original literal/stripped base.
  Existing invalid-input diagnostics, histories and no-extra-inference checks stay.
- One idle-thread journey starts with stripped instructions, applies six captured
  object updates and observes real canonical selected snapshots. Updates do not
  infer. Seven omitted-personality turns preserve the inherited stripped base.
- Subscribed warm rejoin covers all original cases plus six object overrides.
  Selection stays `none`, instructions remain inherited and eleven turns complete.
- Cold resume covers ten independently created parents and genuine PID replacement
  before each resume. Configured fallback handles original omission/null; explicit
  scalar/object overrides select canonical values. All continuations retain the
  inherited stripped base, with exactly twenty requests in the complete journey.

New/strengthened assertions bind fixed assistant answers in live items, completed
saved user/assistant items, exact original outgoing maps, selected snapshot
association, request budgets, unchanged config bytes, empty workspace, clean
Session state and existing process cleanup. Capture stays bounded to 32 frames and
4KiB per frame; summary-only barriers remain outside the targeted capture. Cold
restart checks actual old PID disappearance and a different replacement PID.

These tests qualify real cold **personality selection and continuation**, not raw
rollout immutability, distinct friendly/pragmatic styles or external model behavior.
No fixture produces app-server settings or history. The outside consumer only adds
local validation of the 24 object combinations; its separate native journey remains
initialization/listing.

## Final permitted checks

All eleven final commands pass at seeds `501432` and `987654`:

| Check | Final result |
| --- | --- |
| Nine reviewed protocol modules | **42/0 twice**, no exclusions |
| Seventeen reviewed ordinary driver modules | **119/0 twice**, no exclusions; 163.269/164.407s |
| Driver composition per seed | 90 actual-binary cases and 29 scripted Session fault cases |
| Outside-umbrella consumer | **1/0** |
| Scoped format/package compile | Pass with warnings as errors |
| Root strict Credo | Pass on **518 sources** |
| Python AST/inventory consistency | Eight files parse; inventory passes |
| Before/after executable-source guard | **336** stable files; **328** other prior files unchanged |

Runner: `/tmp/samgita-v356-run.py`; exact command arrays/logs:
`/tmp/samgita-v356-functional-checks/final/`. Source/binding programs:
`/tmp/samgita-v356-{source,bind}.py`; binding uses `--verify` after manifest update.
Independent source-only review SHA256:
`22934d674262a9c89fed713adc61c4d01dfe6b5e578f1f43270a951f3ccb988e`.
Strict completeness separately exits **1** for remaining unverified requirements.

| Artifact | SHA256 |
| --- | --- |
| Source/reproduction evidence | `ed95d8081e64ec6e5d96d9a8bc7b2ab824944ffc9105edcb2aa4c985ea8c9a1d` |
| Final `results.json` | `c696bc54b65224d18bb6b8b93afaeaed8b1db007beeb5b6bd3e297ecbb082ec0` |
| Final `source.json` | `6ab7d07f234e0890b845329400df5b4308afa91c26d01935103261edd01032f9` |

## Rollback and remaining gates

No database migration, task transition, native history rewrite or production change
occurs. Rollback restores local rejection of Personality objects. Preserve native
histories and journals; never redispatch uncertain operations while rolling back.
Session, cleanup, provider fixtures and prior descriptors remain unchanged.

Ten requirement records receive supplemental evidence only. Counts remain
**5,018 implemented /1,537 missing /66 blocked** contracts, **462 implemented
/12 missing /11 blocked** requirements, **zero verified**. The next selected ordinary
gap is live failed dynamic-tool notification owner 2120; prior persistence evidence
does not automatically qualify that separate physical root.

Security/credential/authentication/authorization/permission/approval tests, audits,
mixed broad suites and hosted workflows remain unrun/incomplete under the user's
restriction. A11, producerless legacy paths and external/OS/platform/final aggregate
gates remain open. No tag, publication, deployment or live-credential change occurs.
