# Original native thread/started source notifications

This unit follows `4243727c4a2d137250813aa1dbe03459a74bab72` on existing
`main`. It extends the [separately pinned official standalone profile](standalone-source-selector-qualification.md)
with direct incoming notification evidence. Target: `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, standalone executable SHA256
`528c11baca43b3be05112c0be1fb1c4a3d5c53f1b6d628f5bf42ebd7803e7a9e`.
The combined pin and all production inputs remain unchanged. Fixed YOLO is
launch setup only. No security, authentication, authorization, approval, sandbox
or permission test, audit, broad mixed suite or hosted workflow is run.

## Direct notification behavior

The original four appServer/unknown/custom/vscode producers now each require
exactly one incoming native thread/started in their original bounded capture.
These assertions run after the owned producer closes, without another launch,
RPC, model call or notification-arrival sleep. All original discovery, cold
readback, canonical persistence, correlation, bounds and cleanup assertions stay
intact. The first case adds only the new notification assertion call; all prior
produce/history/schema/matrix/readiness/start/inventory/cleanup helper bodies
remain byte-identical.

A separate second case starts two genuine producers with standalone selectors
`cli` and `exec`. Each creates a real app-server thread, completes one ordinary
assistant turn against the local model fixture, reaches the existing native
persistence barriers and closes before notification inspection. These selectors
exercise native source metadata; they do not claim terminal CLI or native exec
JSONL protocol compatibility. No canonical metadata, SQLite row or app-server
frame is injected. Original request, response and notification bytes are retained.

Each notification is associated with its same-session sole thread/start request
and its sole original-ID-correlated response. The notification itself has no
request ID. Its source, thread/session ID, path, cwd, provider, paginated history
mode, parent/fork metadata and attribution match the captured creation response
and independently known persisted producer identity. Initial preview/turns remain
empty, distinct from the later prompt/history. Params has exactly the thread key;
the complete incoming envelope has method, params and native emittedAtMs. The
timestamp must be a positive integer between the creation snapshot's epoch-second
lower bound and the host time after owned shutdown. Original full data remains
captured; unrelated permission/configuration fields are not validation oracles.

The [native creation path](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L1635)
clones the creation Thread for response and notification. The
[notification builder](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_summary.rs#L220)
clears only turns. The [outgoing envelope](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/outgoing_message.rs#L904)
adds emittedAtMs. No response-before-notification receipt order is required.

The added case requires exactly two model calls, two rollouts, two distinct
native process IDs and two original notifications. Its method inventory is
initialize/initialized/diagnostics/thread-start/turn-start/thread-read/items-list
twice each, plus 4..402 turns-list pages/readiness probes: 18..416 outgoing
frames, every request with one unique correlated reply. No other method is
allowed. Config/catalog/provider/helper/history bytes and the empty workspace
remain unchanged through provider shutdown. The original case keeps four model
calls, six processes and 24 discovery requests. Both cases together inspect six
original creation notifications. Only the original four-source case claims cold
reader coverage; the added CLI/Exec case claims notification and canonical
persistence evidence.

Per-process capture limits stay 1,024 frames, 262,144 bytes/frame and 8,388,608
total bytes. Existing 5s request/persistence, 20s turn and 200-probe bounds stay
unchanged. Existing native/helper ACK, completion, Port closure and reaping are
required. No shared fixture or production cleanup behavior changes.

## Exact physical owners and focused results

Only six physical ServerNotification owners become scoped **implemented**:

| Owner | Pointer under ServerNotification.json# | Native value |
| --- | --- | --- |
| 2386 | `/definitions/SessionSource/oneOf/0/enum/0` | cli |
| 2388 | `/definitions/SessionSource/oneOf/0/enum/2` | exec |
| 2389 | `/definitions/SessionSource/oneOf/0/enum/3` | appServer |
| 2390 | `/definitions/SessionSource/oneOf/0/enum/4` | unknown |
| 2391 | `/definitions/SessionSource/oneOf/1` | custom object |
| 2392 | `/definitions/SessionSource/oneOf/1/properties/custom` | normalized atlas string |

The test pins root SHA256
`c626079776d401d358a8791b74cfe6c978d18aabbb78477ce7bd710a79779bc1`,
resolves the actual thread/started → ThreadStartedNotification → Thread.source
→ SessionSource graph and binds every selected node's original bytes/hash and
incoming value. Search replies, aliases, equal scalar hashes and creation
responses alone do not supply notification credit. No parent, sibling, complete
Thread/method or globally verified state is promoted.

The source-only candidate report is
`/tmp/samgita-thread-started-source-20261029-report.md`, SHA256
`13e24eecafd58c7db0a2743b2462fe1f8f7296ade15648605d90c46c4b5e98de`.
It archive-matches the five complete causal creation/source files. Its draft
envelope expectation was incorrect: the first focused attempt passed format
and compile, then **2 tests failed** because the assertion omitted native
emittedAtMs. The runner stopped before the second seed and strict Credo.
Failure evidence `/tmp/samgita-thread-started-focused-20261029` remains:
results SHA256 `3029896d534d7ae2c388ed4fb39d2d5c52d654f82edfb9bb1e6787a0694e5d62`,
source SHA256 `5dddf627999101e63d307ed5617118e9cccb613694b91a4060750c2d6f6009f6`.

The correction requires the actual three-key envelope and constrains its
timestamp; it removes no original assertion or deadline. Complete outgoing
source SHA256 `784e9f538eea4def26e33532206541bcecce0f94bea2c8fd2b7cb30463602617`
matches the official archive. The repaired focused run passes format, compile,
**2/0 at seeds 501432 and 987654**, and strict Credo. Command times are 10.989s
and 8.699s; all 1,762 guarded sources remain identical. Evidence directory:
`/tmp/samgita-thread-started-focused-repaired-20261029`;
results SHA256 `58537efea83e614957eb812d2befd4106794afca9fa7168a7c1f180be437f163`,
source SHA256 `4fdb9d48879f2d0e693025463c70c4dc0c75ae58b57c51b7bb8d3e4f7972ed7e`.
These focused results precede manifest/runner integration.

Requirements remain 462 implemented /12 missing /11 blocked. Contracts become
**5,748 implemented /737 missing /136 blocked**, with zero globally verified.
Two additional [command/shutdown prerequisites](ordinary-command-shutdown-prerequisites.md)
gain source limitations only; both stay missing. Existing ClientRequest/list
owners676/682/5700 are already implemented and receive no alias-based promotion.
Their exact mapping report is
`/tmp/samgita-standalone-source-owner-map-20261029-report.md`, SHA256
`f20b4ad16859be788cecbf1653153bc4d7f7c9a15bc4cd83921de0a436fa24b5`.

## Final combined-source functional qualification

All **17 reviewed functional steps pass** against **1,762 identical guarded
source hashes**. Every main 165-case argv/assertion and 320s bound is retained;
the separate extension block grows from 14 to 15 cases with its existing 120s
bound. No prohibited or broad check substitutes for the remaining gates.

| Check | Actual result |
| --- | --- |
| Neutral overflow/replay | Three selected cases, zero failures, 13 excluded at each of 455834, 501432 and 987654 |
| Main native block | 165/0 at both seeds; 299.971s and 286.712s |
| Separate native extension block | 15/0 at both seeds; 28.409s and 31.618s |
| Owned cleanup phases | 4/0 with existing ACK/exit/deadline requirements |
| Outside-umbrella consumer | 1/0 against actual combined Codex, without Repo/Phoenix |
| Other checks | Driver format/compile, inventory, umbrella compile/format, strict Credo, Dialyzer and assets build pass |

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-standalone-notification-combined-20261029
```

