# Native stock sleep and accepted steer

The real pinned Codex executes stock `clock.sleep` with requested duration
**60,000ms**. An explicitly accepted `turn/steer` wakes it within the same turn.
The shared **10-second** deadline begins before the steer request; no shorter
sleep, clock replacement, synthetic native frame, client tool response,
turn/interrupt or restart manufactures completion. Target source is
`83086188ae0614bd882818ff1aa23f3194962012`; Linux musl binary SHA256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

The owned Responses peer supplies only one stock sleep function call and one
fixed assistant message. The native tool runs against the system clock, with
shell execution, hooks, plugins and unrelated features disabled. A private
loopback-only namespace has no default routes or inherited credentials.

The test asserts the real started sleep item before steering; exact thread/turn
and both client message IDs; exactly one started/completed sleep pair; original
duration retained; positive native start/completion times within the shared
bound; and complete four-item ordered history. The second actual model request
must contain the native call and its exact result text:
`Wall time: <four decimal digits> seconds\nSleep interrupted by new input.`
The bounded decimal duration is parsed and independently checked. Both raw
Responses request/reply bodies are hashed and checked against prescribed SSE,
not used as manufactured app-server protocol responses.

Selective `thread/items/read` must return the complete prescribed sleep entry
with both exact lifecycle timestamps, handle duplicate/absent selectors, and
return empty for an absent-only query. Owned cold restart must preserve that
entry and the entire history without loading or executing the thread. Exactly
two model requests, no realtime traffic, empty physical workspace, no unresolved
interactions/operations/gaps and complete owned PID reaping remain asserted.

## Initial failed oracle and source correction

`/tmp/samgita-native-sleep-queue-v1-20261024/` passes compile/format/strict Credo
but reports **3 tests / one failure**, seed501432. Both queue cases pass. The
new sleep test incorrectly reads `startedAtMs` from item/completed. The actual
notification has `completedAtMs`, item, threadId and turnId; its start time
belongs to the separate started notification. Pinned
`app-server-protocol/src/protocol/v2/item.rs:1343,1421` defines these distinct
maps, and upstream `app-server/tests/suite/v2/sleep.rs:289–311` compares them
independently. `v2/thread.rs:1818` defines both times on the durable entry.

The repair compares the entire completed-notification map to those four exact
fields. It retains the real positive start time from item/started and requires
that same value in warm/cold selective history. No supported field assertion,
timing bound, sleep duration, steering or cleanup check is relaxed. The failed
native root remains `/tmp/samgita-ss-QBTM091z09o7`.

## Executed evidence and limits

`devenv shell --no-tui -- python3 -B
/tmp/samgita-native-sleep-queue-plugin-v2-20261024.py` passes compile, format,
root strict Credo and **14/0** at both seeds501432 and987654, including this
single sleep case. The complete executable-source guard matches.
`results.json` SHA256:
`afbde503a2f8efdb71d2a668ad3c34ecfeeea21068f01c89cb026bd85c5bc4fc`.
Successful sleep roots: `/tmp/samgita-ss-hgsOF8Dy0Fxs` and
`/tmp/samgita-ss-14EKoxMnaTNj`. A required explicit hosted step runs this profile.

Exactly five physical owners under
`schema:v2/ThreadItemsReadResponse.json#/definitions/ThreadItem/oneOf/14` gain
scoped implemented evidence: the complete selected sleep alternative,
properties durationMs/id/type and the sleep type literal. Every subtree hash is
independently recalculated. Other duration/error/wake/clock modes, cancellation,
mid-turn crash, transports/OS, real model/backend success and full acceptance
remain unqualified. This test grants no Samgita Task acceptance. A11 and missing
legacy emission remain blocked; final-source aggregate/hosted checks remain
required. No fully verified promotion, release, publication or deployment.
