# Native history, MCP, Guardian and local metadata continuation

Status: 112 selected physical contracts implemented; **full compatibility incomplete**.
This extends actual-binary behavior assertions rather than substituting a scripted
app-server. Target: `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The local provider, MCP and backend peers return prescribed synthetic data;
every asserted app-server response/notification comes from that immutable binary.

## Observed behavior and ownership

| Cases | Selected physical owners | Direct native evidence and limits |
| --- | ---: | --- |
| Persisted message phases | 7 | Exact final_answer, commentary and partial_answer agentMessage items survive warm and first cold selective `thread/items/read`; duplicate IDs collapse and absent IDs/turns return empty. Exactly one provider sample; owned PID and connection generation change. |
| Failed/disabled MCP startup | 4 | Fixed initialize rejection produces failed status, diagnostic toolsError and null serverInfo. Disabled alpha receives no MCP traffic, while beta stays healthy. Explicit reload recovers/enables alpha; failed case also proves healthy cold restart. |
| Guardian assessments | 7 | Held review emits approved/low/high after release, dispatches exactly one fixed in-memory MCP result and continues once. Medium/low and critical/medium denials preserve exact reviews/warnings with zero tools/call or approval RPC. |
| Plugin detail/search | 66 | Complete direct rich metadata, namespaced/normalized skill interface, assets and onboardingSkill maps agree in warm and distinct cold native processes. Source bytes and idle state remain unchanged. |
| Retained plugin installed projection | 25 | Complete direct `plugin/installed` equality in the same rich/cold case binds its own physical local-source, null/available and list-field owners. It inherits no evidence from read/search definitions. |
| Project trust | 1 | Exact untrusted ConfigLayer.disabledReason; explicit owned trust enables the project model setting and origin. Trusted disabledReason is omitted. Project skills.config still cannot disable a user skill. Plain/forceReload and cold reads retain source bytes and idle state. |
| Model catalog versions | 2 | Stable-negotiated `model/list` returns complete independently prescribed disabled/v1 multiAgentVersion maps for regular/includeHidden queries. Catalog/config remain unchanged; no multi-agent execution is claimed. |

The persisted history barrier is a loaded paginated `thread/read` with
includeTurns=true: pinned native code persists the standard thread before its
response. That response supplies readiness, never the item oracle. The first
content read in the replacement process is selective, with no resume, full-read
hydration, new turn or additional provider sample. Raw provider ResponseItems
and live pending items are different contracts.

MCP reload acknowledgement alone does not await all startup. The subsequent
selected-server status query refreshes dirty runtime metadata and awaits tool
collection. Pinned plugin search intentionally reports enabled=false even when
the plugin is installed and enabled. Empty arrays and observed null values bind
only their fields/branches, not unobserved elements or non-null alternatives.
Guardian's allowed tool has one fixed in-memory implementation; no command,
network forwarding or external approval is authorized by this qualification.

## Runtime checks and first strict-check failure

The complete nine-file block includes response metadata, MCP controls, Guardian,
plugin lifecycle/MCP/sharing, skills lifecycle/CWD configuration and model
discovery. Six changed Elixir tests are formatted. All Python fixture ASTs pass;
the source preflight preserves the previously repaired shutdown/cleanup ASTs.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-reachable-v28-20261025.py
devenv shell --no-tui -- python3 -B /tmp/samgita-native-reachable-v28-r1-20261025.py
python3 -B /tmp/samgita-bind-v28-reachable112-owners-20261025.py
python3 -B scripts/codex/inventory.py --check
python3 -B -m unittest discover -s scripts/codex -p 'test_*.py'
```

The first run passes **63/0 at each seed 501432/987654**, then fails strict
Credo on four newly added zero-count predicates. It is retained in
`/tmp/samgita-native-reachable-v28-first-failure-20261025.json`, SHA256
`3ef8cf35f6fcd516d867a1a3da3ea1b36cc566c9e4f4cbe909de6d88c85e597c`.
Replacing count==0 with equivalent refute Enum.any? keeps both zero-call
assertions intact. No timeout, scenario, assertion meaning or gate is weakened.

The complete rerun passes **63/0 at both fixed seeds**, zero exclusions,
namespace/native-sandbox prerequisites, warning-free compilation, format and
strict Credo over 442 files. Its **1,495-file source guard and binary guard
match**. Exact commands, logs and preimages are under
`/tmp/samgita-native-reachable-v28-r1-20261025/`. The binding report is
`/tmp/samgita-v28-reachable112-owner-terminal-20261025.json`, SHA256
`9002abc7f8039a0a9bb1635602874f3e1131abd9afd5ce941767b598fd8f9d51`;
the adjacent owner-bound index records original rows, canonical nodes, exact
named cases, test hashes and observed scope. Only those 112 rows change.

## Remaining gates

The ledger becomes **4,013 implemented / 2,608 missing contracts**, zero verified.
Requirements remain **462 implemented / 12 missing / 11 blocked**, zero verified.
This scoped pass does not replace the complete combined-source matrix or
final-pushed hosted checks. The retained populated GitHub pagination assertion,
cursor defects, unexplained listener failure, A11, upstream-unreachable emitters
and real external/backend/OS success remain incomplete. No historical data is
deleted or activation safeguard bypassed. Continue exact request correlation and
remaining compatibility work. No tag, publication or deployment occurs.
