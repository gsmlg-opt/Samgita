# ReasoningSummary unit-object inputs

Default validation now accepts native ReasoningSummary unit objects for `auto`,
`concise`, `detailed` and `none`, with null or empty-map payload. The original
objects reach the pinned binary, which applies canonical values with the real
method's scope. Base: `ed9849a596efb78e4d48442f03ef3257777d9a10`.

## Source and reproduction

Target remains Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

`protocol/src/config_types.rs:59–73` declares these four ordinary lowercase unit
variants. The actual internally tagged ClientRequest buffers nested params
through lock-pinned serde 1.0.228. Its enum decoder accepts one known key and its
unit decoder accepts null or an empty map. Exact request-reference traversal
reaches ReasoningSummary from `thread/settings/update`, `turn/start` and
`turn/settings/update` only. Thirteen complete relevant source files byte-match
the immutable archive; the existing Cargo.lock/crate/decoder/license binding is
checked separately. The dependency reference is never compiled into the package.

Before the correction, the dedicated protocol regression reports **5/3** and the
actual-native module **24/24**. Every native failure is local `schema_violation`
at the submitted object, after ordinary native startup and baseline behavior.
After correction these modules report **5/0** and **24/0**, using normal default
validation throughout. Logs: `/tmp/samgita-v355-{protocol,native}-{before,after}.log`.
No wire-only diagnostic or assertion/deadline/buffer relaxation was used.

The fifth input descriptor keeps the entire canonical schema as one union
alternative, adding four disjoint required-key branches with
`additionalProperties:false` and payload enum `[null, {}]`. Original values,
enclosing identifiers, null/omission semantics and experimental negotiation stay
intact. The composition regression submits summary, ModeKind and deprecated
MultiAgent objects together on overlapping methods. Unknown/multiple keys and
non-unit payloads remain errors. All **770 official JSON exports** and every
previous pinned artifact retain their hashes. Canonical physical owners 354–359
were already scoped implemented; no nonexported owner or state promotion is added.

## Real binary semantics

The 24 new profiles cover each of three methods, four values and two payloads.
The unchanged Responses fixtures emit assistant text or one ordinary dynamic-tool
call; actual Codex owns request decoding, settings, events and persisted history.
Each profile uses fixed ordinary YOLO and a different baseline summary to force
an observable change.

- `turn/start` applies the object, publishes the canonical selected snapshot and
  uses it in the actual provider reasoning map. A subsequent omitted-summary turn
  and a separate outer-null turn keep the selection. Exactly four deliberate
  inferences occur per profile.
- Idle `thread/settings/update` has its empty ACK distinguished from the real
  selected-settings notification. It starts no inference; subsequent omitted/null
  turns use the chosen setting. Exactly three inferences occur per profile.
- `turn/settings/update` operates while the real native dynamic-tool request is
  held. The object, omission and outer null all return `applied` without consuming
  the tool or creating another provider request. After the explicit fixed tool
  result, the next provider request uses the chosen summary. A future turn uses
  the original thread default. Exactly three inferences occur per profile.

For selected `none`, complete provider reasoning is effort-only; no
`reasoning.summary:"none"` is sent. Other values reach that field canonically.
Assertions also bind full original sent maps and response IDs, native turn/thread
metadata, fixed developer instructions/user markers, literal assistant answers,
completed public history, finite event/file bounds, retained script/config/catalog
bytes, empty workspace and complete owned-process cleanup.

After shutdown the native-written `thread_settings_applied.thread_settings`
snapshot retains the selected canonical thread summary, or the unchanged baseline
for turn-local updates. `TurnContextItem.summary` is deliberately unused: pinned
native source hardcodes it to None. Saved bytes alone do not establish cold
restoration. Cold resumed inference and external model behavior remain unqualified.

The outside consumer additionally validates all 24 object combinations locally;
its separate actual-native journey remains initialization/listing. It does not
claim that its native process exercised these summary inputs.

## Final permitted checks

All eleven final commands pass at seeds `501432` and `987654`:

| Check | Final result |
| --- | --- |
| Eight reviewed protocol modules | **37/0 twice**, no exclusions |
| Fifteen reviewed ordinary driver modules | **108/0 twice**, no exclusions; 140.951/142.658s |
| Driver composition per seed | 79 actual-binary cases and 29 scripted Session fault cases |
| Outside-umbrella consumer | **1/0** |
| Scoped format/package compile | Pass with warnings as errors |
| Root strict Credo | Pass on **517 sources** |
| Python AST/inventory consistency | Eight files parse; inventory passes |
| Before/after executable-source guard | **334** stable files; **326** other prior files unchanged |

Runner: `/tmp/samgita-v355-run.py`; exact command arrays and logs:
`/tmp/samgita-v355-functional-checks/final/`. The source/binding programs are
`/tmp/samgita-v355-{source,bind}.py`; binding uses `--verify` after manifest update.
Independent source-only review SHA256:
`64913278b0070ef29db4ed7cbf10f32bb50ff07469a6191d6eeda0b1a059e424`.
Strict completeness separately exits **1**, because required entries remain
unverified; it is not reported as passing.

| Artifact | SHA256 |
| --- | --- |
| Source/reproduction evidence | `7e1bdbb072c27c937647202bac85cc736c3cc686a0630b4e8238c421a48ccd95` |
| Final `results.json` | `262cba70a5d4e915f771baefe91aaacf96125c5ff10b6c38fda2f0f3271bff89` |
| Final `source.json` | `8da3efb1ea756eddd7c3bfbdc423784d117c694a018ef376461877624c016d4e` |

## Rollback and remaining gates

No database migration or task/history rewrite occurs. Session, cleanup, both
provider fixtures and all previous input descriptors remain unchanged. Rollback
restores local rejection of these objects; preserve native histories and journals,
and never redispatch uncertain operations during rollback.

Eight requirement records receive supplemental evidence only. Counts remain
**5,018 implemented /1,537 missing /66 blocked** contracts and **462 implemented
/12 missing /11 blocked** requirements, **zero verified**. Full-goal acceptance
stays incomplete. The next source-confirmed ordinary discrepancy is Personality
object input; no runtime evidence for it is inherited here.

Security/credential/authentication/authorization/permission/approval tests, audits,
mixed broad suites and hosted workflows remain unrun/incomplete under the user's
restriction. A11, producerless legacy paths and external/OS/platform/final aggregate
gates remain open. No tag, publication, deployment or live-credential change occurs.
