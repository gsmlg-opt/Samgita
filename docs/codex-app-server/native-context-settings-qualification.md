# Native resume collaboration and turn runtime roots

Current source-only follow-up: [the exact nullable-result prerequisite](ordinary-null-result-prerequisites.md)
enumerates both pinned production resume constructors, each using Some. It adds
no null success and leaves owner6028 missing; the nonnull evidence below retains
its original scope.

V395 starts from `58e2ef00fd7fccb93dd1478d17b627e8f9654782` on `main`.
Two new ordinary tests qualify narrowly selected native context contracts.
Production code, shared fixtures, schemas, configuration and locks are unchanged.

Target: official Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
All **29** complete producer/conversion/persistence sources match their unique
immutable archive members. Both exact canonical nodes match independently.

| Owner | Physical schema contract after `schema:` | Scoped observation |
| --- | --- | --- |
| 6027 | `v2/ThreadResumeResponse.json#/properties/collaborationMode/anyOf/0` | Complete nonnull Plan and Default result objects |
| 6536 | `v2/TurnStartParams.json#/properties/runtimeWorkspaceRoots` | Ordered replacement/deduplication, omission/null retention and empty clearing |

## Loaded resume and the real persistence prerequisite

The [resume scenario](../../apps/samgita_codex_driver/test/native_resume_collaboration_result_test.exs)
uses two sequential owned native processes and a different persistent paginated
root in each. Each independently prescribed Plan/Default object has its own
literal instruction marker and explicit null effort. A matching applied-settings
notification precedes each resume. All four actual resume results must preserve
the complete expected collaboration object, known model/provider/cwd and native
thread identity; `excludeTurns:true` intentionally returns an empty turn array.

The first zero-inference draft failed before that target assertion:
`thread/resume` returned **-32600**, `no rollout found for thread id ...`.
A diagnostic-only `assert/2` draft raised `MatchError`; an exact success/error
case then exposed the native error without relaxing success requirements.
The proposed fresh-empty full read next returned **-32601**,
`list_turns is not supported yet`. All red sources/logs remain under
`/tmp/samgita-v395-native/resume-{result,diagnostic,diagnostic-case,materialized}/`.
No passing zero-inference or empty-read materialization claim is retained.

The actual source comment at [thread_processor.rs:1731][fresh] identifies lazy
rollout creation. Accepted real input passes `PersistContext::TurnStart` through
`core/src/session/turn.rs:379–385`, `core/src/hook_runtime.rs:716–739` and
`core/src/session/mod.rs:5221–5277,1522–1538`, then LiveThread/live writer/recorder
materialize the canonical rollout. The loaded resume reads stored metadata at
`thread_processor.rs:4524,4842`; its listener emits
`Some(collaboration_mode)` at [thread_lifecycle.rs:929][resume].

The final fixture completes one assistant-only warmup per new root, with distinct
literal input, native started/completed turn and item identities, prescribed
answer and independent provider request metadata. Native full reads retain each
complete original one-turn history before and after both mode/resume operations.
The journal stays frozen through settings, resumes, process closure and the next
initialization. Exactly **two** model requests occur, both to the local fixture.
No rollout or SQLite row is seeded. This corrects a fixture prerequisite while
retaining the complete target result and history assertions.

Exactly **30** original request/response pairs have unique owned IDs. Incoming
frames precede Session decoding; outgoing maps/bytes, incoming full decoded maps
and original-frame decoding must agree with each actual exchange. Raw incoming
evidence excludes JSONL delimiters and OS read chunks. Capture remains32 frames
per direction,4KiB outgoing/64KiB incoming,1MiB total; events remain256/1MiB,
snapshots1MiB and requests/settings remain5s, turns20s, case60s. Checked owner/Port/PID
shutdown and failure cleanup remain required. The second process creates a new
root; it does not prove cold mode persistence of the old thread.

## Ordinary turn roots as current context

