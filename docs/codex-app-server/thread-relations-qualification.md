# Native spawned-thread relation qualification

Two cases pass twice against immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, over Linux stdio: **2 tests / 0
failures**, seeds `501432` and `987654`, 3.4 seconds each. Binary SHA256:
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
This is selected local implementation evidence with a synthetic Responses
provider. Full compatibility remains incomplete.

## Real graph and public observations

The scoped executable files are
`apps/samgita_codex_driver/test/native_thread_relations_test.exs` and
`scripts/codex/thread_relation_fixture.py`. Test lines 35-53 create an unrelated
thread and a real native tree: root -> A -> grandchild, then root -> B. Native
`multi_agent_v1.spawn_agent` and `wait_agent` tools run inside the owned
app-server. The fixture supplies only fixed Responses function calls and
assistant content; Codex generates child IDs, tool results, graph state,
app-server responses and notifications. No SQL seed, fake app-server frame,
external Agent, paid model or shell tool supplies the positive evidence.

Fixture lines 62-88 require each single-child wait to report completion before
the parent proceeds. Exactly **11 provider requests** settle the tree: root 5,
A 3, B 1, grandchild 1 and unrelated 1. The test obtains all child IDs from
actual native function-call outputs (lines 165-175). Root spawn notifications
independently assert exact call ID, parent, receiver, prompt, `spawnAgent` and
`completed` (lines 177-189).

Test lines 54-107 require exact direct-child `[B,A]` and recursive `[B,G,A]`
results. The grandchild's projected parent is A, with depth 2; A/B have root as
parent and depth 1. Public source objects use
`{"subAgent":{"thread_spawn":...}}`, with nested `parent_thread_id` and `depth`.
The fixture provider and owned cwd are retained, and `forkedFromId` is null.
Spawn ancestry is distinct from fork lineage.

One-row forward pagination in both created-at directions returns complete,
ordered identity sets without duplicate rows or repeated cursors (lines 75-81,
192-213). Omitted/null relation source filters and positive `subAgent` /
`subAgentThreadSpawn` filters include the actual children. Explicit empty or
`vscode` sources and an absent provider exclude them. Leaf, unrelated-parent and
missing-ancestor queries are empty. Null relation selectors restore ordinary
interactive listing. Excluding B still fills a two-row descendant page.

Lines 109-118 close the owned process and start a new one. Cold listing preserves
the durable ID, parent, fork, source, cwd, provider and creation-time projection;
direct-child listing and ascending descendant pagination still match. Loaded
membership is empty before and after listing, provider request bytes remain
unchanged, and the new session has no pending, uncertain or interactive work.
This proves this fixture's local graph survives process replacement without
loading or executing the children. It does not prove child execution recovery.

The second case (lines 121-155) checks malformed UUIDs, malformed native-wire
types, the exact mutual-exclusion error and experimental negotiation rejection
for both selectors. It leaves the loaded set empty and makes zero provider
requests.

## Pinned source boundary

Paths below are relative to the pinned checkout's `codex-rs/` directory.

- `app-server-protocol/src/protocol/v2/thread.rs:1470-1480` declares direct-parent
  and recursive-ancestor selectors as experimental and mutually exclusive; the
  ancestor excludes itself.
  `app-server/src/request_processors/thread_processor.rs:2677-2697` parses UUIDs
  and selects the graph filter.
- `app-server-protocol/src/protocol/v2/thread_data.rs:27-55` defines the public
  `SessionSource` with camelCase outer variants and converts the internal source.
  `SubAgent` therefore becomes `subAgent`. The nested `CoreSubAgentSource` retains
  `thread_spawn` and snake_case fields from `protocol/src/protocol.rs:3027-3047`.
  Internal `SessionSource` serialization is not the app-server response contract.
- `core/src/tools/handlers/multi_agents/spawn.rs:111-147,226-244` creates a fresh
  nonfork child and returns its native ID.
  `core/src/tools/handlers/multi_agents_common.rs:141-170` constructs parent/depth
  source metadata.
  `core/src/agent/child_config.rs:114-155` retains the captured provider.
- `core/src/agent/control/spawn.rs:836-908` awaits the graph-write task before
  completing this spawn path. However `core/src/agent/control.rs:667-697` can
  skip unavailable graph storage and logs graph-write errors as warnings. A
  successful spawn response alone does not certify a persisted edge. The exact
  native lists and cold repeat provide the positive persistence evidence here;
  graph-store error handling is not qualified.
- `app-server/src/request_processors/thread_processor.rs:5790-5820` gives
  relation queries their all-source default.
  `app-server/src/filters.rs:6-26,58-85` defines explicit empty interactive
  filtering and the two positive subagent source filters.
- `state/src/runtime/threads.rs:1235-1315` queries direct edges or a recursive
  subtree, excludes the ancestor, projects immediate parents and applies order
  and limit. `app-server/src/request_processors/thread_processor.rs:6373-6403`
  builds public parent/fork fields.
  `app-server-protocol/src/protocol/v2/item.rs:373-399,1227-1250` defines the
  asserted collaboration item fields/status.

## Validation record and limits

The initial seed `501432` run was **2 tests / 1 failure / 2.8s**. The draft
incorrectly expected internal outer key `subagent`; the actual public response
was `subAgent`. The completed 11-request graph had already satisfied the earlier
assertions. The parent corrected only that key at test line 68, using the public
source above, then ran both seeds successfully. The unchanged draft did not
pass. Initial log:
`/tmp/samgita-native-three-units-20261024/native_thread_relations_test-501432.log`.
One Sol repair round; no Astra recovery.

Passing logs and captured command results are in
`/tmp/samgita-native-three-units-v2-20261024/`. The recorded driver commands are
`mix compile --warnings-as-errors`, scoped `mix format --check-formatted`, and
`mix test test/native_thread_relations_test.exs --seed <seed>` for both seeds.
Namespace preflight also passes. The later integrated root `mix credo --strict`
checks **360 files / 69 checks**, finding no issues, in
`/tmp/samgita-native-three-units-v3-20261024/credo.log`. These are coordinator-run
checks inspected for this record; writing this document did not rerun them.

The passing source snapshot records test SHA256
`8525188eb7a7341804c2c7e8a6003b748de20274e3494f081274932ba6953960`
and fixture SHA256
`97f243a6e5dc314bdb86b8de177835f9a6e617b4c6943e4a5694b96e5c6d6e25`.
Both match the reviewed final files.

**21 exact contracts now have selected implemented evidence in the manifest;
zero receive verified status.** They
cover the two relation selectors, the two positive source-kind variants,
parent/source/depth projection and directly asserted completed spawn-item
fields/enums. The complete collaboration-item variant, optional source metadata,
other statuses/tools and wait-tool schema contracts are not promoted.

The positive scope is the healthy local native state store, V1 nonfork children,
created-at forward pagination, Linux and stdio. `useStateDbOnly:true` selects the
fixture path; it does not qualify rollout scan/repair behavior. Reverse cursors,
graph-write failures, mutation races, V2 agents, child restart/rollback,
external/remote storage, real providers and other OS/transports remain open.
A11, aggregate/hosted release checks, full compatibility, publication and
deployment remain independent and incomplete.
