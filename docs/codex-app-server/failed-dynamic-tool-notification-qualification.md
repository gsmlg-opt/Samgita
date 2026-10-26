# Native failed dynamic-tool notification

The actual pinned Codex emits a failed dynamic-tool item after an explicit client
`success:false` response, preserves its failure content for the next model request,
and completes the overall turn normally. This qualifies a missing live-notification
branch; no new driver defect was demonstrated. Base:
`e1e9b49831a7c94a263b705b9ca698391760e0fc`.

## Source and physical ownership

Target remains Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Nine complete relevant source files byte-match the immutable archive. All **770
official JSON exports**, every pinned artifact and all prior executable sources
remain unchanged.

`core/src/tools/handlers/dynamic.rs:218–270` emits the initial inProgress item,
awaits the correlated real client response, maps explicit false to Failed and
emits ItemCompleted with exact content, false success and duration. Native session
and app-server mapping attach timestamps and broadcast the real `item/completed`
notification. The ServerNotification root reaches this status through
ItemCompletedNotification and the dynamicToolCall ThreadItem variant.

The exact missing owner is **2120**:
`schema:ServerNotification.json#/definitions/DynamicToolCallStatus/enum/2`, literal
`failed`. The selected root/enum/item/envelope definitions are identical in stable
and experimental exports. Existing live inProgress/completed owners 2118/2119 and
persisted failed owner 5354 already have their own scoped evidence. This unit
does not promote them or propagate persisted-history proof to the live root.

The earlier persisted-tool suite overlaps this behavior, but it uses a mixed
helper containing a restricted assertion. Neither that suite nor the mixed native
interaction profile is run here. The retained original tests remain intact.

## Actual native behavior

One dedicated ordinary case uses the unchanged `model_fixture.py` dynamic-tool
Responses backend and an owned Linux musl stdio native process with fixed YOLO.
The backend supplies model tool-call/text responses; it never creates app-server
notifications or history. Every protocol event in this test is emitted by Codex.

The test observes one actual tool call with exact thread/turn/call IDs, name,
namespace and arguments. Exactly one inference exists while the response is held.
It returns independently prescribed UTF-8 failure text with `success:false` once.
The native completed map must contain exactly the failed status, original content,
false success and original call identity, with native duration and completion time.
The corresponding started map retains null result/duration and inProgress status.

The **actual received completed envelope** passes the official stable
ServerNotification root schema and a lossless Wire encode/decode round trip under
normal Session validation. The actual second provider request contains exactly the
failure output and original call ID. A fixed assistant answer and completed overall
turn follow in the native event sequence. A failed tool item is not a failed
transport, a failed overall turn or Samgita Task acceptance.

Collection is bounded to 256 events, 1MiB and 32 method types with explicit deadlines.
Generation and monotonic local sequence association are checked. There are exactly
two inferences, no retry, unchanged config/script bytes, an empty workspace and
complete owned native/provider process-owner and port cleanup. The standalone
owning module initially reports **1/0**; log: `/tmp/samgita-v357-native.log`.
No production code, existing test, provider fixture, deadline or assertion is changed.

## Final permitted checks

All eleven final commands pass at seeds `501432` and `987654`:

| Check | Final result |
| --- | --- |
| Nine reviewed protocol modules | **42/0 twice**, no exclusions |
| Eighteen reviewed ordinary driver modules | **120/0 twice**, no exclusions; 163.788/165.937s |
| Driver composition per seed | 91 actual-binary cases and 29 scripted Session fault cases |
| Outside-umbrella consumer | **1/0** |
| Scoped format/package compile | Pass with warnings as errors |
| Root strict Credo | Pass on **519 sources** |
| Python AST/inventory consistency | Eight files parse; inventory passes |
| Before/after executable-source guard | **337** stable files; **336** prior files unchanged |

Runner: `/tmp/samgita-v357-run.py`; exact command arrays/logs:
`/tmp/samgita-v357-functional-checks/final/`. Source/binding programs:
`/tmp/samgita-v357-{source,bind}.py`; binding uses `--verify` after manifest update.
Independent source-only review SHA256:
`591c445e7c0053ced2774cfe703a7f71b55375bd6636813a6f76fe2e03e0eeb9`.
Strict completeness separately exits **1** for remaining unverified requirements.

| Artifact | SHA256 |
| --- | --- |
| Source evidence | `cd39450c9f9ee337368619479d116031d0216bb771d05ee0f4752f95fb96cf08` |
| Final `results.json` | `6fc663d586c255384c294eba8369040cf7011cb1bc2b2eb1838f751e470c2d43` |
| Final `source.json` | `6bb9b59b7e080976241a653e35ca2f037f4a4a9ad1d3d846e7e4c603946911d8` |

## Rollback and remaining gates

Rollback removes only this additional test/evidence mapping. No application state,
database migration, history rewrite or production change occurs. Session, process
cleanup, schema/decoder supplements and provider fixtures remain unchanged. Never
redispatch uncertain work as part of rollback.

Only owner2120 receives the scoped implementation/evidence update. Contracts become
**5,019 implemented /1,536 missing /66 blocked**; requirements stay **462 implemented
/12 missing /11 blocked**, **zero verified**. Requirement records, sibling and
persisted owners keep their states. No full method/family,
every content variant, RPC-error/cancellation, other transport/OS or external model
qualification follows from this one branch. Full compatibility remains incomplete.

Security/credential/authentication/authorization/permission/approval tests, audits,
mixed broad suites and hosted workflows remain unrun/incomplete under the user's
restriction. A11, producerless legacy paths and external/OS/platform/final aggregate
gates remain open. No tag, publication, deployment or live-credential change occurs.
