# Original native shell-command requests

V447 strengthens the existing two-command shell journey at `main`
`a6e489d28e6da1febd38e0a8bb0f58f7b69c4448`. It adds no execution scenario,
production change, retry or longer deadline. Each existing alpha/beta command
has an independently prescribed RPC ID: string `owned-v447-shell-alpha` and
integer `447002`. The successful-send capture retains original encoded bytes
and the complete decoded request. Exact JSON, direct Wire decode and canonical
ClientRequest validation agree with the independently constructed whole request.
The complete returned native response must have exactly that typed ID and `{}`.

The empty response acknowledges submission. Actual completion still requires
the existing distinct turn/item identities, ordered output deltas, completed
userShell items, zero exit status and exact append-only alpha/beta file effects.
Original requests remain unchanged through warm history, old-process shutdown,
a different native process's cold history and final shutdown. Cold reads leave
the same effects, config and zero-model-request journal. RPC IDs remain separate
from native turn/item IDs. No raw inbound ACK envelope is captured or qualified.

The original capture bounds (16 requests, 4096 bytes each), inbound delta bounds
(256 records, 4096 bytes each, 1 MiB aggregate), five-second native command bound,
20-second completion collection and 60-second module deadline remain. Existing
saved-connection cleanup, owner shutdown and native PID absence checks remain.
Two actual commands are the only shell submissions throughout the observed
finite history/close barriers; this is not an exactly-once or retry guarantee.

## Pin and physical owners

Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
binary SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Five whole protocol/dispatch/processor/event source files match the official
archive. The real processor submits RunUserShellCommand and returns the empty
typed result; subsequent item/output/turn events establish execution outcome.

Only these `schema:ClientRequest.json#` owners gain scoped evidence:

| Index | Pointer | Node SHA256 |
| --- | --- | --- |
| 1273 | `/oneOf/39` | `5a8390907a748d84dfd1d69af536cb90087833d73f42996c4a2300954113c7b2` |
| 1274 | `/oneOf/39/properties/id` | `f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7` |
| 1275 | `/oneOf/39/properties/method` | `617cb06847b1ba62d95940832dbc1e588d56ed7d4a555696ef357157bc1ebb27` |
| 1276 | `/oneOf/39/properties/method/enum/0` | `782e4ed8b9239c709001c34a23dd84221de82df99112a5ecba9616e29b808ef9` |
| 1277 | `/oneOf/39/properties/params` | `cd47fd0506f34426c6c24d1b3dcc2aec255ec2aabcbacf4fca8238e7a897361b` |

The manifest's physical pointers address the complete experimental export, even
when a method also exists in stable. An initial scratch-binder check stopped on
the stable export's different array position, before any manifest edit. Binding
the unchanged full export fixes that artifact lookup; it changes no test result
or schema. Complete ClientRequest SHA256 remains
`92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352`.
Source/node binding `/tmp/samgita-v447-binding/source.json`, SHA256
`191e569686b7c643fd12b869df017c37a7b2ef3989ff441cbfe826620b7c6d45`.
No other alias, same-hash reference, response or notification inherits credit.

## Permitted checks and limits

All nine commands in `/tmp/samgita-v447-functional-checks/initial/results.json`
pass: focused **1/0**, reviewed 35-file ordinary block **57/0** at seeds
`501432` and `987654`, Python dependency syntax, scoped format, warning-free
driver compile, root strict Credo, inventory consistency and the outside consumer
**1/0** (seed `959637`). The consumer controls the real pinned binary without
Samgita Repo, Phoenix or umbrella configuration. Results SHA256
`2aeb07adba757a1bc4c2b18b5f4684ca06d9a5137ddd8d27a55bf4cdebe85921`.

All 417 source hashes stay exact during these commands; compared with V446,
416 prior sources are unchanged and only the existing shell test changes.
Guard `/tmp/samgita-v447-functional-checks/initial/source.json`, SHA256
`356a31378a5d63902703092012854d5bf47fa9c30f89621cfdfffea4910b4c16`.
Final test SHA256
`c853f7239122a2470c0f82c59d6689c372f30b1216fb4dbf0bbf1d4baa26c1cd`;
binder `/tmp/samgita-v447-bind.py`; evidence SHA256
`d80ec6415f209f79a9307762d4035e629b83f2f0e1502a080b981ebdeb777d3a`.

Contracts: **5,263 implemented / 1,286 missing / 72 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**; zero verified in both.
This qualifies the bounded Linux/stdio successful shell journey, not timeout,
cancellation, concurrent execution, active-turn auxiliary commands, ambiguous
disconnect/retry, raw ACK wrappers, other platforms/transports or full ID aliases.
Fixed YOLO is setup only. Security/permission tests and audits, broad suites and
hosted workflows remain unrun; A11, legacy/external/platform and release gates
remain incomplete. No publication or deployment. Rollback reverts this test
strengthening and five evidence bindings; runtime and historical records remain.
Continue the pinned config metadata producer limitation and ordinary file paths.
