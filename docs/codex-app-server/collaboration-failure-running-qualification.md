# Native failed and running child snapshots

The pinned native parent receives a failed child's exact error, closes that
child, then closes another child after its real provider request starts. It
continues to a normal final answer. Live and cold persisted collaboration items
retain the correct error and pre-close running snapshots. This qualifies five
missing output owners; no driver defect was demonstrated.
Base: `11c4ed62a80c0cc7ca8d088d091e0cc2d02ce477`.

## Producer and deterministic setup

Target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Thirteen complete relevant files match the immutable archive. All **770 official
JSON exports**, every pinned artifact and all prior executable sources remain
unchanged.

`responses_error.rs:82`, `api_bridge.rs:81` and `protocol/error.rs:154` retain
the prescribed invalid_prompt error text. Native Agent status maps that terminal
error to Errored. The v1 wait handler emits inProgress then the actual final
state; wait and close classify an errored target as a failed tool call.

For the other child, `tasks/regular.rs:51` awaits TurnStarted before sampling;
`session/mod.rs:2701` synchronously records Running. Receipt of its real provider
request is therefore the observable barrier. `agent/control/legacy.rs:50`
captures AgentInfo **before shutdown**; the close handler later uses that saved
status. Its completed tool item can correctly contain running after the child
has closed. This does not mean the child remains loaded or executing.

The new Responses-only peer supplies five prescribed model tool calls and a
fixed final message. Stock Codex supplies every app-server frame, native
thread/turn ID and stored item. Child A gets one ordinary terminal SSE
invalid_prompt with exact message `Owned V359 child failure.` Child B's actual
request sets an Event and stays held without headers or an answer. The parent
cannot receive its close-B model call until that Event is observed.

There are exactly **eight** actual model requests: six parent requests and one
for each child. Parent continuations independently check every tool result in
order: spawn A, wait A, close A, spawn B, close B, final answer. Both genuine
child IDs and their own native turn IDs are distinct. No retry or arbitrary
sleep is used. The threaded peer signals its closing Event before server_close,
so owned teardown releases its held handler.

## Exact actual evidence

The [owning native test](../../apps/samgita_codex_driver/test/native_collaboration_failure_running_test.exs)
passes **1/0**, 2.7s, with fixed YOLO and normal Session validation. It asserts
complete independently prescribed started/completed items for wait A, close A
and close B: native parent/child/turn association, fixed call identity, canonical
tool/status, exact agentsStates/message, explicit null fields, empty started
states and bounded native timestamps. Actual notification envelopes pass the
full root schema and lossless codec checks.

| Physical owner | Exact schema pointer | Qualified behavior |
| --- | --- | --- |
| 2083 | `ServerNotification.json#/definitions/CollabAgentStatus/enum/1` | Running/null in completed close B, after sampled-request barrier and before shutdown snapshot |
| 2086 | `ServerNotification.json#/definitions/CollabAgentStatus/enum/4` | Errored with exact prescribed message in completed wait A and close A |
| 2098 | `ServerNotification.json#/definitions/CollabAgentToolCallStatus/enum/0` | Exact inProgress started maps for all three selected calls |
| 5292 | `v2/ThreadItemsReadResponse.json#/definitions/CollabAgentStatus/enum/1` | Independent warm and first-cold selective running/null history for close B |
| 5295 | `v2/ThreadItemsReadResponse.json#/definitions/CollabAgentStatus/enum/4` | Independent warm and first-cold selective errored history for wait/close A |

Selective reads assert independently built expected maps, with only native
identities/timestamps carried from their observed associations. Request itemIds
are intentionally out of execution order; the actual native reader orders by
CreatedAtOrdinal. A checked distinct owned process repeats the selective reads
while remaining unloaded, with no new inference or execution. Both closed
children are absent from loaded state. The held child's terminal turn shape and
spawn's scheduling-sensitive states are not used as oracles.

Capture is bounded to 32 frames, 4KiB each and 128KiB total; event collection to
256 events, 1MiB and 32 method types, with ordered unique sequences, current
generation and explicit gap/deadline failures. Original fixture/config/catalog
bytes and empty workspace remain checked. Existing completion barriers reap
both owned native instances and the provider owner/Ports. No production runtime,
existing test, provider helper, assertion or deadline is changed.

## Final permitted checks

All eleven final commands pass at seeds `501432` and `987654`:

| Check | Final result |
| --- | --- |
| Ten reviewed protocol modules | **47/0 twice**, no exclusions |
| Twenty-one reviewed ordinary driver modules | **123/0 twice**, 172.821/173.966s |
| Driver composition per seed | 94 actual-binary cases and 29 scripted fault cases |
| Outside-umbrella native consumer | **1/0** |
| Scoped format/package compile | Pass with warnings as errors |
| Root strict Credo | Pass on **523** sources |
| Python AST/inventory | Nine files parse; inventory passes |
| Executable source guard | **344** stable files; all **342** prior files unchanged |

Exact commands/logs: `/tmp/samgita-v359-functional-checks/final/`; runner and
binding: `/tmp/samgita-v359-{run,source,bind}.py`. Independent source review
SHA256: `f47d7f44f992bade0ad7a12255d2994f05076575342b0dea05f6e6c0c0fdeb75`.

| Artifact | SHA256 |
| --- | --- |
| Source evidence | `20384bf1cf66c873df5d98eff2370c098dad882f5a9ac319bb8e696b23ad20e8` |
| Final results.json | `e7f22a8a81ad8aeb824fd39a227d6372483ee5050af03636b9cf1ed9dd732760` |
| Final source.json | `acdb3425695f5b908337eed91c3319c9b0094a115f08fc8e6f35fd5cc6b22089` |

## Rollback and remaining gates

Rollback removes only this additional fixture/test and its evidence mappings.
No application state, schema, migration or production history changes. Never
redispatch work as part of rollback.

Only the five exact owners gain scoped implemented evidence. Contracts become
**5,038 implemented /1,517 missing /66 blocked**; requirements remain **462
implemented /12 missing /11 blocked**, **zero verified**. Persisted inProgress
owner5307 stays missing: completed history replaces the started item. No other
agent/tool status, v2 alias, ThreadRead/Resume/Fork export, broad family, transport,
OS, provider or platform profile inherits a promotion. Native parent completion
does not establish Samgita Task acceptance.

Strict completeness still exits **1**. Prohibited security/credential/
authentication/authorization/permission/approval tests, audits, mixed broad suites
and hosted workflows remain unrun/incomplete. A11, producerless legacy and
external/OS/platform/final aggregate gates stay open. Full compatibility remains
incomplete. No tag, publication, deployment or live-credential change occurs.