Results JSON SHA256:
`eaeb6030ce06a6a90aca1b03e4234ca0adcae3b4fafe714fcc8cef388d55972a`;
source JSON SHA256:
`e33cc2bba10db0b6ea641a7246850a906b6fb9c37ab48c64416d6378fd5114b3`.
Reviewed source fingerprint:
`9b89fedd91e6b6cb3fa2ac828add039debe6e7f479df53e55185c82ef395c2d4`.
Exact commands, bounds, statuses, count checks and original log hashes are in
that evidence directory. Earlier failed source/logs remain separate. Full
compatibility and release acceptance remain incomplete.

## Remaining acceptance and rollback

Production code/configuration, dependency locks, migrations, database safeguards,
process cleanup and default platform executable are unchanged. The preceding
local production assembly remains evidence for those inputs; this unit does
not build, start, publish or deploy another release. Rollback removes the new
notification assertion/helpers, second test and their six manifest bindings,
restoring the prior reviewed runner count/fingerprint. Preserve original source
selection tests, immutable pins, records and all existing cleanup requirements.

Continue other permitted genuine behavior work when its producer and causal
ordering are established. A11's pre-emission telemetry boundary, source-proven
legacy non-emitters, unresolved source/ordering prerequisites and the historical
intermittent cleanup cause, unavailable backend/OS success, prohibited/broad/
hosted checks, full compatibility and release remain incomplete. No live service,
credential, host configuration, historical data or sibling repository changes.
