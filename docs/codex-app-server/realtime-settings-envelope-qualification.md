# Existing native realtime and settings envelope evidence

V458 corrects nine omitted physical evidence bindings at `main`
`e6b5227abe647d6e091c9b2369c1a173411706b3`. No code, test, fixture, runtime,
deadline or capture bound changes. Both unchanged owning modules were enabled
in the latest V456 reviewed **58/0** ordinary runs at seeds `501432`/`987654`.
All 850 source hashes and 13 successful logs remain exact; no new test runs.

Only these `schema:ClientRequest.json#` string-ID fields gain evidence:

| Contract | Pointer | Independent native effect |
| --- | --- | --- |
| 766 | `/oneOf/102/properties/id` | Explicit realtime start creates a native UUIDv7 start fact with prescribed caller session/version |
| 786 | `/oneOf/106/properties/id` | Explicit stop creates a distinct ended fact, requested closure and durable ordered start/closed timeline |
| 1239 | `/oneOf/32/properties/id` | Four alternating summary updates cause prescribed native settings notices without another provider request |

Each request uses an independently generated nonempty string ID before dispatch.
Successful-send original bytes/full map equal the expected request; original
native response capture equals the complete correlated response. Realtime pairs
also require sent-before-received order and exactly id/result response keys.
Settings uses only the ordinary runtime-roots case; no historical mixed settings
or permission profile supplies evidence. Its notification oracle checks model,
provider and summary, without claiming the complete settings map or original
notification ingress.

Six more exact `schema:ServerNotification.json#` leaves gain separate evidence:

| Contracts | Parent | Selected physical leaves | Native literal |
| --- | --- | --- | --- |
| 3084/3085 | `/oneOf/71` | `properties/method`, `properties/method/enum/0` | thread/realtime/started |
| 3092/3093 | `/oneOf/73` | same two separately bound leaves | thread/realtime/item/started |
| 3100/3101 | `/oneOf/75` | same two separately bound leaves | thread/realtime/item/completed |

The realtime case independently prescribes session identity, version and the
complete expected start/closed item shapes. Real native start/stop creates
distinct UUIDv7 items; complete original selected frames require exact semantic
payloads, measured timestamp brackets, canonical schema, generation/order and
unchanged decode through JSON and Wire. A native persistence barrier and two
exact timeline reads establish durable `[start, closed]` facts. The owned local
WebSocket backend provides handshake/session ACK inputs; it supplies no
app-server frames, native history items or real-provider acceptance evidence.
No inference, media or live external service is qualified here.

Fourteen complete RPC/declaration/dispatch/turn/settings/realtime/history/store/
serialization files match the official archive at Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`. Native core constructs/persists the
history facts; `bespoke_event_handling.rs:448–456,467–499` constructs the exact
three public notifications. Settings applies `Op::ThreadSettings` and emits the
changed snapshot. The common response path retains the connection-scoped ID.
Executable SHA256 remains
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
All nine nodes and six separate parent hashes/method identities match the full
canonical experimental export and generated copy. The experimental
ServerNotification export `c626079776d401d358a8791b74cfe6c978d18aabbb78477ce7bd710a79779bc1`
is distinct from its stable export. No stable-array index is substituted.

Owning hashes:

| File | SHA256 |
| --- | --- |
| `native_realtime_start_stop_test.exs` | `d7e96511cd740613a65ccb8c4685e77aaab4c2b29079332b1c12319787151cf4` |
| `native_turn_runtime_roots_test.exs` | `55f8af2caa59e02d284e868d4a85fcc6be5df55e4db7e1e9f1d3e7f11478e6ed` |

Report `/tmp/samgita-v458-candidate.md`, SHA256
`44cc2a297ec2d8f2d95b50416228f9594c4f66a1ca404909225c21fb06823edc`;
binder `/tmp/samgita-v458-bind.py`; source/node binding SHA256
`cefa33d3e6f200d729cb20bbb4c3bba2ed04057c7f4fd27d6afeb06c64633d05`;
evidence SHA256
`8cdce19b6f3f279629e23b4a5a85c36d443a484a27817a92253848a13418efc3`.
Bindings are under `/tmp/samgita-v458-binding/`; actual V456 commands/logs and
source guard are recorded in [the command profile](command-request-id-qualification.md).
Inventory consistency and diff whitespace are checked after binding. Original
finite captures, RPC/lifecycle deadlines and checked native/peer owner/Port/PID
cleanup remain. No new runtime acceptance is claimed by this evidence correction.

Contracts: **5,286 implemented / 1,248 missing / 87 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
No parent/params reference, alias, timestamp, RequestId alternative, integer/
reused/concurrent/reconnect/cancellation, whole method/settings map, other
platform/transport or real-backend credit transfers. Fixed YOLO is setup only.
Security/permission tests/audits, broad/hosted workflows, A11, unavailable legacy
producers, external/platform and release gates remain incomplete. No publication
or deployment. Rollback reverts these nine bindings and documentation only.
Continue the enabled ordinary hook-plugin metadata gap; the separate V460
review of creation/MCP-startup/reasoning envelope leaves found them already
implemented and nominates no additional credit or redundant tests.
