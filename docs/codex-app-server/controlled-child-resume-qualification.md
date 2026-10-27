# Controlled idle child resume

V416 starts from `main` `4c13b76d7e78ad8547093480aceadddd749a7955`.
Only physical owners2082/5291 gain scoped implemented evidence for
`CollabAgentStatus.pendingInit` in live notification and selective history.
The official pin remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

The existing three-phase actual-native V1 lifecycle completes and closes a
child, proves that exact child unloaded, then resumes its completed history
without submitting child input. A separate loaded-list query proves the same
child is loaded before the later followup can implicitly load it. Its genuine
completed resume item must equal this complete independent oracle:

```elixir
%{
  "id" => "owned-collab-resume",
  "type" => "collabAgentToolCall",
  "tool" => "resumeAgent",
  "status" => "completed",
  "senderThreadId" => root,
  "receiverThreadIds" => [child],
  "prompt" => nil,
  "model" => nil,
  "reasoningEffort" => nil,
  "agentsStates" => %{child => %{"status" => "pendingInit", "message" => nil}}
}
```

Warm selective history must return the same full item and original bounded
native start/end timestamps. The actual model-provider tool result separately
must equal `{"status":"pending_init"}`; neither observation constructs the
other expectation. Both are prescribed by source. The loopback provider emits
only model SSE; stock Codex owns all native lifecycle events and persistence.

## Producer and persistence evidence

Pinned `core/src/agent/control/resume.rs:14–35` loads the absent runtime from its
rollout and reads its new status. `control/spawn.rs:1440–1510` constructs resumed
history and re-registers it without submitting a turn. `session/mod.rs:959`
initializes PendingInit; `1643–1723` restores only Interrupted from history.
Completed history therefore leaves this idle runtime PendingInit. New turns
change status through `agent/status.rs:6–23`; the fixture proves none occurred
during this snapshot.

`tools/handlers/multi_agents/resume_agent.rs:84–136` emits the real completed
item with its effective receiver status. `multi_agents.rs:86–97` marks this
tool completed, independently of receiver state. `v2/item.rs:965–983,1305–1338`
maps the public value to `pendingInit`/null; `protocol.rs:1929–1947` serializes
the model-facing value as `pending_init`. The ordinary outgoing path is
`bespoke_event_handling.rs:1077–1138`; `rollout/src/policy.rs:137–144` retains
canonical ItemCompleted and `thread_processor.rs:3622–3669` serves it.

Twenty-five complete upstream files and both exact schema nodes match the
immutable archive. Owner5291 uses the experimental export; stable export lacks
that response. `/tmp/samgita-v416-source/evidence.json` SHA256:
`8467edcaf489f303a4886b33ec3a29306753449836f92144fa083943fa11b5a3`.
Both literal-node SHA256 values are
`92bb841157c533e14eb43d906eb4f708a9baff6b5812d824294ac1d489f85165`.

## Final permitted verification

Only the existing test changes. No extra RPC, provider request, scenario,
process, helper behavior, deadline or cap is added. Original six/eight/thirteen
request barriers, eleven root/two distinct child-turn requests, twelve unique
native request envelopes, exact other tool results, loaded observations,
provider/config/workspace immutability, bounded event/capture state and owned
cleanup remain. Spawn/send snapshots stay timing-dependent and unqualified.

The owning module's two ordinary cases use direct fixed YOLO, owned temporary
resources and loopback model input. Its second case retains the independent
first-cold null-agent-path search proof. The module calls only ordinary setup,
catalog and pure notification helpers; historical execution/security controllers
and the base provider's unused command scenario are never invoked.

Runner `/tmp/samgita-v416-run.py` preserves isolated Elixir1.18.5/OTP27.3.4.17,
two schedulers, pinned binary and cleared inherited Mix path/partition overrides.
Focused **2/0** at501432 takes4.574 command seconds. The reviewed24-module
matrix passes **41/0** at501432/987654,67.569/67.718 seconds, no exclusions.
Eight Python syntax checks, scoped format, warning-free driver compile, root
strict Credo and inventory consistency also pass. All406 guarded sources remain
stable across checks;405 other prior paths retain their original bytes.

Final test SHA256:
`55523c105eae0dc8a4201260635c546e95cd595b6bb6676685b4e8ebd728f07d`.
Unchanged provider SHA256:
`3b0631a4b79df452b7e228a07d2a9c1ef56b7160dc52bc43665933f04c67bdef`.
Exact commands, logs, membership and source hashes are in
`/tmp/samgita-v416-functional-checks/final/{results,source}.json`, SHA256:
`0b407e912a56ed9163205b0862bc57b10f981a3c7d194d3c854afe792f44237c` /
`75574f01e73d390f191f31a4bce3d2c227d4712c89b218882df2cbae5aaa299b`.
Binder `/tmp/samgita-v416-bind.py` verifies only the two row changes;
`/tmp/samgita-v416-binding/evidence.json` SHA256:
`9c43d99ad4d1a2512d3c044e9f3e5ecdd81174cf645f5865561363549b0825ab`.

Contracts: **5,163 implemented /1,392 missing /66 blocked**. Requirements stay
**462 implemented /12 missing /11 blocked**; zero verified. This is no cold
PendingInit, other alias/producer, transport/OS, external or full-goal claim.
The pin's V2 `analytics.rs:10,18–61` explicitly constructs private analytics
without a public tool item; exercising sendMessage/followupTask/interruptAgent/
listAgents cannot qualify their public collab literals. Interrupted tool-call
status, transient inProgress selective history and shutdown also remain
unqualified. No mock or supplied canonical history substitutes for native proof.

Prohibited security/permission tests, audits and mixed broad/hosted workflows
remain unrun; pushes suppress CI. A11, unreachable producers, external/platform
acceptance and release gates remain incomplete. No publication or deployment.
Rollback restores the single test and two bindings without runtime/history
changes. Continue the separately gated actual interrupted-child close and its
warm/first-cold persisted status.
