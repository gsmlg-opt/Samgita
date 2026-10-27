# Real interrupted-child close and persisted status

V417 starts from `main` `f46ebc6e73f025cff62751cec2664a9931802fc8`.
Only physical owners2084/5293 gain scoped implemented evidence for the child
status `interrupted` in notification and selective-history schemas. The close
tool itself succeeds with status `completed`; these are distinct states.

Pin: official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
New provider/test use direct fixed YOLO and owned synthetic local work. The
provider supplies finite Responses SSE, never app-server frames or native IDs.

## Actual interruption before a stable close snapshot

The root's first response invokes real V1 spawn_agent. The finite provider
records a real child HTTP request and withholds its response; it separately
holds the root's second response, which contains the native spawn result.
Readiness requires both actual requests and the original matching child
turn/started. The native IDs from the child HTTP metadata and spawn result
must agree; global HTTP arrival order is unconstrained.

Public turn/interrupt targets those actual child thread/turn IDs. Its original
correlated successful ACK and the matching native interrupted turn/completed
must both arrive and validate before the test releases the owned provider's
stdin gate. That terminal has null error, no items and no child final answer.
The test preserves this two-observation barrier without prescribing ACK versus
completion wire order. The pinned handler awaits response enqueue, but the
outgoing path uses `write_complete_tx: None`; no cross-task client-write fence
is assumed.

Only after this barrier does root response2 invoke real close_agent. Complete
independent started/completed close items prescribe the fixed call/tool ID,
parent/child associations, null prompt/model/effort and all fields. Started is
inProgress with empty agentsStates; completed is completed with
`{child: {status: "interrupted", message: null}}`. Original full wrappers,
clock brackets, current generation, strict event order and raw ingress equality
are required. The actual final provider request contains exactly
`{"previous_status":"interrupted"}`, followed by a prescribed root answer.

Exactly four actual model requests occur: three root requests in one turn and
one held child request in its own turn. Exact SSE journals and provider state
are independently checked. Public loaded-list confirms child removal. Warm
selective history must equal the independent completed item and original
validated native timestamps. After checked shutdown, a distinct pinned process
has an empty loaded-list; its first content read returns that exact entry
without resume or new inference. Request count/journals, config/catalog and
the empty workspace remain unchanged across readback, restart and shutdown.

## Pinned producer and lifecycle evidence

`app-server/src/lib.rs:1298–1320` and `thread_processor.rs:3769–3838` attach the
actual created child to initialized clients. `turn_processor.rs:1619–1663`
registers a non-startup interrupt; `bespoke_event_handling.rs:1208–1224,1571–1584`
responds upon actual TurnAborted and emits interrupted completion.
`core/src/session/mod.rs:2700–2708` updates status before publishing the core
event; `agent/status.rs:13–19` maps it to Interrupted.

`agent/control/legacy.rs:50–111` snapshots status before teardown and returns
that snapshot. `tools/handlers/multi_agents/close_agent.rs:72–112` uses it for
both completed canonical item and provider result. `multi_agents.rs:86–97`
marks an existing interrupted receiver's close operation completed;
`v2/item.rs:1305–1338` maps child status to interrupted/null. A later shutdown
cannot replace the captured status. V1 wait is deliberately absent because
`agent/status.rs:26–31` excludes Interrupted from final statuses.

`rollout/src/policy.rs:132–144` retains canonical ItemCompleted;
`thread_processor.rs:3622–3669` serves its stored entry without loading work.
Twenty-six complete sources match the immutable source archive; both exact
schema nodes match the correct stable/experimental exports. Source artifact
`/tmp/samgita-v417-source/evidence.json` SHA256:
`e6519bad5b4fb6a2dd2c505f1fe366c45cb8bfa2a57e82e1c38015e67d34a61c`.
Both scalar nodes hash to
`f855378058a19fb7ebeb43188cc3fb801b899123d893631a2f807044e2c7e437`.

## Verification, first failure and bounds

Initial actual-native focused run passes **1/0**. The first final-matrix
attempt stops at strict Credo: await_ready complexity11 exceeds9. All readiness
assertions move unchanged into a small helper; no assertion, gate, synchronization
condition or limit is removed. Its failed logs remain in
`/tmp/samgita-v417-functional-checks/final/`; subsequent final results use
`repaired/`, never the failed attempt.

Runner `/tmp/samgita-v417-run.py` uses isolated Elixir1.18.5/OTP27.3.4.17,
two schedulers, pinned binary and cleared inherited Mix path/partition overrides.
Final focused **1/0**,3.072 command seconds, and reviewed25-module matrix
**42/0** at501432/987654,69.478/69.477 seconds, pass without exclusions.
Nine Python syntax checks, scoped format, warning-free driver compile, root
strict Credo and inventory consistency pass. All408 guarded source files are
stable; all406 prior paths retain their original bytes.

Raw capture and Session remain128 messages/2MiB; inbound64KiB/outbound8KiB,
request1MiB, SSE64KiB, journals2MiB, startup/RPC/readiness5s, one shared20s active
deadline, case60s and held-handler30s ceilings all fail explicitly. Provider
teardown releases both gates before joining handlers. Both native instances
and the provider have executable/PID checks, owner completion, Port closure and
process disappearance; cleanup runs before deleting owned temporary directories.

Final test/provider SHA256:
`6864df9f6217abb809cb558599fe98c80a4d48e96fc6a268f7892500d427891b` /
`baccf44853bd7b0daf029f21e993bf6d3e7744fc3990554260b92d556b521a55`.
Commands/logs/membership/source hashes:
`/tmp/samgita-v417-functional-checks/repaired/{results,source}.json`, SHA256:
`9565c7cbf5da31b8a1dec61e707838c8d30d770f0e0e03adce4ee741ecf2ad1c` /
`98fb1db4a2e3416d6d64dd447993954c498b751bce66313251fd5deda649ccfa`.
Binder `/tmp/samgita-v417-bind.py` validates only2084/5293;
`/tmp/samgita-v417-binding/evidence.json` SHA256:
`68951fc74cc705cd59eea4006681cf9748f574f6634d468df66ac6713f75b376`.

Contracts: **5,165 implemented /1,390 missing /66 blocked**. Requirements stay
**462 implemented /12 missing /11 blocked**, zero verified. This does not
qualify shutdown, interrupted tool-call status, private V2 analytics, transient
stored items, other producers/aliases/transports/OS or external/platform success.
Prohibited security/permission tests, audits and broad/hosted checks stay unrun;
pushes suppress CI. A11, unreachable legacy producers and full-goal/release
gates remain incomplete. No publication or deployment. Rollback removes the
two new files and two bindings, leaving runtime and historical records intact.
Continue the ordinary saved-setting null and process-stream union owners.