The [turn-root scenario](../../apps/samgita_codex_driver/test/native_turn_runtime_roots_test.exs)
drives four real assistant-only turns in one paginated thread:
`[B,A,B] → [B,A]`, omission retains `[B,A]`, explicit null retains `[B,A]`, and
`[]` clears it. Expected paths/order come from two empty owned fixture directories.
Original turn frames retain exact field presence/value. All four native turns,
eight unique completed items and independent provider marker/thread/turn metadata
remain checked; the complete ordered history is retained.

After each completion an alternating summary-only update supplies a matching
native settings barrier. It carries no root override. Public loaded environment
maps must then equal the prescribed local ID/cwd/root vector. Repeated final
whole reads preserve the empty vector and full history; rollout/journal/input
bytes and empty directories remain stable through checked process cleanup.
Exactly **18** correlated raw RPC pairs and **four** model requests occur.
The same capture/event/snapshot/request/turn/case bounds remain in force.

The typed input at [turn.rs:222–229][roots] and real handler
`turn_processor.rs:592–597,773–792` distinguish None from Some(empty).
`request_processors.rs:697–705` retains first occurrences without sorting;
`core/src/session/session.rs:431–448` applies replacement/retention, and native
environment selection/conversion supplies the public snapshot. Root-only turns
do not promise an unconditional settings checkpoint: `session/mod.rs:4919–4943`
conditions it on full-context injection. This test qualifies sticky live context,
without claiming cold-root restoration or filesystem access behavior.

## Final-source checks and limits

Each new module passes its focused native **1/0** run. The final eight-file block
adds both to V394's six reviewed ordinary modules and passes **8/0** at seeds
**501432** and **987654**, no exclusions. Scoped format, driver warning-free
compile, root strict Credo and offline inventory consistency pass. Environment
remains Elixir1.18.5/OTP27.3.4.17, test mode, two schedulers and the pinned binary;
ordinary launches retain fixed YOLO setup. No security or permission behavior is
part of these scenarios.

Runner/results/log hashes: `/tmp/samgita-v395-run.py` and
`/tmp/samgita-v395-functional-checks/final/`. Its **391** guarded sources match
before/after; all **389** prior sources remain unchanged and the two new modules
are added. Source/node binding: `/tmp/samgita-v395-source.py` and
`/tmp/samgita-v395-source/evidence.json`, SHA256
`44036d0f4a2432707881641bc9283b72268c9ed63187b101935815abcbe4e0db`.
The final resume/root test hashes are respectively
`145a5bfe6ffb23645c720f4973ef005c7e02e68aae942c6f6f37ad0667fdd66b` and
`55f8af2caa59e02d284e868d4a85fcc6be5df55e4db7e1e9f1d3e7f11478e6ed`.
Final results/guard SHA256 values are respectively
`07e216f3e5d823d83cedc4ac93908ec89c503a037435a00bdafbf1626537c804` and
`f158cfaeacfe104584330bcb0494c66718dd5a7726c52848891eb7a6143846b1`.
Manifest binding: `/tmp/samgita-v395-bind.py` and
`/tmp/samgita-v395-binding/evidence.json`. Root strict Credo reports557 files;
the runtime block contains only the eight explicitly selected ordinary modules.

Only **6027/6536** gain scoped implemented evidence: contracts become
**5,085 implemented /1,470 missing /66 blocked**; requirements remain
**462 implemented /12 missing /11 blocked**, zero verified in both. Resume null,
aliases, other context variants/transports/platforms and broader families do not
inherit acceptance. Strict completeness remains failed. Earlier larger-suite and
outside-consumer runs retain their original exact-source scope; none is rerun or
claimed by this unit.

Prohibited security/credential/authentication/authorization/permission/approval
tests/audits, mixed broad suites and hosted workflows remain unrun. A11,
source-unavailable producers, real external/OS/platform acceptance, full
compatibility and release gates remain incomplete. No publication or deployment
occurs. Rollback removes only these new tests and exact evidence mappings;
historical data and runtime behavior remain unchanged. Continue the separately
reachable ordinary hook configuration-error/recovery profile.

[fresh]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L1731-L1738
[resume]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_lifecycle.rs#L929
[roots]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/turn.rs#L222-L229
