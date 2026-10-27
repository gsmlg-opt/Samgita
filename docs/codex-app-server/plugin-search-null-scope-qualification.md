# Native local plugin search with explicit null scope

V443 extends the existing ordinary catalog matrix at `main`
`fcf12d99bbac08afb5e0a1d065a6c490d1f178ee` with explicit `"scope": null`.
The global, personal and omitted-scope controls retain all assertions. Two
independently prescribed catalogs discriminate the selected behavior: null
returns their ranked union, while either explicit scope selects its own rows.
Six actual native null queries cover both catalogs, global held/restored,
personal held/restored, and a distinct cold process after confirmed shutdown.

Expected candidate arrays come from fixture literals for names, IDs, paths,
keywords, display names and rank, independently of any native response. Each
stage compares the complete existing ordinary candidate projection and requires
exact top-level keys plus `nextCursor: null`. Complete original request/response
bytes and maps remain captured. In particular, the null query must retain its
explicit key, while the omitted control must omit that key. Warm/cold retained
results, source-tree/config/input snapshots, empty provider journal and absence
of rollouts are still checked. No thread, turn or plugin execution is requested.

The inventory grows from 24 to 30 unique correlated RPCs: 20 warm searches,
four cold searches and six retained initialization/diagnostics/loaded-list
requests. Existing per-direction capacity 32, 4 KiB outbound/64 KiB inbound
frames, 1 MiB aggregate, 5-second RPC and 60-second module deadlines are
unchanged. Ready/no-gap/no-uncertainty and existing owner completion/Port/native
PID cleanup remain. Launches use fixed YOLO. Only the test matrix and its exact
request counts change; no runtime, shared fixture, bound or assertion is weakened.

## Source binding and actual checks

Pin: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The native optional scope deserializes null as None. The genuine local search
processor matches None against both catalog classes, then ranks native local
matches. Three complete protocol/search/processor source files match the
immutable archive; the canonical export matches its pinned generated file.

Only `schema_contracts[4752]`, exact ID
`schema:v2/PluginSearchParams.json#/properties/scope/anyOf/1`, gains implemented
evidence. Node SHA256:
`b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb`.
Source/node binding `/tmp/samgita-v443-binding/source.json`, SHA256
`d70bca1551224a40277e0f0070fbaa6964999b05bb8c2c512ca4536292f63458`.

All nine commands in `/tmp/samgita-v443-functional-checks/final/results.json`
pass: focused **1/0**, reviewed 33-file ordinary block **55/0** at both
`501432` and `987654`, dependency Python syntax, scoped format, warning-free
driver compile, root strict Credo, inventory consistency and reviewed outside
consumer **1/0** (generated seed `723282`). That consumer uses actual pinned
Codex outside the umbrella without Samgita Repo, Phoenix or platform startup.
Results SHA256:
`db42b8bb6e0f610ea8dc76d73ef681ce39a69cdececf480d3e919eec7830f4c1`.
All 415 guarded sources stay stable during validation; 414 prior paths remain
exact and only this scope module changes. Guard SHA256
`26b7c6fea20e62853e891da4dfe68ffc7b9a0139fba8a625d01f2c95e13616be`.
Test SHA256
`93602b891fcd506b256426212cd9638f500073982a21d3fe8970a3567a221e5c`.
Binder `/tmp/samgita-v443-bind.py`; evidence JSON SHA256
`f333b590f230b53873e20563a9f9b520c885eff1f4328a20e06a99d5050ac223`.

Contracts: **5,248 implemented / 1,307 missing / 66 blocked**. Requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
This ordinary projection does not qualify every PluginSummary field, remote or
workspace catalogs, requested remote limits, actual remote pagination or other
OS/transports/platforms. No mocked app-server producer or legacy success is
substituted. Security/permission tests and audits, broad suites and hosted
workflows remain unrun. A11, upstream-unreachable legacy, external/platform/
full-goal and release gates remain incomplete. No publication or deployment.
Rollback reverts this matrix addition and its one evidence binding, preserving
runtime and records. Continue ordinary environment failure observation and
exact upstream producer-limit evidence.
