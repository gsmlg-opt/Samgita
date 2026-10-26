# Explicit canonical input enums

This evidence binding qualifies exactly two physical ClientRequest owners:
LocalShellStatus.incomplete234 and Personality.none270. Existing real-native
functional cases already supply these literal values and observe their effects.
No executable source or test changes, and no tests are rerun for this binding.

## Explicit inputs and actual native effects

`native_turn_personality_test.exs` starts independent none/friendly threads and
explicitly submits personality:none in a later turn. It checks the complete
outgoing turn params, correlated completion, actual provider instructions and
an independent summary-only native applied-settings snapshot. Initial none
removes exactly the synthetic template's Personality section; later settings
changes do not rewrite an already fixed initial base. Null/omitted followups
retain the selected value. `native_resume_personality_values_test.exs` also
submits explicit none on cold resume, distinguishes it from configured pragmatic,
and observes inherited stripped instructions without an automatic inference.
The local peer returns ordinary assistant output only. These are native setting
and instruction-construction effects, not an external model-style assessment.

`native_supplied_local_shell_history_test.exs` receives an incomplete shell
through the current generic Responses decoder. Stock Codex produces the lsh_ ID,
absent call ID, complete canonical action nulls and source-turn metadata. The
entire genuine raw shell equals the durable map. A separate cold native imports
the original user/shell maps, then an explicit followup consumes the expected
provider copy with only passthrough metadata removed. The independently fixed
oracle includes status:incomplete. Provider counts remain **1 → 1 → 2**. The
second profile changes only client metadata to null. Neither runs a shell,
synthesizes a paired output or establishes genuine legacy backend emission.
See [the LocalShell history evidence](local-shell-history-inputs-qualification.md).

## Exact source ownership

Pin: rust-v0.163.0, source83086188ae0614bd882818ff1aa23f3194962012,
binary SHA256399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215.
Thirty-three complete source files match the immutable official archive.
The actual thread/start, thread/resume and turn/start personality references,
and thread/resume.history ResponseItem→LocalShellStatus reference, resolve to
the exact canonical definitions. Each node is independently hashed.

| Physical owner | ClientRequest pointer | Literal |
| --- | --- | --- |
| 234 | /definitions/LocalShellStatus/enum/2 | incomplete |
| 270 | /definitions/Personality/enum/0 | none |

`protocol/src/config_types.rs:330–336` defines none. The real request processors
forward the typed value; `models-manager/src/model_info.rs:46–86` implements
initial template stripping, `core/src/session/mod.rs:798–832` fixes the initial
base and `step_settings.rs:281–283` updates the selected setting. For incomplete,
the current generic decoder, non-tool router path, native recording/raw-event
forwarding and supplied-history reconstruction establish the limited data path
documented in the LocalShell evidence. No absent legacy producer is invented.

ClientInfo.title89 and LocalShellStatus.in_progress233 remain missing and
byte-identical. Sibling enums, schema copies, references, enclosing methods and
legacy lifecycle contracts inherit no qualification from this binding.

## Reused functional evidence and fresh binding checks

Base commit e6765de4af20f7f45e9f6c8a6e8d650cf0411cca contains the latest reviewed
**49-file, 99/0 twice** functional matrix, seeds501432/987654. Those runs also
pass scoped format, warnings-as-errors compile, strict Credo, outside actual-binary
consumer1/0 and27 fixture ASTs. This documentation-only unit reuses those exact
results; it does not claim a new run. All **297 current and committed guarded
sources** equal that tested code, including all three owning native modules,
their helpers, fixtures, driver/native-schema source and retained package locks.

Artifacts: /tmp/samgita-v323-functional-checks/. The fresh binding verifies the
complete pinned files, four nodes, request references, unchanged guarded source,
retained result/log hashes, exactly two promotions and unchanged requirements,
schema identities and planned tests. Inventory consistency passes; strict
completeness still exits **1**.

| Evidence | SHA256 |
| --- | --- |
| Reused V319 results | a4c1422836ebd511efa97eab5cb0d8d0d52c3755f66ac1704f002f35c7d140ae |
| Reused V319 source guard | abd4a8b5e988d33f4ec6b37112f87b71e3b1785058597789ed26d6226b602834 |
| Thirty-three files, four nodes and binding | d6e241c8c6cd780ca9efee98734665bb9185f627edb551009f69f2f3d16ee819 |
| Resulting manifest | 45a15d3106ce4dd28d41fef09ea5de54307eb58163688aae1f3b30a6005abcba |

Contracts: **4,960 implemented / 1,595 missing / 66 blocked**. Requirements:
**462 implemented / 12 missing / 11 blocked**, zero verified. Fixed yolo setup,
bounds and owned-process cleanup remain unchanged. Full history/personality,
legacy execution, external providers, other OS/transports, A11 and full-goal
acceptance remain incomplete. Prohibited security/auth/permission/approval tests,
audits and broad/hosted workflows stay unrun. No release, publication or deployment.
