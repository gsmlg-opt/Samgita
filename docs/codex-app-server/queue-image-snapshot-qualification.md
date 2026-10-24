# Native queued PNG snapshots and cold dispatch

Two cases pass at seeds `501432` and `987654` against stock `rust-v0.163.0`,
source `83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The driver uses a real UDS connection in a private loopback-only namespace.
Owned native restart/cleanup guards are retained. The peer supplies two fixed
no-tool assistant messages and records actual model HTTP bytes, digest, parsed
body and native queue metadata. It never creates app-server envelopes.

The legacy case materializes a thread, closes/restarts its native process and
adds text plus local PNG A to its unloaded queue. The complete returned saved
input is normalized text plus the exact inline PNG/detail. Overwriting the
source with distinct PNG B does not change A in the queue. After deleting the
source and restarting again, the unloaded queue remains exactly A with the same
queue/client identities and one model call total. Explicit thread/resume then
wakes and dispatches that stored queue; the test does not call queue/start.

The paginated case replaces accepted A with B using queue/update, preserving
queue/client identity. After removing B's source file, a replacement referencing
a missing file returns the exact native Linux invalid-request error. The whole
last accepted B submission remains intact through restart and dispatch. Neither
rejection nor cold reads start a turn. In both cases, exactly one queued turn
reaches the model, completes and empties the queue. The physical source workspace
is empty. No tool, credential, policy rule or realtime traffic exists.

Independent PNG oracles check exact bytes/SHA, dimensions, chunk CRCs and all RGB
pixels. The model advertises original-image-detail support; the actual request
must contain one exact original-detail image. HTTP metadata, native turn ID,
user client ID and live start/completion correlate. Both complete durable turns
are checked with the original turn unchanged. A second postcompletion restart
must retain full history and the empty queue without another model request.
Every owned native/controller/namespace process must be confirmed reaped.

## Independently expected selected assistant after restart

A subsequent additive assertion specifies the model-supplied assistant ID
`owned-queue-image-2` and fixed text independently, then compares complete native
started/completed maps with present null delivery/memoryCitation/phase/questions.
Both actual notification timestamps must be positive integers and completion
must follow start. The accepted user item completes before this assistant starts.
In paginated mode the selected assistant entry, including both exact times,
must match warm and after another owned cold restart. Legacy selective reads
retain their unsupported error and sequential stored IDs; no legacy timestamp
is invented. Original PNG, full-history, queue, no-reexecution and cleanup
assertions remain intact.

The new complete owning profile passes **2/0** within **14/0** at both fixed
seeds in `/tmp/samgita-native-sleep-queue-plugin-v2-20261024/`, with compile,
format, root strict Credo and matching executable-source guard. `results.json`
SHA256 is
`afbde503a2f8efdb71d2a668ad3c34ecfeeea21068f01c89cb026bd85c5bc4fc`.
The earlier three-case runner fails only the separate sleep notification oracle;
both queue cases pass there too. This run supersedes the profile hash below;
the original hashes/counts remain historical evidence, not final-source proof.

Exactly eight still-missing owners under
`schema:v2/ThreadItemsReadResponse.json#/definitions/ThreadItem/oneOf/2` gain
scoped implemented evidence: the complete selected AgentMessage alternative,
properties delivery/memoryCitation/phase and their null branches, plus questions
present null. Each physical subtree hash was independently recomputed. This
selective-response evidence is distinct from the seven previously indexed
ServerNotification owners. Their test anchors move to383–416; their states
are unchanged. Non-null values, omissions/defaults, other item alternatives,
external providers and full verification remain unqualified. Required hosted
and final-source aggregate checks remain separate gates.

## Native legacy behavior and retained initial failures

The first two runners stopped at strict Credo before native execution. Splitting
the large lifecycle assertions into named helpers preserved their sequence,
oracles and deadlines. The third runner passed the paginated case but failed
legacy live-ID versus stored-ID equality, **2/1**, 6.6s. All three directories
remain under `/tmp/samgita-native-queue-image{,-v2,-v3}-20261024/`.

Pinned
[`thread_history.rs:1537`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/thread_history.rs#L1537)
allocates sequential IDs when reconstructing legacy messages. The materializing
turn consumes item-1/2; the queued user/assistant therefore become item-3/4.
Only those two prescribed IDs differ from the exact live maps; content, image
bytes and client identity remain equal. Paginated history retains the live IDs
and exact timestamps. Native
[`read.rs:228`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/thread_history/read.rs#L228)
rejects selected-item reads in legacy mode. Warm and cold legacy calls must
return the exact `-32601 thread/items/read is not supported yet` error;
paginated calls must return the exact positive item/timestamp entry. No legacy
timestamp/result is fabricated and no paginated success assertion is removed.

The immutable snapshot contract is explicit in
[`local_media.rs:20`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/local_media.rs#L20)
and the
[`queue service`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/queue/src/service.rs#L267):
prepare inline data before persisting enqueue/update, preserve client identity,
then dispatch saved payloads. Its
[`attachment tests`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/queue/tests/queue_service.rs#L828)
are source support, separate from this actual consumer evidence.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-queue-image-v4-20261024.py
```

Final Python AST, driver warning-free compile, scoped format and root strict
Credo (420 files) pass. Both seeds pass **2/0**, no exclusions, 7.0s each (runner
7.483/7.530s); executable-source guard matches. A required explicit hosted
profile step is added. Final combined-source local/hosted checks remain required.

| File | SHA256 |
| --- | --- |
| `native_queue_image_snapshot_profile.exs` | ce3c5a9ef33e808dbb6fe5688d02eacae025e098bf6fe1c2e0ecd9748b471cf4 |
| `isolated_queue_image_fixture.py` | fa43f97351f2fad186e35e753ba055867183f8393b64eedbd9860fbb53c4a857 |

Exactly thirteen direct physical owners gain scoped implemented evidence:
queue/add request thread/input/client fields; its response queuedSubmission and
three saved-submission fields; queue/update request thread/queued-ID/input and
its response queuedSubmission; queue/list response data and nextCursor. Exact
IDs/subtree hashes are in the manifest. Assertions99–179,219–240,452–491 cover
these owners;242–406 adds live/durable/model evidence. No nested schema alias,
whole union, queue/start, audio, concurrent-writer/crash atomicity, capacity,
real image interpretation or external provider success is inferred.

Regenerated totals: **485 requirements: 0 verified / 462 implemented / 12 missing /
11 blocked; 6,621 contracts: 0 verified / 3,047 implemented / 3,574 missing**.
A11, unreachable legacy emitters, other OS/backend profiles and complete
compatibility remain incomplete. No publication, production migration or deployment.
