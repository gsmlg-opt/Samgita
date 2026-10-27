# Native initialize IDs across clean connection generations

V446 adds one ordinary-only native case at `main`
`bd107ba314205e912c9fa642376df1d4fe7fec8a`. One Session explicitly opens three
owned stdio generations, initialized with integer `0`, string `owned-init-λ🙂`
and integer `9_007_199_254_740_993`. The latter exceeds JavaScript's exact
integer range and remains within native i64. Full original requests and native
responses retain exact typed IDs. This adds initialization/concurrency/reconnect
coverage; it does not duplicate the existing serial read-ID matrix.

Each handshake uses independently prescribed client info and fixed experimental
capability setup. Its complete native result has exactly the expected four
keys, owned codexHome, Linux/unix and fixed user-agent prefix/suffix. The native
OS/terminal middle is retained without inventing a portable exact value. One
canonical initialized notification is captured after each successful handshake.
Original JSON, direct Wire decoding and the hash-pinned canonical ClientRequest
agree for all observed RPC exchanges.

Each generation queues integer `7` and string `"7"` reads while Session is
briefly suspended. A bounded unconditional try/after resumes it before cleanup.
Caller-owned Erlang asynchronous request references exercise the existing
internal request handler, rather than introducing a public asynchronous API.
Both references are consumed with bounded waits before either response assertion.
Both actual request sends must precede either consumed native response; each
caller receives its independently prescribed full result and exact ID type.
The native replies need not arrive out of order. A third read uses string `"0"`.

Reconnect follows settled requests only. The old native PID/Port must close;
Session instance identity stays stable, generation increments, phase becomes
new and no automatic request appears before explicit initialization. Existing
explicit_reconnect gap metadata remains tagged with the preceding generation;
it is never cleared to satisfy a fresh-only assertion. Reused read IDs are
scoped by actual Port, generation and strict typed ID, rather than a global ID
lookup. The exact inventory is 15 RPC/reply pairs and three initialized notices.

The capture allows three connections, 32 entries per direction, 4 KiB outbound/
64 KiB inbound frames and 1 MiB total; overflow fails. Five-second RPC/system-call
bounds, 60-second module deadline and existing owned cleanup remain. Every
successful generation requires owner completion, closed Port and absent owned
native PID. Provider journal, workspace and rollout output remain empty;
fixture config/catalog/script/source snapshots stay unchanged. No execution,
model inference or ambiguous mutation retry occurs. The capture selects original
RPC replies and initialized notices; other notifications remain subject to the
existing bounded Session drain, including rejection of unexpected requests.

## Native pin and exact owners

Target: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Native RequestId is a type-sensitive untagged string/i64 enum. Dispatch,
initialize and outgoing response preserve it and its connection identity. The
driver keeps typed map keys and resets used IDs on the new generation. Five
whole native RPC/initialize/dispatch/outgoing/user-agent source files match
the immutable archive. Canonical export and five exact nodes match the pin.

Only these physical owners under `schema:ClientRequest.json#` gain evidence:

| Index | Pointer | Node SHA256 |
| --- | --- | --- |
| 740 | `/oneOf/0` | `228229cbc1708eacb4f8098153720ca2379faff3cbf4392a24805bee07e36c2f` |
| 741 | `/oneOf/0/properties/id` | `f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7` |
| 742 | `/oneOf/0/properties/method` | `f33d77eec612d9e1ba8150fa4160b163cbc29e38ae931e43d24ed94bdac8784e` |
| 743 | `/oneOf/0/properties/method/enum/0` | `4089b3e0215cee9ee008853556027db9f3f55f2c922191850ad1beaa0f85a77a` |
| 744 | `/oneOf/0/properties/params` | `f9280c07770b00afb8c28bcfec40b18933a309cee77490154db756a083bfec2b` |

Selected initialize settings/metadata do not qualify every referenced capability,
user-agent value, RequestId alias or other method. Binding
`/tmp/samgita-v446-binding/source.json`, SHA256
`fafd5cc9b41991241f65d68bc915e86e32de67ed5489ab43c5c2f8e0f5cb4421`.

## Actual permitted checks, initial failure and limits

Initial focused native **1/0**, Python syntax, scoped format and compile passed,
then strict Credo failed: capture `record` nesting depth three exceeded two.
The remaining ordinary repeats/consumer were not run in that attempt. Extracting
the same append body into a private helper changes no limit, assertion, ID,
timeout or lifecycle behavior. Initial results SHA256
`ad926aeb52a74323dcacd19b7cd93c3d9bb1268d39d649d913d764d2aa847acc`;
initial guard SHA256
`d4714bd1ba82f9e27b1c7ca23cb910ba9f54d5ed291c8a8bd45e6f234ba8239b`.
Those failure artifacts remain intact.

All nine final commands in
`/tmp/samgita-v446-functional-checks/final-after-flat/results.json` pass:
focused **1/0**, reviewed 35-file ordinary block **57/0** at both `501432` and
`987654`, dependency Python syntax, scoped format, warning-free driver compile,
root strict Credo, inventory consistency and reviewed outside consumer **1/0**
(generated seed `803919`). The consumer runs actual pinned Codex outside the
umbrella without Samgita Repo, Phoenix or platform startup. Results SHA256
`c05891e121709e2ae2465f27940fe68d17375c57c350b4f9a961ee273f15d9fa`.
All 417 sources stay exact during final validation; 416 prior paths remain
unchanged and only this new test is added. Guard SHA256
`f5df27ae6d6930fc487c8e659da4bb674294cc1c761c0fe1b7c13803f800bed8`.
Final test SHA256
`cbf265c478510be271e31d510abe3c715a15ae4f8093d296c33d8f03853eeaf3`.
Binder `/tmp/samgita-v446-bind.py`; evidence JSON SHA256
`e33bcd8e20491fa325702fa42f634c70a3307f2763c8fa0f0041adb3152b34fa`.

Contracts: **5,258 implemented / 1,291 missing / 72 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
No actual stale-frame injection, native reply reordering, ambiguous disconnect,
active cancellation, system-resume failure, external providers/platforms or
other OS/transports are qualified. Fixed YOLO remains setup only. Security/
permission tests and audits, broad suites and hosted workflows remain unrun.
A11, legacy/external/platform/full-goal and release gates remain incomplete.
No publication or deployment. Rollback reverts this test and five bindings,
preserving runtime and records. Continue the existing shell-command envelope
journey with its actual output/effect/history oracles.
