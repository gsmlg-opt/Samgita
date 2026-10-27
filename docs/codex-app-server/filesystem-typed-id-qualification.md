# Typed IDs on the existing native filesystem journey

V450 strengthens `native_fs_path_values_test.exs` at `main`
`10ad8e0fa4c7ac2c359acec0e94fa02d5a805f26`. Its same 25 native requests create,
write, read, copy, watch, unwatch and remove disposable Unicode paths, retaining
actual file bytes, directory contents/existence, watch evidence and birthtime
comparison. No new request, command, process, lifecycle or longer wait is added.

Selected existing request positions prescribe integer/string aliases `0`/`"0"`,
`7`/`"7"`, `42`/`"42"`, integer `2^53+1`, negative `-1`, signed-i64 min/max and
Unicode string `owned-fs-λ🙂`. Each position checks its expected method, so
request reordering cannot silently transfer an ID profile. Remaining positions
use unique deterministic strings. All 25 IDs must be distinct under typed
identity. Capture retains successful-send original bytes plus the whole map;
both must equal the independently constructed request. Returned responses retain
strict ID equality and exactly id/result keys. Existing caller-specific result
and host-effect assertions remain the independent success oracles; an observed
metadata result is not presented as a prescribed complete result.

The capture is outgoing only. This supplies original outbound envelope and
returned-map correlation evidence, without claiming original inbound response
bytes, natural response reordering or every ID representation on every method.
The original 32-send/4096-byte capture bounds, 256-event/five-second watch bound,
60-second module deadline, zero-model/config/empty-workspace controls and saved
connection/owned native PID cleanup remain unchanged. Added byte retention is
bounded by 128 KiB. No mutation retry or ambiguous-disconnect recovery occurs.

## Exact owners and provenance

Target Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
binary SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Five whole RPC/declaration/dispatch/outgoing/FS-processor source files match the
official archive. RequestId is string or signed i64; connection-scoped dispatch
and outgoing response preserve its type. The actual processor performs local
filesystem effects and watch registration rather than echoing fixture results.

Only these `schema:ClientRequest.json#` fields gain scoped evidence:

| Index | Pointer | Owning method |
| --- | --- | --- |
| 1534 | `/oneOf/86/properties/id` | fs/readFile |
| 1539 | `/oneOf/87/properties/id` | fs/writeFile |
| 1544 | `/oneOf/88/properties/id` | fs/createDirectory |
| 1564 | `/oneOf/91/properties/id` | fs/remove |
| 1569 | `/oneOf/92/properties/id` | fs/copy |
| 1574 | `/oneOf/93/properties/id` | fs/watch |
| 1579 | `/oneOf/94/properties/id` | fs/unwatch |

Each exact node SHA256 is
`f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7`.
Binding recomputes each physical node and checks its parent method in the full
canonical export, SHA256
`92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352`.
Equal hashes do not transfer evidence to siblings; branch 85 is app/installed
and excluded. Metadata/directory IDs, wrappers, other methods and the shared
RequestId alternatives receive no new credit.

## Permitted validation and limits

All nine commands in `/tmp/samgita-v450-functional-checks/initial/results.json`
pass: focused **1/0**, reviewed 36-file ordinary block **58/0** at seeds `501432`
and `987654`, dependency Python syntax, scoped format, warning-free driver compile,
root strict Credo, inventory consistency and outside consumer **1/0** (seed
`910295`). The consumer drives the actual pin outside the umbrella, without
Samgita Repo/Phoenix/platform configuration. Results SHA256
`26a694b6911a9a99b8a484082bc5e0974381c932987beff823794856c3ab4ef1`.
All 417 sources stay exact during checks; 416 prior sources remain unchanged
and only this existing test changes. Guard SHA256
`991f47da96f9241fd847dfb2d267d8cd1d6b0d89cba0c7432c1d08bd3f482db6`.

Final test SHA256
`77cd85342a15d7b76e1ad20fbdf1ddc27f76215db2e44cdf1e71e67cb0992efd`;
binder `/tmp/samgita-v450-bind.py`; source/node binding SHA256
`5b0b045ab0a318c1407a8fe1bf905e047d8b4c8a2e6912c8eb0cc046373fdfb5`;
evidence SHA256
`7475833e995f5357e4071e7fc8cc0f55798170fb14e49d2c95b20b2037ff2d17`.
The older V216 pass is historical; current qualification binds these final bytes
and current helpers instead of assuming old evidence survives helper changes.

Contracts: **5,270 implemented / 1,274 missing / 77 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
No raw inbound wrapper, all per-method ID variants, concurrent mutation,
reconnect/replay, active cancellation, other OS/transports or full compatibility
claim follows. Fixed YOLO is setup only. Security/permission tests and audits,
broad suites and hosted workflows remain unrun; A11, legacy/external/platform
and release gates remain incomplete. No publication or deployment. Rollback
reverts this test strengthening and seven evidence bindings, preserving runtime
and records. Continue the source-proven resource limit and existing fork evidence.
