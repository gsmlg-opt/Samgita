# Native environment pending and cached timeout observation

V444 adds one ordinary-only actual-native case at `main`
`d870651bb84f29dce1967dc6b67a53c4819c56a3`. Pinned Codex registers one named
environment, eagerly attempts its loopback connection, reports pending, then
reports the actual cached timeout through repeated status reads. A supervised
passive TCP peer holds request framing and sends zero bytes. It supplies only
transport fault facts, never successful executor responses or native status.
No thread, turn, command, model work or recovery method is requested.

After a positive accepted/held peer milestone, two complete native results must
equal `{status:"pending"}`, with error omitted. The peer must then observe
actual native EOF. A read-only collector accepts only pending until the exact
disconnected result is published, bounded by 16 queries and 5 seconds. Its
independent expected error uses the URL supplied before registration:

```text
exec-server connection attempt failed: timed out connecting to exec-server websocket `U` after 5s
```

Three further complete results must retain that exact failure. One registration
is sent, with deliberately prescribed `connectTimeoutMs:5000`; it is never
retried. Native status is an observation of startup/cached failure, rather than
a request to reconnect. The peer's final live-listener barriers require exactly
accepted, held and EOF, with one observed connection. This finite observation
is corroborated by the upstream FailFast call path; it is not an unbounded
promise about future traffic. Loaded threads and model-provider journal stay
empty; config/model-catalog/script bytes and workspace remain unchanged.

Complete original inbound/outbound frames are retained before Session decoding.
Each unique RPC has one exact correlated result envelope, original JSON/Wire
equality and native request/result schema validation. Initialized generation
and instance remain stable. Ready/no-pending/no-interaction/no-uncertainty and
no-gap barriers hold; every drained item is a same-generation notification,
and the drained sequence equals all original observed notifications. The exact
method inventory allows initialization/diagnostics, one add, the prescribed
bounded status reads and one loaded-list read only.

Bounds remain explicit: 128 capture records, 64 KiB inbound/8 KiB outbound per
frame, 2 MiB total and a 60-second module deadline. The no-send peer has a
16 KiB framing bound, eight journal entries, 15-second total lifetime and
20 ms passive servicing. Accepted/held and control milestones use 1-second
bounds; positive EOF is bounded relative to acceptance at 6.5 seconds. None
of these waits establishes success without the required observed fact. No
existing deadline, assertion or shared fixture changes.

The peer owns every socket, retains a live listener through final observation,
and closes its Ports on monitored shutdown. Native and inert provider retain
the unchanged confirmed owner/completion/Port/PID cleanup. Cleanup is registered
before registration can fail. Observed ingress is frozen and checked after
cleanup; existing native Owner shutdown still discards normal stdout. No
shutdown-tail capture or absence beyond the finite barriers is claimed.

## Native provenance and exact contracts

Pin: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The selected and running diagnostics-identified executables match the pin.
Six whole native files match the immutable archive: dispatch, environment
request processor, exec-server environment/client/transport and protocol types.
Registration starts eagerly; status uses FailFast without reconnect. The
transport applies the supplied timeout, the client supplies the exact wrapped
error and the serializer omits absent error. The canonical unchanged result
export also matches its generated pin.

Only these five physical owners under
`schema:v2/EnvironmentStatusResponse.json#` gain scoped implemented evidence:

| Index | Pointer | Node SHA256 |
| --- | --- | --- |
| 3914 | `/definitions/EnvironmentStatusKind/oneOf/1` | `4fc1895131a43fca21bbe4631c0323d89ac53ca9de8373b6a3a03f74bd617e6e` |
| 3915 | `/definitions/EnvironmentStatusKind/oneOf/1/enum/0` | `6006c8517af64611108324ddb24ea0332b6a2114b53e75acf4bf55ae285d66ca` |
| 3916 | `/definitions/EnvironmentStatusKind/oneOf/2` | `0bb42768e34e956d796c3f1c473fc05450f320232fc5f4fd42f6d85795996186` |
| 3917 | `/definitions/EnvironmentStatusKind/oneOf/2/enum/0` | `ba4c16dfac2cf0e80877196e81280478b8341a7f4ca35af77b5b31d4913f6d45` |
| 3922 | `/properties/status/allOf/0` | `c72c845596aeff9a1b76b7677694caed28fc946dd4a2424a36172a9ce9e50174` |

The allOf evidence covers observed pending/disconnected, not every referenced
status. Existing roots/ready/unknown, notification and other aliases receive
no duplicate credit. Source/node binding `/tmp/samgita-v444-binding/source.json`,
SHA256 `fa1de3b2c4f7ba900bc2ffcec0b45dec9cc0329f583dd1c4d0b32242b69329bc`.

## Actual permitted checks and limits

All nine commands in `/tmp/samgita-v444-functional-checks/initial/results.json`
pass on this first integrated source: focused **1/0**, reviewed 34-file ordinary
block **56/0** at both `501432` and `987654`, dependency Python syntax, scoped
format, warning-free driver compile, root strict Credo, inventory consistency
and reviewed outside-umbrella consumer **1/0** (generated seed `329464`). The
consumer uses actual pinned Codex without Samgita Repo, Phoenix or platform.
Results SHA256
`8f697d4928d95e2b015d4b26fdf8fccd269c1bf4ae3f7fdf520e31f1da48f342`.
All 416 source hashes stay exact during validation; all 415 prior paths remain
unchanged and only this test is added. Guard SHA256
`cba022c992778172812021eee52b3de9ac41ab160dfad38d999228982369a0fd`.
Test SHA256
`f93785dff1cd6b72d20e47cc6f9ea936fe50af441222eecf0742ca2029bae856`.
Binder `/tmp/samgita-v444-bind.py`; evidence JSON SHA256
`258d94a8f00910ecc71f4d9d1e537263493cdfb91e0c4664ca7dcc488b46284c`.

Contracts: **5,253 implemented / 1,296 missing / 72 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
Successful executors, reconnect/recovery, selected-thread notices, cloud/Noise,
registration persistence, replacement/concurrency, other OS/transports and
real platform/provider integration remain unqualified. No existing mixed
environment suite is run or weakened. Security/permission tests and audits,
broad suites and hosted workflows remain unrun. A11, legacy/external/platform/
full-goal and release gates remain incomplete. No publication or deployment.
Rollback reverts the new test and five evidence bindings, preserving runtime
and records. Continue ordinary typed initialization and correlation lifecycles.
