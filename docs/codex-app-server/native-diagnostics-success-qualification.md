# Actual native process and gauge diagnostics

The separate `native_diagnostics_success_test.exs` profile qualifies ordinary
positive Linux diagnostics through the real pinned Codex app-server. It does
not run the original mixed diagnostics/memory suite or infer Agent health.

Pin: `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
Linux x86_64 musl/stdio. Binary SHA256:
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

## Independent process and memory observations

Every native request has a unique string ID, exactly one captured outgoing
envelope and one correlated incoming response. The full decoded and raw JSON
must match. Capture is bounded to 256 frames, 262,144 bytes per frame and
4,194,304 bytes total, with an explicit overflow failure.

The complete process response must contain only ID, resident memory and
physical footprint. The positive uint32 PID must identify the pinned executable
by both `/proc` link and whole-file hash; its parent PID must be the explicitly
owned Stdio wrapper. RSS is a positive uint64 and a multiple of the operating
system page size, obtained independently with Python `os.sysconf`. That small
probe uses the existing Stdio owner, a five-second deadline and unconditional
close/reap checks. Linux physical footprint must be present and null.

RSS is not equated to a later `/proc/self/statm` sample: legitimate allocations
can change it between observations. Exact pinned source computes resident pages
times page size. This is memory-measurement evidence for the declared profile,
not a cross-platform memory guarantee or a healthy-Agent decision.

## Real gauge lifecycle and cold reads

Every complete gauge row has exactly name/value, a nonempty name and uint64
value. Names must be sorted and unique. The request-in-flight gauge retains its
source-supported bounded oracle; unrelated scheduler-dependent values are not
frozen to invented constants.

The warm process starts without a registered `core.threads.live` gauge. Two
explicit ordinary empty threads produce the exact loaded-ID set and live count
two. Both IDs are archived, then normal owned shutdown must complete, close the
port and remove the actual native process before the cold process starts.

The cold process has a distinct independently bound PID, no registered live
thread gauge and an empty loaded list. Both persisted thread IDs and empty
turn histories remain readable. A second snapshot and loaded-list query prove
these reads did not hydrate live execution. No turn is started. Exact outgoing
method counts rule out hidden execution; model requests stay zero, inputs and
configuration bytes remain exact, and the workspace remains empty. Native,
probe and provider resources retain their existing explicit ownership/cleanup.

## Exact field and source binding

Only these `v2/ServerDiagnosticsResponse.json` physical owners become scoped
**implemented**:

| Owner | Pointer | Node SHA256 |
| --- | --- | --- |
| 5073 | `/definitions/ServerDiagnosticsProcess/properties/residentMemoryBytes` | `8f759d27691871647f729a7988d8638fcadd6eb4c42b76dcaadb49e493060583` |
| 5074 | `/properties/gauges` | `4b98bdfa39ade8b1d87ba0f171c86a3c6540534df8acdd78ff9553a803149fb4` |
| 5075 | `/properties/process` | `bf6b1c95ae3ba32129f0f46a32002280fbe8a7faf0fc830224f0e56ccf6005b0` |

The actual request macro, dispatch and response type map `server/diagnostics`
to the native diagnostics snapshot. Independent node hashes and pre-change
owner records bind the process/gauge references. No sibling, hash or reference
propagation occurs. Thirty-nine whole files in the retained source-evidence
union match the immutable archive, including seven directly relevant files:
protocol common/diagnostics types, message dispatch, diagnostics processor,
snapshot implementation, live-thread lifetime guard and persisted-thread reader.

Positive nonnull Linux RSS, process identity and registered gauges are covered.
Null/unavailable RSS, other OS metrics, disabled negotiation, transport reconnect,
broad default/experimental/backend matrices and whole-family qualification remain
separate. The local model fixture is a synthetic dependency with zero requests;
native snapshots and thread objects come from the stock executable.

## Final functional verification

Baseline: `26347621f4503be494e311f8abcc620f1b461aeb`.
The owning profile passes **1/0**. Final affected five-file checks pass
**11/0 twice**, seeds `501432` and `987654`, in 35.824s and 35.984s.
Scoped format, warnings-as-errors compile, strict Credo on 509 sources, outside
actual-binary consumer **1/0** and retained relay/inline Exec AST checks pass.
The 311-source guard is stable, with all 310 prior sources and production
protocol/driver/process cleanup byte-identical. No retry, sleep, removed
assertion, test skip, deadline increase or new functional failure occurs.

Commands/logs: `/tmp/samgita-v346-run.py` and
`/tmp/samgita-v346-functional-checks/final/`; source/final bindings:
`/tmp/samgita-v346-source.py` and `/tmp/samgita-v346-bind.py`.

| Artifact | SHA256 |
| --- | --- |
| Functional results | `827ac910bd97eb4a825dcc4b02ae966da9a119754e174f0d02a1bbd640f53e57` |
| Source guard | `687d00da32c8291c3bc285349bbc65c2d0cf1e24aeaad21318adec517259e86f` |
| Whole source/schema comparisons | `f44c0526f1eca142e05e78469e8f17e14d76a62754384f0d72e4b47a6e1963fe` |

Inventory consistency passes; strict completeness exits **1**. Contracts become
**5,009 implemented / 1,546 missing / 66 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified. Fixed YOLO is
ordinary launch setup. Prohibited security/credential/authentication/
authorization/permission/approval tests and audits, broad suites and hosted
workflows remain unrun. A11, source-unreachable legacy, unavailable external/
platform/OS success, full compatibility and release remain incomplete. No real
provider integration, package publication, deployment or production migration
is established.
