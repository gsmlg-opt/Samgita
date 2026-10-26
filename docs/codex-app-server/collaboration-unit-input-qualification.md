# Collaboration mode unit-object inputs

Default validation now accepts native ModeKind unit objects for `plan`, `default`,
`code`, `pair_programming`, `execute` and `custom`, with `null` or `{}` payload.
Caller objects stay intact; the real binary applies Plan/Default parsing and
persists canonical string modes. Base:
`1fdde83f44fad7ae75e56617e072c594fe67b825`.

## Source, reproduction and narrow correction

Target remains Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

ModeKind's source declares ordinary unit variants and the four Default aliases.
The actual internally tagged ClientRequest buffers nested params through the
pinned serde ContentDeserializer. Its enum decoder accepts one known key, and
its unit decoder accepts null or an empty map. Request-parameter traversal reaches
this type only from `thread/settings/update` and `turn/start`. Eleven complete
Codex files, including Cargo.lock, match the immutable archive; the previously
vendored serde source/license match its lock-pinned crate. The
[previous input repair](deprecated-mode-input-qualification.md) records that
dependency provenance and the distinction from direct Value unit decoding.

Before this correction, the expanded protocol module fails **6/2** and the full
native module **19/12**: all twelve new object cases fail local validation, while
seven prior cases pass. An isolated actual-binary diagnostic copy reports
**19/0** with `validation: :wire`, characterizing both null and empty-map forms.
That diagnostic does not count as final acceptance. After correction, the normal
default-validation modules report **6/0** and **19/0**. Logs remain at
`/tmp/samgita-v354-{protocol,native}-{before,after}.log` and
`/tmp/samgita-v354-native-characterization.log`.

Only the collaboration input descriptor changes. It retains the entire original
string contract plus its four aliases and adds six disjoint required-key object
branches with `additionalProperties:false` and payload enum `[null, {}]`.
Settings constraints, invalid-input rejection and experimental negotiation remain
intact. Output schemas and outgoing values are unchanged. Existing exact branch
generation and dependency-reference checks are shared with the previous
MultiAgent correction; that descriptor remains byte-identical.

All **770 official JSON exports** and every other pinned artifact retain their
hashes. No new physical enum owner is invented for nonexported representations.
Canonical Plan/Default owners are already scoped implemented; this extension
does not promote unrelated nullable branches or whole-method coverage.

## Real binary behavior

Twelve added native profiles cover each key with both unit payload forms. The
unchanged Responses-only fixture emits literal proposed-plan text, never
app-server settings, items or persistence records. Every profile uses ordinary
fixed YOLO and normal default validation, with the original object sent in both
settings/update and turn/start.

- Default and alias objects reuse the real applied-snapshot barriers, explicit
  Plan baseline and selected turn override. They must emit the exact ordinary
  assistant message containing the proposed-plan tags literally, preserve the
  selected developer instructions/user marker in actual provider input, and
  persist the complete canonical Default collaboration context.
- Plan objects first await the real applied Plan snapshot, then must emit native
  Plan lifecycle/items with the prescribed parsed body, identity and bounded
  timestamps. Native turn context independently records canonical `plan` and
  `mock-model`. This does not qualify every built-in instruction/effort field;
  the stronger complete context assertion belongs to Default profiles.
- Warm and first cold selective content reads preserve actual live items,
  timestamps and full saved turns. Native PID replacement, unchanged retained
  rollout/config/model/provider-script/request bytes, one inference per profile,
  no work during cold reads and existing checked shutdown all remain asserted.

Two structural cases add complete object/wire retention, unchanged official
rejection and invalid object shapes. Existing negotiation cases also cover the
objects. No assertion/deadline/bound is relaxed. The outside consumer validates
all forms locally, then retains its actual-native initialization/list journey;
it does not submit mode objects to that consumer's native process.

There is no independent outgoing transport recorder, cold resumed inference,
full mode-default/delegation coverage or external model acceptance in this unit.
Parsed-value validation does not claim raw duplicate-key rejection.

## Final permitted checks

All eleven final commands pass at seeds `501432` and `987654`:

| Check | Final result |
| --- | --- |
| Seven reviewed protocol modules | **32/0 twice**, no exclusions |
| Thirteen reviewed ordinary driver modules | **82/0 twice**, no exclusions; 105.917/105.939s |
| Driver composition | 53 actual-binary cases and 29 scripted Session fault cases per seed |
| Outside-umbrella consumer | **1/0** |
| Scoped format/package compile | Pass with warnings as errors |
| Root strict Credo | Pass on **515 sources** |
| Python AST/inventory consistency | Seven files parse; inventory passes |
| Before/after executable-source guard | **330** stable files; **323** other previous sources unchanged |

Runner: `/tmp/samgita-v354-run.py`; artifacts:
`/tmp/samgita-v354-functional-checks/`. Source binding: `-source.py`; manifest
binding: `-bind.py --verify`. Source-only review SHA256:
`a35849bc0286fbdd7731a3745aaaa7c8a4c70dd81dcb01c0a06fe672f54314ac`.
Strict completeness separately exits **1**, not a passing result.

| Artifact | SHA256 |
| --- | --- |
| Source/reproduction evidence | `0c9b1ef05518f6c47069c31259130b950d00a932a3d31a8b0a7e007c51a6838e` |
| Final `final/results.json` | `933cf5b5f9a4901879d4ebff3392ecbce5d64a9087be1c1744db1238449e657e` |
| Final `final/source.json` | `2cc8c621fe112a5566c8f63faddfddaf3efc82fc021eb8ca1bc4e86d5ace648b` |

## Rollback and remaining gates

No database migration, task transition or history rewrite occurs. Session,
cleanup, model fixtures and the older MultiAgent/dynamic-tool/compaction
descriptors remain unchanged. Rollback restores local rejection of mode objects
while preserving existing string-alias support; keep histories/journals and never
redispatch uncertain work during rollback.

Six requirement records receive supplemental evidence only. Contracts remain
**5,018 implemented /1,537 missing /66 blocked**, requirements **462 implemented
/12 missing /11 blocked**, **zero verified**. Broad defaults/negotiation and all
required full-goal acceptance remain incomplete. The next independently identified
ordinary candidate is ReasoningSummary input representation; no runtime evidence
for it is inherited here.

Security/credential/authentication/authorization/permission/approval tests, audits,
mixed broad suites and hosted workflows remain unrun/incomplete under the current
restriction. A11, producerless legacy paths and external/OS/platform/final
aggregate gates remain open. No tag, publication or deployment occurs.
