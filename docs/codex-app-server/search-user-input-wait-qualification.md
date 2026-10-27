# Native search during ordinary user input

This functional qualification starts from `b90c7cc35ae870ddc92e6fcbf0ce06ea77119290`
on the existing `main`. It adds one ordinary-only driver test and one loopback
Responses fixture; production code, schemas, shared fixtures and cleanup stay
unchanged. Fixed YOLO configuration is launch setup. No security, credentials,
permissions or approval behavior is tested.

Target: Codex `rust-v0.163.0`, immutable source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The test hashes to
`8ebafb0f8a360dd3d3b46a75f11bdd6f4bcefb472fdd9dafb4bb3d2e23dbc9d5`;
the provider hashes to
`0b044293018473a5fcd345eb85d96be4eed081de19460b640579a94ee809f6cb`.

## Native producer and exact contract

Only physical owner 6169 is selected:
`schema:v2/ThreadSearchResponse.json#/definitions/ThreadActiveFlag/enum/1`,
literal `waitingOnUserInput`. The inventory encoder binds its exact node SHA256
`6eaa09674e6a45394bbd63716ad32a20e9ec0a632f51493d11a1883de8d059a5`.
No sibling flag, enclosing alternative or other endpoint inherits this evidence.

The [native input handler:829–862][input] establishes its UserInput guard before
sending the actual `item/tool/requestUserInput` server request. Receiving that
request is an observable readiness barrier. The [status tracker:201–220,
445–461][status] derives the waiting flag from that guard. Actual
[search:2857–2878][search] and [loaded enrichment:38–48][enrichment] obtain and
return the watched status for the real matching thread. The fixture cannot
supply a search status or result.

The loopback provider emits exactly three Responses items: a searchable warmup
answer, one ordinary Plan-mode One/Two question, and the final chosen-answer
completion. It checks the actual third model request contains exactly the
native function output with the original call ID and prescribed One answer.
Stock Codex owns all app-server frames, native IDs, history, status and storage.
The test independently requires exactly three model requests, associated with
the first, second and second actual turns.

Four actual searches use identical original parameters and four distinct RPC
IDs. They require the independently known root, original path and exact snippet:

1. Warmup completion plus a full native history read precede an `idle` result.
2. The native question remains unanswered; search must show exactly
   `activeFlags:["waitingOnUserInput"]`, one interaction and two model requests.
3. The real opaque handle is answered once. Both the matching native
   `serverRequest/resolved` and completed second turn precede the next `idle`
   result. The stored outcome must identify the same handle and reply digest.
4. After checked native shutdown, a distinct cold process searches the same
   retained history and returns `notLoaded`. Search and full history read leave
   loaded IDs empty and cause no additional inference or interaction replay.

`:ok` from the reply is only successful transport send. It is never used as
processing completion. The matching resolution and completed turn establish
that later checkpoint. Full read retains both prescribed user/assistant turns,
the first complete turn stays equal, and the original rollout remains a full
prefix. Final rollout, config/catalog/helper and model-journal bytes remain
exact through cold reads and shutdown. The backward cursor oracle uses the
separate prior history `createdAt * 1000 - 1ms`; this is not reverse-pagination
success evidence.

## Preserved failure and correction

The initial native run failed **1/1** after the wait/reply path, at an invented
whole-object model-metadata expectation. Pinned
[metadata construction:376–430][metadata] and
[metadata fields:31–60][fields] contain additional native fields. The correction
compares exactly the required `thread_id` and `turn_id` projection and their
three-request order. No wait, correlation, persistence or cleanup assertion is
removed. The corrected focused native run passes **1/0**.

The first matrix stops at formatting, requesting one blank line in that new
pipeline. Formatting is corrected before the final run; the failed matrix and
initial native source/log remain retained. Source binding also corrects two
proof-script assumptions: use the inventory's newline-terminated canonical
encoder, and count the 15 input descriptors under `source`, separately from the
10 older supplemental exports. Neither correction changes executable sources,
schemas or the selected node.

## Bounds and verification

Capture is limited to eight 4KiB frames and must contain exactly five: four
original search frames plus the native-ID reply. Calls/initialization stay 5s,
event collection 20s/256 events/1MiB, final drains 128 events/1MiB, files 1MiB
and the case 60s. Both processes require owner completion, closed Port and
absent owned PID. No timeout increase, sleep barrier, state-changing retry,
fabricated history or mock app-server acceptance is used.

The final reviewed matrix passes **87 schema and 154 ordinary driver tests at
both 501432 and 987654**, with outside-umbrella native consumer **1/0**. Scoped
formatting, both package compiles, strict Credo (551 files), fixture syntax and
inventory consistency pass. All eleven commands terminate successfully; the
386-source guard stays identical and all 384 prior sources remain unchanged.
Only 6169 becomes scoped implemented: contracts are **5,069 implemented / 1,486
missing / 66 blocked**, requirements stay **462 implemented / 12 missing / 11
blocked**, and both have zero verified. Strict completeness remains incomplete.

The runner is `/tmp/samgita-v384-run.py`; terminal results, complete command
arrays and source guard are under
`/tmp/samgita-v384-functional-checks/final2/`. The initial
failed formatting run remains under `final/`, and native red/green logs under
`/tmp/samgita-v384-native-*`. The source-only review is
`/tmp/samgita-v384-source-review.md`. Twenty-four complete upstream files match
the immutable source archive; all 770 official exports and 15 input descriptors
remain exact.

Prohibited checks, broad suites containing them and hosted workflows remain
unrun. Full compatibility, A11, unavailable legacy producers, external/backend/
OS/platform profiles and release gates remain incomplete. Nothing is published
or deployed. Rollback removes only this unit's two new functional fixtures and
exact evidence; production state and historical records are unaffected.

[input]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/bespoke_event_handling.rs#L829-L862
[status]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/thread_status.rs#L445-L461
[search]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L2857-L2878
[enrichment]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_enrichment.rs#L38-L48
[metadata]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/turn_metadata.rs#L376-L430
[fields]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/responses_metadata.rs#L31-L60
