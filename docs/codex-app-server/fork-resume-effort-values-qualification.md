# Native fork and cold-resume effort values

Two ordinary functional cases qualify four exact response alternatives on
immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Each case uses an independent owned home, the real app-server and an assistant-only
Responses fixture. The fixture supplies fixed model text; it does not emulate
fork/resume operations or produce app-server frames. No Samgita platform or
database is required.

## Response, applied settings and actual inference

The model catalog supports low effort but deliberately declares no default.
Fixed literal instructions and unique child/parent user markers prescribe
inference independently of native observations.

| Configuration | Actual fork/resume response | Applied effort snapshot | Actual provider reasoning |
| --- | --- | --- | --- |
| Effort absent | Present null | Present null | summary concise; effort member absent |
| Effort low | low | low | summary concise and effort low |

Each case creates and names a durable empty legacy parent through public APIs.
A real fork must return a distinct child/path, forkedFromId equal to that original
parent, empty initial history and the independently expected reasoningEffort.
A summary-only update produces a matching applied-settings notification without
overwriting effort. One ordinary child turn must actually complete with fixed
assistant text; its real provider request must contain the prescribed reasoning,
instructions, child marker and actual thread/turn identities.

The original parent's ID/name/path, empty history and rollout bytes remain
unchanged through child work. The first hash-checked owned native process closes
and disappears. A distinct checked process cold-reads that original parent
without loading or inferring. It then resumes the **original parent**, explicitly
selecting mock-model, and independently repeats the response→summary snapshot→
actual inference chain with a different input. Exactly two provider requests
occur per home, child then parent. Completed legacy histories retain distinct
IDs/markers/paths and fixed assistant answers; readback preserves the entire
provider journal, configuration/catalog bytes/hashes and empty workspace.

Explicit model selection matters. The pinned
[resume branch](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L4166)
can clear configured effort when empty saved metadata has none and no explicit
model override is supplied. This unit deliberately qualifies the explicit-model
branch and leaves that separate restoration/default branch unqualified.
The [fork handler](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L5476)
and response assembly read genuine child configuration. Actual inference
resolves selected/default effort separately; provider serialization omits None,
so null response and absent provider effort are distinct observations.

Twelve complete production files byte-match the archive, both experimental
exports match pinned provenance and all four owner-node hashes match inventory.
Source/owner and implementation handoffs are in
`/tmp/samgita-v230-next-functional-candidate/` and
`/tmp/samgita-v232-fork-resume-effort-implementation/`. Before first execution,
parent review replaces draft whole-thread warm/cold equality with prescribed
empty legacy history, stable correlated ID/name/path and unchanged bytes:
runtime status is legitimately different across loading. No executed failing
assertion or effort oracle is removed. Independent review in
`/tmp/samgita-v233-fork-resume-review/` finds no actionable functional defect.

Four unchanged encoded fork/resume/turn requests per case have unique IDs matched
to genuine response IDs. Capture is bounded to eight frames/4096 bytes; events
are bounded to 256/one MiB with explicit gap detection. Requests/initialization/
settings use fixed 5s bounds and turns 20s. Existing captured-connection cleanup
and exact native disappearance remain. Yolo launch is fixed owned setup only;
there are no policy assertions or production configuration changes.

## Exact owners and checks

Only **5230/5231**, ThreadForkResponse reasoningEffort value/null alternatives,
and **6041/6042**, ThreadResumeResponse equivalents, receive scoped implemented
evidence after final checks. No settings/start/provider enum alias, whole
response, other effort value or omitted-model branch inherits these results.
The first focused real-native run passes **2/0**, seed 501432, in 6.1 test seconds;
log `/tmp/samgita-v232-fork-resume-first.log`.

The final twenty-two-file block is the twenty-one reviewed files documented in
[start-default qualification](thread-start-default-values-qualification.md#exact-owners-and-qualification-boundary)
plus `test/native_fork_resume_effort_values_test.exs`. Both full runs with
`--warnings-as-errors --seed 501432` and `--seed 987654` pass **37/0**, in
**66.795/66.514** command seconds. Warning-free compile, scoped format, strict
Credo on **474 files**, outside-umbrella consumer **1/0**, both Python AST checks
and the **247-file** unchanged-source guard pass. All eight commands complete;
no runtime failure, increased deadline or weakened gate occurs in this unit.

Exact commands/logs/source: `/tmp/samgita-v234-functional-checks/functional/`.
Results/source SHA256:
`77c3184c6b548346e728252282e1f3d20c47b9f80adc20ef7a40832551d6eb4a` /
`0a47b97705338a19f0d042438a6408b5ac252594557006b6cea2288e509f429d`.
The adjacent `manifest-binding-fork-resume.json` binds original/current rows and
test SHA256 `07f9cdf36affe2e990ab921b15115a0812f84dc7ba15ac6c4e23c03e43ece9b9`.
Contracts become **4,699 implemented / 1,863 missing / 59 blocked**; requirements
stay **462 implemented / 12 missing / 11 blocked**, zero verified in both.
No runtime library, shared helper or previous process cleanup is changed.

Other history modes, model-default/effort values, transports, OS/backends and
complete compatibility remain unqualified. Security/permission-related checks
and related broad/hosted workflows remain unrun under the user's restriction.
A11, source-unreachable legacy paths and real external acceptance remain
incomplete. No release, publication, deployment or production migration occurs.
