# Local readiness and unknown environment status

V431 starts from `main` `df0e9a2ae7820799a823f87430d30d45c40c1c02`.
The existing [unclassified-error case][test] now checks global environment
status before and after its thread-local resource-absence failure. Only four
exact physical owners gain scoped implemented evidence:

| Index | Owner below `schema:v2/EnvironmentStatusResponse.json#` | Value |
| --- | --- | --- |
|3912|`/definitions/EnvironmentStatusKind/oneOf/0`|complete ready branch|
|3913|`/definitions/EnvironmentStatusKind/oneOf/0/enum/0`|`ready`|
|3918|`/definitions/EnvironmentStatusKind/oneOf/3`|complete unknown branch|
|3919|`/definitions/EnvironmentStatusKind/oneOf/3/enum/0`|`unknown`|

Two explicit public status requests require independent full results:

```json
{"status":"ready"}
{"status":"unknown","error":"unknown environment id `owned-v431-unconfigured`"}
```

The first selects `local`; the second selects the exact unconfigured identity.
Both repeat after the real standalone shell task fails because its thread
selected `environments:[]`. Thus thread selection and global local readiness
remain separate. Status reads do not register/recover an executor or launch
work. Full original RPC byte/map correlation and canonical response validation
hold for all four calls; ready omits error, unknown supplies the exact message.
No pending/disconnected, remote-health or connection-recovery claim follows.

All earlier full error/failed-turn oracles remain, including the exact nonnull
TurnError with inner null, original event ordering, no inference/command effect,
frozen provider/config/catalog bytes and empty workspace. The precise outgoing
inventory gains only four environment/status reads. Existing128frames/2MiB,
64KiB inbound/8KiB outbound,5s startup/RPC,shared20s active/60s case and checked
owner/PID/Port cleanup bounds remain. Fixed YOLO is setup; no security or
permission behavior is exercised.

Official pin: `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Four complete upstream files match the immutable archive. The public status
types at `app-server-protocol/src/protocol/v2/environment.rs:98–149` distinguish
these branches and omit absent errors. The real handler at
`request_processors/environment_processor.rs:81–106` supplies the independent
unknown diagnostic. `exec-server/src/environment.rs:476–483,1163–1174` only
observes the manager and maps a local backend to Ready, without starting it.
All four canonical nodes match unchanged generated exports.
`/tmp/samgita-v431-source/evidence.json` SHA256:
`9a23b1476258b4d7c897dbb4b7f2072295e689e07df1c24daeb215a4772cfbe5`.

Initial and final focused checks pass **1/0**. The final combined ordinary
27-module selection, including the separately owned Interrupt Hook case, passes
**45/0** at501432/987654 in74.137/74.289 command seconds. Ten Python syntax
checks, scoped format, warning-free driver compile, root strict Credo and
inventory consistency pass. All411 final source hashes are stable:408 prior
paths retain their bytes, this test changes, and two Hook files are new.
The new files are independently scoped; they supply no status evidence.

Test SHA256:
`325e02c0b9501b90ab755cdb05c3f9122fada59d0d572060242e7f3002826692`.
Runner `/tmp/samgita-v428-v431-run.py`; final results/source guard:
`/tmp/samgita-v428-v431-functional-checks/final/{results,source}.json`, SHA256
`66a2f7b93305dfed837c9c89f6e1eb27201076f4d8e40e9573c7243dc9aadc70` /
`805aaec99ddafc1dbc225042d03ef338af3ef868ba52300bf40d29bc7f69dd89`.
Binder `/tmp/samgita-v428-v431-bind.py --unit status`; evidence
`/tmp/samgita-v431-binding/evidence.json` SHA256:
`9603a0d46af9e75d47d3cc896acc18931f0867c8ae9ff5b0ce12af2a9a76e5f9`.

Only these four become implemented: **5,196 implemented /1,359 missing
/66 blocked** contracts. Requirements remain **462 implemented /12 missing
/11 blocked**, zero verified. Prohibited security/credential/authentication/
authorization/permission/approval tests and audits, broad suites and hosted
workflows stay unrun; existing gates remain. A11, unavailable producers,
external/platform/full-goal and release acceptance remain incomplete. Pushes
suppress CI. No publication or deployment. Rollback removes the added status
assertions and four bindings while preserving the original error case/runtime.
Continue the separately qualified ordinary root Interrupt Hook binding.

[test]: ../../apps/samgita_codex_driver/test/native_unclassified_turn_error_test.exs
