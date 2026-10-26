# Deprecated multi-agent input representations

Default validation now accepts pinned native `multiAgentMode` inputs omitted
from the official schema: string `none`, and single-key unit objects for `none`,
`explicitRequestOnly` and `proactive`, with `null` or `{}` payload. All three
current request fields are deprecated and ignored by Codex. Parsing these inputs
does not activate delegation or change effective project authority. Base:
`af777bc8cfdabad4a3ffd408d04fd86e63d6ec6a`.

## Source and correction history

Target: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`;
source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

`config_types.rs:340–367` deserializes through `MultiAgentModeWire`, which adds
`None` to the exported type's variants and maps it to `Custom("")`. Actual
request parameter reference graphs reach this decoder from exactly
`thread/start`, `thread/settings/update` and `turn/start`. Request declarations
mark these fields experimental and ignored; native processors omit them from
effective settings and publish `explicitRequestOnly` in start/settings results.

The initial dedicated protocol/native modules fail **4/3** and **3/1** at local
default validation. The string-only repair passes **4/0** and **3/0**, followed
by a **29 protocol /64 driver twice** matrix. That matrix is retained but
superseded: source review discovers that its `{"none":null}` negative case
encodes another native-valid representation as invalid. The corrected tests
make it positive and add source-consistent invalid payloads/extra-key cases;
this is a contract correction, not an assertion skipped to obtain green tests.

The initial null-only dependency interpretation is also insufficient. Codex's
`ClientRequest` is **internally tagged**, buffering nested parameters through
serde `ContentDeserializer`. Its unit decoder accepts `Unit` **or an empty Map**
(`private/de.rs:1301–1318`). The direct serde_json Value unit decoder's null-only
behavior cannot stand in for this actual nested path. An isolated diagnostic
copy characterizes the empty-map forms against the real binary: **6/0**, using
`validation: :wire` only to reach the native decoder. That bypass is not final
acceptance. The expanded ordinary test module uses normal default validation.

The tagged-unit regressions first fail **5/3 protocol** and **6/3 native**.
After correction, the dedicated modules pass **5/0** and **9/0**; the complete
final matrix below covers the final null/empty-map tables without a bypass.
Original and diagnostic logs remain at `/tmp/samgita-v353-*.log`.

## Input contract and pinned dependency evidence

A fourth separate input descriptor adds only the supported missing branches:

| Input | Native type decoding | Current request behavior |
| --- | --- | --- |
| `"none"` | `Custom("")` | Ignored |
| `{"none":null}` or `{"none":{}}` | `Custom("")` | Ignored |
| `{"explicitRequestOnly":null}` or `{"explicitRequestOnly":{}}` | `ExplicitRequestOnly` | Ignored |
| `{"proactive":null}` or `{"proactive":{}}` | `Proactive` | Ignored |

Each added object branch requires its one known key, rejects additional distinct
keys and enumerates exactly `[null, {}]` for its payload. Canonical string/custom
branches and enclosing required fields remain intact. This is a parsed-value
contract; it does not claim rejection of duplicate keys in raw JSON. Caller maps,
wire values and canonical output enums are unchanged. Experimental negotiation
still applies. Corrections compose with existing dynamic-tool/collaboration
corrections rather than masking them with competing method clauses.

Nine complete Codex source files and its full Cargo.lock match their immutable
archive members. Cargo.lock SHA256
`17cdd862471774ba7aef836aaf0a0a3ed76bd23e503b1fc7278c89d1f2719d03`
pins serde `1.0.228` crate checksum
`9a8e94ea7f378bd32cbbd37198a4a91436180c5bb472411e48b5ec2e2124ae9e`.
The complete vendored dependency `private-de.rs` and included MIT license match
their crate members. A generated origin records those digests and exact source
member/URL. These are references only; no Rust code/tests are compiled or run.
Inventory generation checks the exact dependency lock; standalone compilation
and offline generation/checking verify the source/license/origin hashes.

All **770 official JSON exports**, three previous input descriptors and previous
pinned artifacts keep their hashes. No neutral schema, runtime provider or
application configuration dependency is added.

## Actual-native oracle and final checks

Seven new native cases cover the string and all six object forms. Each sends
the original representation through all three entry points with default
validation. The existing bounded delegating Stdio capture requires exact complete
request equality after successful sends, three ordered field-bearing methods and
the same caller value. Summary-only reads retain their original capture behavior.

Every case establishes `concise`, sends the selected input together with a real
change to `detailed`, then waits for the matching `thread/settings/updated`
snapshot. An ACK alone is insufficient; a mode-only no-op need not emit that
event. Selected settings remain exact and public mode stays `explicitRequestOnly`;
zero inference occurs during the updates. One deliberate marked turn must
produce the real assistant answer, exact fixed developer instructions/model,
one user marker, one provider request and native completed-turn history. The
unchanged provider emits Responses text, never app-server frames/history.

The two existing published-value control cases remain. Config bytes, empty
workspace, ready/no-uncertainty state, finite deadlines, bounded transport capture,
recorded cleanup and explicit native PID exit checks remain. Existing collectors
retain finite deadlines; this unit adds no event/byte collection bound or cold
history claim. No actual delegation is observable because native ignores the
field. The outside consumer validates the new forms locally; its actual-native
journey remains initialization/list.

All eleven final commands pass at seeds `501432` and `987654`:

| Check | Final result |
| --- | --- |
| Seven reviewed protocol modules | **30/0 twice**, no exclusions |
| Thirteen reviewed ordinary driver modules | **70/0 twice**, no exclusions; 85.089/85.887s |
| Driver composition | 41 actual-binary cases and 29 scripted Session fault cases per seed |
| Outside-umbrella consumer | **1/0**, local form validation plus actual native smoke |
| Scoped format/package compile | Pass with warnings as errors |
| Root strict Credo | Pass on **515 sources** |
| Python AST/inventory consistency | Seven files parse; inventory passes |
| Before/after executable-source guard | **330** stable files; **319** other previous sources unchanged |

Runner: `/tmp/samgita-v353-tagged-run.py`; artifacts:
`/tmp/samgita-v353-functional-checks/tagged-final/`. The earlier `final/` matrix
and runner remain as superseded evidence. Source/reproduction binding:
`/tmp/samgita-v353-source.py`; manifest binding: `-bind.py --verify`.
Final source-only review SHA256:
`2f3440aa46c71715ae3723bca5b4b754fa3cf54dfcfbf78a5df9f99132c37d92`.
Strict completeness separately exits **1**, not a passing result.

| Artifact | SHA256 |
| --- | --- |
| Superseded string-only `final/results.json` | `251422127492adca6baebdf1443cfcf8403f2d6b9e792d9ac1a411eb1b5b8bd8` |
| Source/reproduction evidence | `4640a60edcecf94c4dc7b22db6ca7af664fddaaa27e2e4e3919c9d7871ebf9c0` |
| Final `tagged-final/results.json` | `3bbc1456fc09d95b28929e53e5a03ededdf30c9d35e1e3aaecbbf229c263783c` |
| Final `tagged-final/source.json` | `1ec3077fda8b2a2dbd231e755933c80197f9b4a898d43bb0755fe9f4d0467af5` |

## Migration, rollback and open gates

No database migration, history rewrite or task transition changes. Session,
owned-process cleanup, model fixtures and previous input regressions remain
unchanged. Rollback restores local rejection of these forms; preserve histories,
journals and uncertain operations without replaying possibly executed work.

Eight requirement records receive supplemental evidence, with no state/physical
owner promotion. Contracts remain **5,018 implemented /1,537 missing /66 blocked**;
requirements **462 implemented /12 missing /11 blocked**; **zero verified**.
The omitted forms have no invented official physical owner. Broad defaults and
negotiation remain missing. The next source-confirmed ordinary candidate is the
separate ModeKind unit-object representation; it has no runtime evidence here.

Ordinary owned launches use fixed YOLO. Security/credential/authentication/
authorization/permission/approval tests, audits, mixed broad suites and hosted
workflows remain unrun/incomplete under the current restriction. A11, producerless
legacy paths, external/OS/platform profiles, full aggregate qualification and the
full goal remain incomplete. No tag, publication or deployment occurs.
