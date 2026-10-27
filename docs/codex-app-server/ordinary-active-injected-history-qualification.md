# Native active injection, consumption and interruption

V510 follows `7b62349` on existing `main`. The official target remains
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Two ordinary cases use unchanged ModelFixture, fixed yolo launch and confirmed
owned-process cleanup. The deterministic peer supplies model responses; stock
Codex produces every app-server frame, callback, queue effect and history row.
This is actual-native evidence with synthetic dependencies, not external-provider
acceptance. No production runtime, helper or model-fixture code changes.

## Held queue and explicit consumption

The real `item/tool/call` callback is an observable running-turn barrier. While
it remains unanswered, two sequential `thread/inject_items` requests each
receive their original correlated empty native result. After each ACK, neither
authored ID nor text exists in the actual rollout or original single provider
request. The same callback stays pending and the turn has not completed.
No sleep, quiet-window assertion or private Session state provides readiness.

Replying once to the genuine callback lets the original tool finish. The next
actual provider request contains its output followed by both complete injected
messages, exactly once in authored FIFO order. Real durable records contain
both complete prepared payloads after that tool output and before the final
assistant answer. Exactly two provider requests and one completed logical turn
are required. Full original injected rows remain identical after shutdown.

Three independently authored maps distinguish the request, prepared history and
provider input. Text preparation adds `content_item_kinds:["unknown"]` inside
the supplied internal turn metadata; the fixture-provider projection removes
the whole metadata object while preserving these explicitly prefixed IDs.
Neither native normalization nor an observed row supplies the expected payload.

Local callback write success remains a `sent_unconfirmed` interaction outcome
after tool and turn completion. Those later observations establish specific
native effects; they do not invent a separate remote response acknowledgement.

## Interrupted queue and preserved history

A second isolated case reaches the same unanswered callback and queues both
injections. It sends one real interrupt and requires its correlated success,
the original turn's interrupted terminal event, no successful assistant answer
and no additional provider request. It does not answer or retry the callback.

The original user message and function call are independently identified using
literal input, tool name, arguments and call identity. Their complete original
rows, including native IDs, metadata and timestamps, must remain once and in
order after interruption, confirmed warm shutdown, distinct cold native startup,
resume of the original UUID/path, and the next explicit turn's completion.
Queued IDs and text must remain absent at every checkpoint.

Only an explicit fresh turn causes the second provider request. It retains the
complete original user/call payload projections and new user input, with no
resurrected injected items. Native normalization may add an `aborted` output
for an unmatched prior call; this case does not require that prompt-only output
to be a durable row or to win a cancellation race. The unanswered interaction
is retired without a fabricated sent response. No platform task/history is
deleted or accepted by these temporary native-thread assertions.

## Immutable source and observation limits

The [injection branch](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/inject.rs#L74-L103)
queues active/not-finishing items, whereas the idle path prepares and records
them. `input_queue.rs:368–438` preserves FIFO on append/drain. The
[turn loop](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/turn.rs#L440-L488)
records drained input before constructing its next sampling request.
The callback's in-flight tool future holds that continuation until reply or
interruption. The runtime test brackets held absence and later visibility;
there is no invented public post-drain/pre-provider notification.

The [abort path](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tasks/mod.rs#L550-L578)
removes the active turn before cancellation and then clears pending input.
Ordinary completion cannot drain that removed turn. Its public terminal ACK
does not establish a join fence for the final local clear. The case qualifies
this explicit interruption, not every task-error/shutdown race. It does not
require a failed dynamic-tool item to beat the native100ms cancellation grace.

Source evidence `/tmp/samgita-v510-source-evidence.json`, SHA256
`4daf18bc8e4fadc82d6b6e0626002037eea6ec8529b5f436992a80a7c2009d2d`,
checks21 complete official archive-equal files and all five existing canonical
request owners1418–1422. Independent review additionally required preservation
of pre-existing user/call rows before any native execution. Those assertions
were added without changing fixtures, effects, deadlines or expected queue
semantics. No additional physical owner gains implementation credit.

## Checks and remaining gates

Exact-file real-native checks pass **2/0** at seeds501432/987654,3.4s each:

```sh
mix test test/native_active_injected_history_lifecycle_test.exs --warnings-as-errors --seed 501432
mix test test/native_active_injected_history_lifecycle_test.exs --warnings-as-errors --seed 987654
```

Logs `/tmp/samgita-v510-focus-501432.log` and
`/tmp/samgita-v510-focus-987654.log` have SHA256
`a1b83b3273c7792e9b01d78031221328b04ada2f159b45df7958b4a7f20c926b` and
`98a6f871d508197adf1eb474a9b1232f20cf5119dd5a52a2c644bfcdcde6569c`.
Combined-source qualification and final binding follow separately.

The first strict-Credo check fails solely on capture-helper complexity13,
maximum9: `/tmp/samgita-v510-strict-credo.log`, SHA256
`8a413e0872fd53a027bf0799df5f45ebfe4c7c2f72acc02d5293331bbfab0128`.
Extracting its unchanged per-connection assertions into one helper retains
every frame/count/correlation check and all bounds. Subsequent functional and
static results apply to that final structure; the original failure is retained.
Corrected focus passes **2/0** at both seeds (3.4s/3.3s); strict Credo passes
all595 source files. Corrected logs are
`/tmp/samgita-v510-corrected-focus-501432.log` (same hash as the first focus),
`/tmp/samgita-v510-corrected-focus-987654.log` (SHA256
`f300705febd75e897b7c41e7d455efe2cf25b7997cccc8ab332e32e0cd7b25ad`)
and `/tmp/samgita-v510-corrected-strict-credo.log` (SHA256
`ae3f2e7954c68eaa37cd795f700fa8643b1eb8b791dc329d2b19f9b3b71ecc58`).

Bounds remain30s per case,5s operations/waits,128 frames/events and1MiB total
capture/rollout,64KiB inbound/4KiB outbound,128 rollout rows and at most one/two
owned native connections. Cleanup proves owner completion, closed Port and
absent native PID before fixture removal. No mutation retry, replay manufacture
or test weakening occurs. Rollback removes this module and its supplemental
documentation/manifest/selector entries; it preserves V508 and process cleanup.

Counts remain **5,482 implemented / 1,009 missing / 130 blocked** contracts;
requirements **462 implemented / 12 missing / 11 blocked**, zero verified.
Arbitrary raw-item variants, other transports, complete lifecycle/deployment
profiles, source-unreachable emitters, external/OS success, A11 and full
compatibility remain incomplete. Security/credential/authentication/
authorization/permission/approval tests and audits, broad suites and hosted
workflows remain prohibited and unrun. No publication, release, production
migration, credential change or deployment is claimed.
