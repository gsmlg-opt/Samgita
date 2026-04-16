# Samgita — Comprehensive Code Review & Suggestions

> Generated: 2026-04-14  
> Scope: All four umbrella apps (`samgita`, `samgita_web`, `samgita_memory`, `samgita_provider`)  
> Method: 6 parallel specialist agents — code quality, performance, architecture, security, testing, documentation  
> Total findings: **90** across 6 categories — 19 High, 34 Medium, 37 Low

---

## Table of Contents

1. [Code Quality Issues](#1-code-quality-issues)
2. [Performance Optimizations](#2-performance-optimizations)
3. [Architecture Suggestions](#3-architecture-suggestions)
4. [Security Issues](#4-security-issues)
5. [Testing Improvements](#5-testing-improvements)
6. [Documentation Gaps](#6-documentation-gaps)
7. [Priority Summary](#7-priority-summary)

---

## 1. Code Quality Issues

### CQ-01 · Duplicate 18-line "verify success" block — exact copy-paste

**File:** `apps/samgita/lib/samgita/agent/worker.ex` lines 399–446  
**Priority:** High | **Effort:** S (<2 h)

The `is_binary(result)` and catch-all `_` arms of the `verify` state's `case` expression are **identical** — 18 lines including 6 side-effecting calls and the struct reset. The only difference is a single log message.

```elixir
# Current — both arms do EXACTLY this:
CircuitBreaker.record_success(data.agent_type)
ActivityBroadcaster.broadcast_activity(data, :verify, "Task verified successfully")
handle_task_completion(data)
complete_and_notify(data)
WorktreeManager.maybe_checkpoint(data)
notify_caller(data.reply_to, data.current_task, :ok)
close_session_if_open(data)
reset_message_budget(data)
data = %{data | current_task: nil, act_result: nil, ...}
{:next_state, :idle, data}
```

**Fix:** Extract `handle_verify_success(data)` and call it from both arms. The `_` arm is effectively unreachable (all successes are binary), so it can be merged into the binary guard.

---

### CQ-02 · `Process.sleep/1` on the hot-path of a gen_statem worker

**File:** `apps/samgita/lib/samgita/agent/worker.ex` line 629  
**Priority:** High | **Effort:** S

```elixir
[] when retries > 0 ->
  Process.sleep(500)   # blocks the gen_statem process for up to 1.5 s
  do_notify_orchestrator(project_id, task_id, retries - 1)
```

Blocking in a `gen_statem` state callback prevents the process from handling any messages or timeouts during that window — a core OTP anti-pattern.

**Fix:** Use `{:keep_state, data, [{{:timeout, :notify_orchestrator}, 500, {task_id, retries}}]}` and handle the named timeout in the appropriate state.

---

### CQ-03 · Repeated `Projects.get_project` DB fetch per RARV cycle iteration

**File:** `apps/samgita/lib/samgita/agent/worker.ex` lines 158, 769, 857+  
**Priority:** High | **Effort:** M (2–8 h)

`Projects.get_project(data.project_id)` is called 3–4 times per RARV cycle: in `:reason` (via `get_working_path`), in `:act` (same), and in `fetch_project_for_provider`. The `working_path` guard exists but only caches after `:act`, so `:reason` always hits the DB.

**Fix:** Cache `working_path` and `provider_preference` in the worker struct during `init/1`. These fields are set at project creation and never change at runtime.

---

### CQ-04 · `compute_node_wave` memoisation is always empty — O(n!) worst case

**File:** `apps/samgita/lib/samgita/tasks/dependency_graph.ex` lines 116–139  
**Priority:** High | **Effort:** M

```elixir
defp compute_wave_numbers(graph) do
  Enum.map(graph.nodes, fn node ->
    wave = compute_node_wave(node, graph, %{})  # fresh empty memo per node!
    {node, wave}
  end)
end
```

The memo map is passed by value and never threaded back out, so memoisation is a no-op. For diamond DAGs this causes exponential re-computation.

**Fix:** Thread memo as an accumulator via `Enum.reduce`, or simply assign waves in topological sort order (already computed by `validate/1`) in a single O(n) linear pass.

---

### CQ-05 · `parse_severity/1` duplicates the same `cond` arm pattern 6 times

**File:** `apps/samgita/lib/samgita/quality/anti_sycophancy.ex` lines 230–257  
**Priority:** Medium | **Effort:** S

```elixir
cond do
  String.starts_with?(trimmed, "[CRITICAL]") ->
    {:critical, String.replace(trimmed, "[CRITICAL]", "") |> String.trim()}
  String.starts_with?(trimmed, "[HIGH]") ->
    {:high, String.replace(trimmed, "[HIGH]", "") |> String.trim()}
  # ... 4 more identical-structure arms
end
```

**Fix:** Define `@severity_tags` as a module attribute list and use `Enum.find_value/3` to replace all 6 arms with a single loop.

---

### CQ-06 · `parse_vote_response/2` iterates `lines` three times for three fields

**File:** `apps/samgita/lib/samgita/quality/completion_council.ex` lines 208–237  
**Priority:** Medium | **Effort:** S

Three separate `Enum.find(lines, &String.contains?(&1, "LABEL:"))` passes where one `Enum.reduce` building a map would do.

**Fix:** Extract `extract_labelled_line(lines, label)` helper. Replace the three passes with a single reduce.

---

### CQ-07 · `touch_access/1` issues two separate SQL statements where one suffices

**File:** `apps/samgita_memory/lib/samgita_memory/memories.ex` lines 121–136  
**Priority:** Medium | **Effort:** S

One `update_all` + one raw `Repo.query!` per retrieved memory, inside an `Enum.each` loop (20 round-trips per 10-result retrieval).

**Fix:** Merge into a single `Repo.query!` updating `accessed_at`, `access_count`, and `confidence = GREATEST(confidence, $1)` atomically. Use `WHERE id = ANY($2)` to batch all IDs from one retrieval call.

---

### CQ-08 · `enqueue_phase_tasks` — 9-clause, 250-line dispatch function

**File:** `apps/samgita/lib/samgita/project/orchestrator.ex` lines 559–826  
**Priority:** Medium | **Effort:** L (1–3 d)

Six of the nine clauses are structurally identical: load project → define task list literal → call `create_phase_tasks/4`. Task specifications are data embedded as code.

**Fix:** Define `@phase_task_specs` as a module attribute map from phase atom to task list. Replace the 6 identical-structure clauses with a single `when phase in @data_driven_phases` catch-all.

---

### CQ-09 · `import Ecto.Query` buried inside a private function body

**File:** `apps/samgita/lib/samgita/agent/worker.ex` lines 659–665  
**Priority:** Medium | **Effort:** S

`import` at function scope is non-idiomatic Elixir and signals a boundary violation (the only direct DB access in this module).

**Fix:** Move the query to `Samgita.Projects.find_active_agent_run/2` and move `import Ecto.Query` to the top of `projects.ex`.

---

### CQ-10 · `headers/0` in `ClaudeAPI` reads `Application.get_env` on every request

**File:** `apps/samgita_provider/lib/samgita_provider/claude_api.ex` lines 251–259  
**Priority:** Medium | **Effort:** S

**Fix:** Read the API key once in `start_session/2`, store in `session.state`, pass to `do_request/2`.

---

### CQ-11 · Unanimous completion detection logs but never calls `AntiSycophancy`

**File:** `apps/samgita/lib/samgita/quality/completion_council.ex` lines 119–143  
**Priority:** Low | **Effort:** M

The docstring says "spawn extra Devil's Advocate review" but the code only logs. `AntiSycophancy.challenge/3` exists but is never called here.

**Fix:** Wire the call or add a `# TODO:` explaining the deferral.

---

### CQ-12 · Hardcoded weights in nil-embedding branch diverge from config-driven branch

**File:** `apps/samgita_memory/lib/samgita_memory/retrieval/pipeline.ex` lines 103–114  
**Priority:** Low | **Effort:** S

Nil-embedding path hardcodes `0.7 / 0.2 / 0.1`; the embedding path reads from config. Config changes silently diverge.

**Fix:** Read config values at the top of `execute/2` and pass down to both branches.

---

### CQ-13 · `do_notify_orchestrator` re-reads `Application.get_env` inside a recursive loop

**File:** `apps/samgita/lib/samgita/agent/worker.ex` lines 619–641  
**Priority:** Medium | **Effort:** S

`Application.get_env` is called at entry and again in the base case, even though `retries` already encodes the original max.

**Fix:** Remove the second `Application.get_env` call; use `retries == 0` as the termination condition.

---

### CQ-14 · `!` negation operator — non-idiomatic Elixir

**File:** `apps/samgita_provider/lib/samgita_provider/claude_code.ex` line 222  
**Priority:** Low | **Effort:** S

```elixir
args = if !is_resume and system_prompt, do: ...
```

**Fix:** Use `not is_resume` or `unless is_resume`.

---

## 2. Performance Optimizations

### PF-01 · N+1 queries in `unblock_tasks` / `propagate_dependency_output`

**File:** `apps/samgita/lib/samgita/projects.ex` lines 376–444  
**Priority:** High | **Effort:** M

`maybe_unblock_task/2` issues **two DB queries per dependent task** (fetch hard dep IDs + count completed). `propagate_dependency_output/2` issues 2N queries per call. Worst case: 3 queries per dependent task.

**Fix:** Replace with a single CTE-based query using `HAVING count(*) FILTER (WHERE status != 'completed') = 0`. Batch dependency-output updates with `update_all`.

---

### PF-02 · N+1 `Repo.delete` loop in `cleanup_old_snapshots`

**File:** `apps/samgita/lib/samgita/workers/snapshot_worker.ex` lines 78–85  
**Priority:** High | **Effort:** S

```elixir
|> Repo.all()
|> Enum.each(&Repo.delete/1)   # one DELETE per old snapshot
```

**Fix:**
```elixir
ids_query = from(s in Snapshot, where: s.project_id == ^id,
              order_by: [desc: s.inserted_at], offset: ^keep, select: s.id)
from(s in Snapshot, where: s.id in subquery(ids_query)) |> Repo.delete_all()
```

---

### PF-03 · `Samgita.Cache` is fully implemented but never used

**File:** `apps/samgita/lib/samgita/cache.ex` (unused)  
**Priority:** High | **Effort:** S

The ETS+PubSub cache with TTL exists but `Projects.get_project/1` always hits the DB. `ContextAssembler.fetch_project_info/1` calls it on every RARV cycle for every agent.

**Fix:** Wire `Samgita.Cache` into `Projects.get_project/1` with a 30s TTL, invalidate on `update_project`. Cache PRD fetches in `ContextAssembler.fetch_prd_context/1` similarly.

---

### PF-04 · Missing HNSW vector index on `sm_memories.embedding`

**File:** `apps/samgita_memory/priv/repo/migrations/20260209000001_create_memories.exs`  
**Priority:** High | **Effort:** S

No vector index means pgvector performs a full sequential scan (O(n × 1536)) per retrieval call.

**Fix:**
```sql
CREATE INDEX sm_memories_embedding_hnsw ON sm_memories
USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
```

---

### PF-05 · Full ETS table scan for LRU eviction

**Files:** `apps/samgita_memory/lib/samgita_memory/cache/memory_table.ex` lines 75–85,  
`apps/samgita_memory/lib/samgita_memory/cache/prd_table.ex` lines 77–85  
**Priority:** High | **Effort:** M

```elixir
:ets.tab2list(@table)                    # copies entire 10k-entry table
|> Enum.sort_by(fn {_k, _v, accessed_at} -> accessed_at end)
|> Enum.take(count)
```

O(n log n) while holding a GenServer lock.

**Fix:** Use `:ets.select/2` to fetch only `{key, accessed_at}` pairs (skip copying values), or switch to `ordered_set` keyed by `{accessed_at, original_key}` for O(log n) eviction.

---

### PF-06 · O(n²) Elixir-side cosine deduplication in retrieval pipeline

**File:** `apps/samgita_memory/lib/samgita_memory/retrieval/pipeline.ex` lines 145–191  
**Priority:** Medium | **Effort:** M

For 30 candidates (3× over-fetch), `duplicate?/2` scans all accepted entries for each candidate: up to 450 cosine comparisons, each iterating a 1536-float vector in pure Elixir.

**Fix:** Build a `MapSet` of normalized content hashes (O(1) lookup per check) for content deduplication. For vector deduplication, exploit sort adjacency from the pgvector `<=>` query — only compare each entry against its immediate neighbors (sliding window, O(n·k) instead of O(n²)).

---

### PF-07 · `get_task_queue_state` loads all task rows just to count by status

**File:** `apps/samgita/lib/samgita/workers/snapshot_worker.ex` lines 66–77  
**Priority:** Medium | **Effort:** S

Loads full task structs (including JSON payload, result, dependency_outputs) just to `Enum.count` by status.

**Fix:** Replace with `Samgita.Projects.task_stats/1` which already uses `GROUP BY status` in SQL.

---

### PF-08 · Missing composite index `(project_id, status)` on `tasks`

**File:** `apps/samgita/priv/repo/migrations/20260129100001_create_tasks.exs`  
**Priority:** Medium | **Effort:** S

Most common query pattern is `WHERE project_id = X AND status IN (...)`. With only single-column indexes, Postgres must filter one with a heap scan.

**Fix:** `create index(:tasks, [:project_id, :status])`

---

### PF-09 · Missing composite index `(project_id, agent_type)` on `agent_runs`

**File:** `apps/samgita/priv/repo/migrations/20260129100002_create_agent_runs.exs`  
**Priority:** Medium | **Effort:** S

`find_or_create_agent_run/3` queries `WHERE project_id = X AND agent_type = Y AND ended_at IS NULL` on every task dispatch. No composite index exists.

**Fix:** `create index(:agent_runs, [:project_id, :agent_type], where: "ended_at IS NULL")`

---

### PF-10 · `compute_wave_numbers` memo not shared across nodes

**File:** `apps/samgita/lib/samgita/tasks/dependency_graph.ex` lines 116–139  
**Priority:** Medium | **Effort:** S

(See also CQ-04.) Each node starts with a fresh `%{}` memo; memoization never benefits from previously computed sibling subtrees.

**Fix:** Single topological-sort linear pass, or thread memo as a shared `Enum.reduce` accumulator.

---

### PF-11 · `Project.Memory.load_from_db` loads all memories then triple-filters in Elixir

**File:** `apps/samgita/lib/samgita/project/memory.ex` lines 94–109  
**Priority:** Medium | **Effort:** S

```elixir
memories = MemorySchema |> where(project_id: ^project_id) |> Repo.all()
%{episodic: Enum.filter(memories, &(&1.type == :episodic)), ...}
```

No LIMIT; runs at GenServer startup with unbounded memory growth.

**Fix:** Fetch each type separately with `WHERE type = X LIMIT N`, or use a single `GROUP BY type` aggregation query.

---

### PF-12 · JSONB `payload->>'prd_id'` filter lacks expression index

**File:** `apps/samgita/lib/samgita/projects.ex` lines 184–190  
**Priority:** Medium | **Effort:** S/M

`list_tasks_for_prd/2` uses `fragment("?->>'prd_id' = ?", t.payload, ^prd_id)` — a full sequential scan with JSONB expression evaluation.

**Fix (quick):** `execute "CREATE INDEX tasks_payload_prd_id ON tasks ((payload->>'prd_id'))"`  
**Fix (proper):** Promote `prd_id` to a first-class FK column on `tasks`.

---

### PF-13 · Double DB roundtrip per memory access with `id::text` cast preventing index use

**File:** `apps/samgita_memory/lib/samgita_memory/memories.ex` lines 121–136  
**Priority:** High | **Effort:** S

(See CQ-07.) The raw SQL uses `WHERE id::text = $2`, which prevents the UUID primary-key index from being used.

**Fix:** Use `WHERE id = $2::uuid` and merge both UPDATEs into one statement.

---

## 3. Architecture Suggestions

### AR-01 · Worker bypasses context modules to write to Repo and Prds directly

**Files:** `apps/samgita/lib/samgita/agent/worker.ex` lines 694–721, 751–757  
**Priority:** High | **Effort:** M

```elixir
# Direct Prds calls from inside a gen_statem:
Samgita.Prds.list_prds(project.id)
Samgita.Prds.update_prd(prd, %{content: result, status: :approved})

# Direct Repo.insert bypassing any context module:
Samgita.Repo.insert(Artifact.changeset(%Artifact{}, attrs))
```

Business rules ("if no PRD exists, create one") embedded in the state machine. Can't be tested independently of the RARV cycle.

**Fix:** Add `Samgita.Projects.save_artifact/2` and `Samgita.Prds.upsert_from_generation/2`. Have `Worker` call those context functions.

---

### AR-02 · `ProjectLive` calls Oban directly and duplicates bootstrap logic

**File:** `apps/samgita_web/lib/samgita_web/live/project_live/index.ex` lines 57–78  
**Priority:** High | **Effort:** S

```elixir
alias Samgita.Workers.BootstrapWorker   # web layer importing a worker module
Oban.insert(BootstrapWorker.new(%{project_id: project.id, prd_id: prd.id}))
```

The LiveView knows which Oban worker to enqueue and constructs its payload — domain orchestration in the presentation layer.

**Fix:** Move `Oban.insert(BootstrapWorker.new(...))` into `Samgita.Projects.start_project/2`. Remove `BootstrapWorker` alias from the web layer.

---

### AR-03 · Provider facade uses runtime `function_exported?/3` instead of enforcing the behaviour

**File:** `apps/samgita_provider/lib/samgita_provider.ex` lines 57–135  
**Priority:** High | **Effort:** M

```elixir
if function_exported?(provider, :start_session, 2) do
  provider.start_session(system_prompt, opts)
else
  {:ok, SamgitaProvider.Session.new(provider, system_prompt, opts)}
end
```

This pattern appears in every public function. It defeats compile-time behaviour safety and means `Codex` (which implements no session callbacks) silently degrades to stateless mode without any warning.

**Fix:** Define two sub-behaviours: `StatelessProvider` (`query/2` only) and `SessionProvider` (full session API). Use a capability struct returned by `capabilities/0` for runtime dispatch instead of `function_exported?`.

---

### AR-04 · `verify` state executes 6 sequential side effects inline with silent failure swallowing

**File:** `apps/samgita/lib/samgita/agent/worker.ex` lines 373–447  
**Priority:** High | **Effort:** M

If `complete_and_notify` fails silently after `handle_task_completion` has already written to the DB, the task is persisted as complete but the orchestrator is never notified.

**Fix:** Extract `finalize_task(data)` called from both match arms. Make `complete_and_notify` return a result tuple so failures are visible in the verify-state log.

---

### AR-05 · Worker owns provider-selection logic (resolves provider modules directly)

**File:** `apps/samgita/lib/samgita/agent/worker.ex` lines 850–898  
**Priority:** Medium | **Effort:** M

`worker.ex` constructs `SamgitaProvider.Synapsis`, `SamgitaProvider.ClaudeAPI`, `SamgitaProvider.Codex` atoms directly. Adding a new provider requires editing the worker.

**Fix:** Add `SamgitaProvider.for_project/2` that accepts a `provider_preference` atom + project metadata and returns a ready session. The worker calls only that function.

---

### AR-06 · `find_active_agent_run` duplicated identically in Worker and ActivityBroadcaster

**Files:** `worker.ex` lines 659–670, `activity_broadcaster.ex` lines 154–165  
**Priority:** Medium | **Effort:** S

Both bypass the `Projects` context with an identical private `import Ecto.Query` + `Repo.one` pattern.

**Fix:** Expose `Samgita.Projects.get_active_agent_run/2`; both modules call it.

---

### AR-07 · PubSub topic namespace is inconsistent; Dashboard reloads all projects on each event

**Files:** `worker.ex` line 98, `orchestrator.ex` lines 933–935, `dashboard_live/index.ex` lines 13–14  
**Priority:** Medium | **Effort:** S

Worker subscribes to `"samgita:agents:<id>"` but orchestrator broadcasts on `"project:<id>"` — different prefix. Workers are likely subscribed to a topic no one publishes to.

Dashboard subscribes to a global all-projects topic AND every individual project topic, then calls `Projects.list_projects()` on every event — N queries per fan-out.

**Fix:** Standardise all topics through `Samgita.Events`. In the Dashboard, update only the affected project's entry in the assigns list rather than re-fetching all projects.

---

### AR-08 · All projects and all agents share a single flat Horde DynamicSupervisor

**File:** `apps/samgita/lib/samgita/application.ex` line 20  
**Priority:** Medium | **Effort:** L

`Samgita.AgentSupervisor` hosts project supervisors, orchestrators, and individual agent workers at the same level. Stopping a project supervisor does not cleanly terminate agent workers started directly under `AgentSupervisor` by the orchestrator.

**Fix:** Keep `Samgita.AgentSupervisor` for project-level supervisors only. Have `Project.Supervisor` start a scoped `DynamicSupervisor` for its own agent workers.

---

### AR-09 · Phase task catalog hardcoded inline in the orchestrator state machine

**File:** `apps/samgita/lib/samgita/project/orchestrator.ex` lines 629–820  
**Priority:** Medium | **Effort:** M

Eight phases × inline task literals = a 250-line dispatch function. `agents_for_phase/1` (lines 429–463) independently hardcodes the same phases as a second parallel maintenance surface.

**Fix:** Move phase task definitions to `Samgita.Agent.PhaseConfig`. The orchestrator calls `PhaseConfig.tasks_for_phase/1` and `PhaseConfig.agents_for_phase/1`.

---

### AR-10 · `PrdChatLive` calls `SamgitaProvider.query/2` directly and owns system prompts

**File:** `apps/samgita_web/lib/samgita_web/live/prd_chat_live/index.ex` lines 193–267  
**Priority:** Medium | **Effort:** S

Provider calls and prompt templates (domain logic) live in a presentation module. The async `Task.start` is fire-and-forget — crashes are unlinked from the LiveView.

**Fix:** Move to `Samgita.Prds.chat_message/2` and `Prds.generate_from_conversation/1`. Use `Task.Supervisor.async_nolink` for visibility.

---

### AR-11 · `Samgita.Projects` is a god context covering 5 sub-domains in 483 lines

**File:** `apps/samgita/lib/samgita/projects.ex`  
**Priority:** Low | **Effort:** L

Project lifecycle, task management, agent run tracking, artifact storage, and dependency graph management all in one module.

**Fix:** Split into `Samgita.Projects`, `Samgita.Tasks`, `Samgita.AgentRuns`, `Samgita.Artifacts`.

---

### AR-12 · Root supervisor has no explicit restart budget or group isolation

**File:** `apps/samgita/lib/samgita/application.ex` line 31  
**Priority:** Low | **Effort:** S

Default OTP restart intensity (3/5s) means a DB connectivity blip can crash the entire application.

**Fix:** Group into `InfrastructureSupervisor` (Repo, PubSub, Horde, Finch) and `ApplicationSupervisor` (Oban, Recovery, CircuitBreaker) with appropriate restart intensities.

---

### AR-13 · Codex missing session callbacks, silently degrades to stateless mode

**File:** `apps/samgita_provider/lib/samgita_provider/codex.ex`  
**Priority:** Low | **Effort:** S

Multi-turn Codex sessions are client-side-only — conversation history is never sent to the CLI.

**Fix:** Implement `start_session/2`, `send_message/2`, `close_session/1` with conversation-prefix emulation. Add `@impl true` annotations.

---

## 4. Security Issues

### SEC-01 · API key comparison is not timing-safe

**File:** `apps/samgita_web/lib/samgita_web/plugs/api_auth.ex` line 23  
**Priority:** High | **Effort:** S

```elixir
[key] -> if key in valid_keys, do: conn, else: unauthorized(conn)
```

`in/2` uses standard Elixir equality which short-circuits on the first differing byte — a timing oracle for key enumeration.

**Fix:**
```elixir
valid = Enum.any?(valid_keys, fn k -> Plug.Crypto.secure_compare(k, key) end)
```

`plug_crypto` is already a transitive dependency.

---

### SEC-02 · `/api/health` and `/api/info` are unauthenticated and unrate-limited

**File:** `apps/samgita_web/lib/samgita_web/router.ex` lines 37–40  
**Priority:** High | **Effort:** S

`/api/info` returns Elixir/OTP/Phoenix/app versions, Mix environment name, and the full endpoint URL — reconnaissance information — with no auth or rate limiting.

**Fix:** Move `/api/info` into the authenticated `:api` pipeline. Apply `RateLimit` to the public health route.

---

### SEC-03 · Unsanitised user-supplied git URL passed to `git clone`; path traversal in target

**File:** `apps/samgita/lib/samgita/git.ex` line 38  
**Priority:** High | **Effort:** M

```elixir
System.cmd("git", ["clone", git_url, target], stderr_to_stdout: true)
```

The URL regex allows `git+ssh://`, `git+https://` and local paths. `extract_repo_name/1` takes the last `/`-segment without sanitising `..` sequences — a URL like `https://evil.com/../../../../etc/cron.d/payload` traverses the path.

**Fix:**
1. Restrict `validate_git_url/1` to `https://` and `git@` only.
2. Sanitise `extract_repo_name/1` to match `~r/^[A-Za-z0-9_.-]+$/` only.
3. Add `--no-local --` before the URL: `["clone", "--no-local", "--", git_url, target]`.

---

### SEC-04 · `check_origin: false` disables WebSocket origin validation globally

**File:** `config/config.exs` line 14  
**Priority:** Medium | **Effort:** S

Disabling origin checks globally means any page on any domain can open a WebSocket and interact with LiveView.

**Fix:** Remove `check_origin: false` from `config.exs`. Keep only in `dev.exs`. Set explicit allowed origins in `runtime.exs`.

---

### SEC-05 · Claude CLI debug logs expose full system prompts and user prompts

**Files:** `apps/samgita_provider/lib/samgita_provider/claude_code.ex` lines 21, 165;  
`apps/samgita_provider/lib/samgita_provider/codex.ex` line 24  
**Priority:** Medium | **Effort:** S

```elixir
Logger.debug("Claude CLI: #{command} #{Enum.join(args, " ")}")
```

`args` contains `--system-prompt <full system prompt>` and all user prompt text.

**Fix:** Redact values following `--system-prompt` before logging:
```elixir
safe_args = redact_arg_after(args, "--system-prompt")
Logger.debug("Claude CLI: #{command} #{Enum.join(safe_args, " ")}")
```

---

### SEC-06 · Webhook HMAC has no `sha256=` prefix convention; no minimum secret length

**File:** `apps/samgita/lib/samgita/workers/webhook_worker.ex` lines 47–48  
**Priority:** Medium | **Effort:** S

The raw HMAC hex string has no prefix, making it ambiguous to receivers. No minimum length validation on `webhook.secret`.

**Fix:** Prefix: `"sha256=" <> signature`. Add `validate_length(changeset, :secret, min: 16)`.

---

### SEC-07 · `ANTHROPIC_API_KEY` has no startup guard; silently sends empty key to Anthropic

**File:** `config/runtime.exs`  
**Priority:** Medium | **Effort:** S

`DATABASE_URL` and `SECRET_KEY_BASE` raise if unset, but the Anthropic key does not. A missing key silently returns 401 errors at runtime.

**Fix:**
```elixir
System.get_env("ANTHROPIC_API_KEY") ||
  raise "ANTHROPIC_API_KEY is required in production"
```

---

### SEC-08 · `git commit -m` and `git checkout` receive user-controlled values without `--` guard

**File:** `apps/samgita/lib/samgita/git/worktree.ex` lines 85–88  
**Priority:** Medium | **Effort:** S

Values starting with `-` could be misinterpreted as flags.

**Fix:** Add `--` separator: `["commit", "-m", "--", message]`, `["checkout", "--", branch]`.

---

### SEC-09 · ETS rate-limit table is `:public` and not shared across cluster nodes

**File:** `apps/samgita_web/lib/samgita_web/plugs/rate_limit.ex` lines 69–81  
**Priority:** Low | **Effort:** M

Per-node counters allow N×limit requests in an N-node cluster. `:public` table allows any process to manipulate counts.

**Fix:** Change to `:protected`. Consider Hammer with a shared backend for distributed deployments.

---

### SEC-10 · Prompt injection guardrails not applied to PRD content or webhook payloads

**File:** `apps/samgita/lib/samgita/quality/input_guardrails.ex` lines 112–131  
**Priority:** Low | **Effort:** M

`InputGuardrails.validate/1` checks only task description/agent_type/task_type. PRD chat content and webhook payloads flow directly into agent context via `ContextAssembler` without sanitisation.

**Fix:** Apply `InputGuardrails.validate/1` (or a dedicated content sanitizer) to PRD content before it is assembled into agent prompts.

---

## 5. Testing Improvements

### TS-01 · Compile bug: `_low.id` is unbound in compaction test

**File:** `apps/samgita_memory/test/samgita_memory/workers/compaction_test.exs` line 87  
**Priority:** High | **Effort:** S

```elixir
{:ok, _low} = ...          # _low discarded
assert is_nil(Repo.get(Memory, _low.id))   # _low is unbound here!
```

This test likely hasn't been run recently. Fix: rename `_low` to `low`.

---

### TS-02 · Worker: circuit-open task rejection path never tested

**File:** `apps/samgita/test/samgita/agent/worker_test.exs`  
**Priority:** High | **Effort:** S

The `idle/3` `:circuit_open` branch exists in the state machine but is never triggered in tests.

**Fix:** Add a test that drives `CircuitBreaker` to `:open` for the agent type, assigns a task, and asserts `{:error, :circuit_open}` is returned to the caller.

---

### TS-03 · Worker: `assign_task` while busy path never tested

**File:** `apps/samgita/test/samgita/agent/worker_test.exs`  
**Priority:** High | **Effort:** S

The catch-all handler in busy states calls `notify_caller(reply_to, task, {:error, :agent_busy})`. No test sends a second task while the first is in-flight.

---

### TS-04 · Orchestrator: `planning` phase and `planning_auto_advance: false` untested

**File:** `apps/samgita/test/samgita/project/orchestrator_test.exs`  
**Priority:** High | **Effort:** M

Tests only start projects in `:bootstrap` or `:development`. The `start_mode: :from_idea` entry point and manual-advance pause have zero coverage.

---

### TS-05 · `QualityGateWorker`: gate-fail → orchestrator not notified path missing

**File:** `apps/samgita/test/samgita/workers/quality_gate_worker_test.exs`  
**Priority:** High | **Effort:** M

The test asserts `:ok` for both pass and fail but never verifies the orchestrator receives `:quality_gates_passed` on pass, or no cast on fail.

---

### TS-06 · `Process.sleep`-based synchronisation throughout orchestrator tests

**File:** `apps/samgita/test/samgita/project/orchestrator_test.exs`  
**Priority:** High | **Effort:** M

At least 15 tests use `Process.sleep(50..500)` as synchronisation barriers. Flaky on slow CI; incorrect on fast machines.

**Fix:** Replace with a polling helper on `Orchestrator.get_state/1` with a deadline, or `assert_receive` on PubSub events.

---

### TS-07 · `AgentTaskWorker` tests use silent `case :ok` masking failures

**File:** `apps/samgita/test/samgita/workers/agent_task_worker_test.exs`  
**Priority:** High | **Effort:** S

```elixir
case AgentTaskWorker.perform(job) do
  {:error, _} -> assert ...
  :ok -> :ok   # silently passes when error branch not exercised!
end
```

**Fix:** Stub the provider to deterministically fail. Use `assert {:error, _} = AgentTaskWorker.perform(job)` directly.

---

### TS-08 · `prd_chat_live_test.exs` sleeps instead of asserting async completion

**File:** `apps/samgita_web/test/samgita_web/live/prd_chat_live_test.exs` lines 295–300  
**Priority:** High | **Effort:** S

```elixir
defp assert_receive_and_render(view, timeout) do
  Process.sleep(min(timeout, 500))   # never asserts a message was received
  render(view)
end
```

Tests pass even if the async Task crashes and never responds.

**Fix:** Use `assert_receive {:chat_response, _, _}, timeout` or subscribe to PubSub and assert the actual LiveView message.

---

### TS-09 · Worker↔CircuitBreaker feedback loop integration not tested

**File:** `apps/samgita/test/samgita/agent/worker_test.exs`  
**Priority:** High | **Effort:** M

No test confirms that a worker failing `@max_retries` times actually opens its circuit breaker, and that subsequent workers for the same agent type receive `:circuit_open`.

---

### TS-10 · Worker retry count and PubSub broadcasts not asserted on retry path

**File:** `apps/samgita/test/samgita/agent/worker_test.exs`  
**Priority:** High | **Effort:** M

The retry test only waits for the final error. It doesn't assert intermediate `retry_count` increments, `CircuitBreaker.record_failure` calls, or PubSub broadcasts for each RARV re-entry.

---

### TS-11 · Rate limit window expiry never tested

**File:** `apps/samgita_web/test/samgita_web/plugs/rate_limit_test.exs`  
**Priority:** Medium | **Effort:** S

The expiry logic could be completely broken without any test failure.

**Fix:**
```elixir
test "allows requests after window expires" do
  opts = RateLimit.init(limit: 1, window_ms: 50)
  RateLimit.call(build_conn(), opts)
  assert RateLimit.call(build_conn(), opts).halted
  Process.sleep(60)
  refute RateLimit.call(build_conn(), opts).halted
end
```

---

### TS-12 · `AgentTaskWorker` dependency-output propagation untested

**File:** `apps/samgita/test/samgita/workers/agent_task_worker_test.exs`  
**Priority:** Medium | **Effort:** M

`depends_on_ids`, `dependency_outputs`, and `wave` fields are never tested end-to-end: child tasks don't assert they receive parent outputs in their context.

---

### TS-13 · `BootstrapWorker` Oban enqueue failure path absent

**File:** `apps/samgita/test/samgita/workers/bootstrap_worker_test.exs`  
**Priority:** Medium | **Effort:** S

The `with` chain stops on enqueue error but no test stubs `MockOban.insert` to return `{:error, :timeout}`.

---

### TS-14 · Provider error response not tested in `PrdChatLive`

**File:** `apps/samgita_web/test/samgita_web/live/prd_chat_live_test.exs`  
**Priority:** Medium | **Effort:** S

The stub always returns success. No test for `{:error, :rate_limit}` or similar, which should render an error state.

---

### TS-15 · Quality gate mock prevents gate-fail scenarios from being exercised

**File:** `apps/samgita/test/samgita/workers/quality_gate_worker_test.exs`  
**Priority:** Medium | **Effort:** M

`MockProvider` always returns `"mock response"` — AI-dependent gates (`BlindReview`, `AntiSycophancy`) cannot produce a failing verdict.

**Fix:** Add tests that stub the provider to return outputs with known injection/sycophancy markers and assert the gate fails.

---

### TS-16 · Retrieval pipeline token budget truncation boundary untested

**File:** `apps/samgita_memory/test/samgita_memory/retrieval_pipeline_test.exs`  
**Priority:** Medium | **Effort:** S

No test verifying results are truncated at 4000 tokens, or that truncation preserves highest-scoring entries.

---

### TS-17 · `Project.Recovery` PubSub resubscription not verified after restart

**File:** `apps/samgita/test/samgita/project/recovery_test.exs`  
**Priority:** Medium | **Effort:** M

The test confirms the orchestrator process restarts but does not verify it re-subscribes to PubSub and resumes receiving events.

---

### TS-18 · `ProjectLive` does not assert task status updates or agent error events

**File:** `apps/samgita_web/test/samgita_web/live/project_live_test.exs`  
**Priority:** Medium | **Effort:** S

`task_completed` is tested but only asserts the view doesn't crash. No test for `agent_terminated` or `agent_error` events.

---

## 6. Documentation Gaps

### DOC-01 · README.md contains multiple stale facts from pre-umbrella era

**File:** `README.md`  
**Priority:** High | **Effort:** S

- Agent count wrong: says 37/6 swarms, actual is **41/8 swarms**
- Project structure shows flat `samgita/lib/` — actual is umbrella `apps/`
- Supervision tree shows non-existent `Samgita.ProjectSupervisor`, missing `CircuitBreaker`, `SessionRegistry`, `HealthChecker`, `Recovery`
- Links to `./docs/CONSTITUTION.md` (broken; file is at `docs/development/CONSTITUTION.md`)
- Documents non-existent `ClaudeAgent`/`ClaudeAPI` modules instead of `SamgitaProvider`
- Config examples reference non-existent keys

**Fix:** Full README overhaul: update agent count, fix project structure to show umbrella layout, fix supervision tree to match `application.ex`, fix broken links, replace API section with `SamgitaProvider` docs.

---

### DOC-02 · `Samgita.Agent.Worker` — 29 public functions with zero `@doc` or `@spec`

**File:** `apps/samgita/lib/samgita/agent/worker.ex`  
**Priority:** High | **Effort:** M

The most critical module in the system. Gen_statem state callback signatures, `assign_task/3` contract, `child_spec/1` restart policy, and all 12 `defstruct` fields are completely undocumented.

**Fix:** Add `@doc` + `@spec` on `start_link/1`, `assign_task/3`, `get_state/1`, `child_spec/1`. Document each struct field.

---

### DOC-03 · `Samgita.Projects` — 26 of 37 public functions undocumented, zero `@spec`

**File:** `apps/samgita/lib/samgita/projects.ex`  
**Priority:** High | **Effort:** M

The main domain context. The 5 lifecycle functions (`pause_project`, `resume_project`, `stop_project`, `restart_project`, `terminate_project`) have no docs explaining what state transitions they trigger or what PubSub events they emit.

---

### DOC-04 · `Samgita.Prds` — all 13 public functions undocumented, zero `@spec`

**File:** `apps/samgita/lib/samgita/prds.ex`  
**Priority:** High | **Effort:** S

Primary entry point for the LiveView PRD chat feature. Complete absence of documentation.

---

### DOC-05 · `DependencyGraph.compute_waves/1` memoization is non-functional — undocumented

**File:** `apps/samgita/lib/samgita/tasks/dependency_graph.ex` lines 116–140  
**Priority:** High | **Effort:** S

(See CQ-04 / PF-10.) The `@doc` exists but does not document the correctness limitation for DAGs with convergent paths.

**Fix:** Either fix the memoization or add an explicit note: "NOTE: memo is per-root-node only; correct for DAGs without convergent paths."

---

### DOC-06 · `.samgita/CONTINUITY.md` mechanism undocumented architecturally

**File:** Architecture gap  
**Priority:** High | **Effort:** S

`ContextAssembler.write_continuity_file/2` is the primary working-memory mechanism for the Claude CLI, but it's not documented: what the file contains, when it's created/updated/deleted, whether multiple agents share it.

**Fix:** Add section to `docs/architecture/ARCHITECTURE.md` or create `docs/architecture/continuity-files.md`.

---

### DOC-07 · Provider session lifecycle and token budget concept undocumented end-to-end

**File:** `docs/architecture/claude-integration.md` (partial)  
**Priority:** High | **Effort:** M

When sessions are opened vs. reused, what happens on `send_message` failure, and what "message budget" means are all absent from architecture docs.

---

### DOC-08 · `Samgita.Orchestrator` — 6 of 10 public functions undocumented, zero `@spec`

**File:** `apps/samgita/lib/samgita/project/orchestrator.ex`  
**Priority:** High | **Effort:** S

`advance_phase/1` (manual trigger for testing/UI) and the `defstruct` with `phase_dag`, `stagnation_checks`, etc. are undocumented.

---

### DOC-09 · `Agent.Types` model routing logic is opaque — cost-sensitive decisions undocumented

**File:** `apps/samgita/lib/samgita/agent/types.ex`  
**Priority:** Medium | **Effort:** S

`model_for_type/1` silently routes planning agents to Opus, QA/review to Haiku, everything else to Sonnet — cost-sensitive routing with no documentation.

---

### DOC-10 · Near-total absence of `@spec` across all context modules

**Files:** `projects.ex`, `prds.ex`, `features.ex`, `notifications.ex`, `webhooks.ex`, `worker.ex`, `orchestrator.ex`  
**Priority:** Medium | **Effort:** L

Zero typespecs across the core business logic layer prevents Dialyzer from providing meaningful coverage.

---

### DOC-11 · Stagnation detection is observability-only — this is undocumented

**File:** `apps/samgita/lib/samgita/project/orchestrator.ex`  
**Priority:** Medium | **Effort:** S

After 25 min without progress, the orchestrator logs and broadcasts `stagnation_detected` but does NOT automatically pause or advance. This non-obvious behavior should be called out in the `@moduledoc`.

---

### DOC-12 · `devenv.nix` and `docker-compose.yml` not mentioned in any developer guide

**File:** `docs/development/GETTING-STARTED.md`  
**Priority:** Medium | **Effort:** S

Both exist at the project root but are invisible to developers reading the docs.

---

### DOC-13 · 8+ runtime config keys undocumented in the deployment guide

**File:** `docs/deployment/DEPLOYMENT.md`  
**Priority:** Medium | **Effort:** S

Undocumented keys include: `orchestrator_notify_retries`, `retrieval_default_limit`, `retrieval_min_confidence`, `retrieval_semantic_weight`, `retrieval_recency_weight`, `retrieval_access_weight`, `embedding_provider`, and all project-level fields (`provider_preference`, `synapsis_endpoints`, `planning_auto_advance`, `start_mode`).

---

### DOC-14 · Agent crash recovery and re-spawn policy undocumented

**File:** `apps/samgita/lib/samgita/project/orchestrator.ex` lines 364–388  
**Priority:** Medium | **Effort:** S

Orchestrator monitors and re-spawns crashed agents with no maximum respawn count, reusing the same `agent_id`, without automatic task reassignment.

---

### DOC-15 · `SamgitaMemory.PostgrexTypes` needs explanation of pgvector requirement

**File:** `apps/samgita_memory/lib/samgita_memory/postgrex_types.ex`  
**Priority:** Low | **Effort:** S

The one-line `Postgrex.Types.define/3` call is a footgun (must be defined exactly once, must include `Pgvector.Extensions.Vector`). A `@moduledoc` explaining the pgvector-on-PostgreSQL-14 build-from-source requirement prevents future confusion.

---

## 7. Priority Summary

### 🔴 High Priority — Address First

| ID | Category | Issue | Effort |
|----|----------|-------|--------|
| SEC-01 | Security | Timing-unsafe API key comparison | S |
| SEC-02 | Security | `/api/info` unauthenticated/unrate-limited | S |
| SEC-03 | Security | Unsanitised `git clone` URL + path traversal in target | M |
| AR-01 | Architecture | Worker bypasses context — direct `Repo.insert` | M |
| AR-02 | Architecture | LiveView calls Oban directly, owns bootstrap logic | S |
| AR-03 | Architecture | Provider uses `function_exported?` not behaviour | M |
| AR-04 | Architecture | `verify` state: 6 side effects inline, silent failure | M |
| PF-03 | Performance | `Samgita.Cache` built but never used | S |
| PF-04 | Performance | No HNSW vector index on `sm_memories.embedding` | S |
| PF-01 | Performance | N+1 queries in `unblock_tasks` | M |
| PF-02 | Performance | N+1 `Repo.delete` loop in snapshot cleanup | S |
| PF-05 | Performance | ETS cache full-table scan for LRU eviction | M |
| PF-13 | Performance | Double DB roundtrip + no-index UUID cast per memory access | S |
| CQ-04 | Code Quality | `compute_node_wave` memo always empty — O(n!) | M |
| CQ-02 | Code Quality | `Process.sleep` in gen_statem callback | S |
| CQ-01 | Code Quality | 18-line duplicate block in `verify` state | S |
| TS-01 | Testing | Compile bug: `_low.id` unbound in compaction test | S |
| TS-02 | Testing | Circuit-open task rejection never tested | S |
| TS-03 | Testing | `assign_task` while busy never tested | S |
| TS-04 | Testing | Planning phase + `auto_advance: false` untested | M |
| TS-05 | Testing | Quality gate fail → orchestrator not notified path missing | M |
| TS-06 | Testing | `Process.sleep` sync in 15+ orchestrator tests | M |
| TS-07 | Testing | Silent `case :ok` masks worker error assertions | S |
| TS-08 | Testing | LiveView async helper sleeps instead of asserting | S |
| TS-09 | Testing | Worker↔CircuitBreaker feedback loop not tested | M |
| TS-10 | Testing | Retry count and PubSub broadcasts not asserted | M |
| DOC-01 | Documentation | README: wrong agent count, broken links, stale API docs | S |
| DOC-02 | Documentation | `worker.ex` — 29 public fns, 0 `@doc`, 0 `@spec` | M |
| DOC-03 | Documentation | `projects.ex` — 26/37 fns undocumented | M |
| DOC-04 | Documentation | `prds.ex` — 13/13 fns undocumented | S |
| DOC-05 | Documentation | `DependencyGraph` memo bug undocumented | S |
| DOC-06 | Documentation | CONTINUITY.md mechanism undocumented | S |
| DOC-07 | Documentation | Provider session lifecycle undocumented | M |
| DOC-08 | Documentation | `orchestrator.ex` — 6/10 fns undocumented | S |

### 🟡 Medium Priority

| ID | Category | Issue | Effort |
|----|----------|-------|--------|
| SEC-04 | Security | `check_origin: false` globally | S |
| SEC-05 | Security | Debug logs expose full system/user prompts | S |
| SEC-06 | Security | Webhook HMAC no prefix; no min secret length | S |
| SEC-07 | Security | `ANTHROPIC_API_KEY` has no startup guard | S |
| SEC-08 | Security | git args missing `--` guard | S |
| AR-05 | Architecture | Worker owns provider-selection logic | M |
| AR-06 | Architecture | `find_active_agent_run` duplicated in 2 modules | S |
| AR-07 | Architecture | PubSub topic inconsistency; Dashboard full-reload | S |
| AR-08 | Architecture | Flat Horde supervisor for all projects + agents | L |
| AR-09 | Architecture | Phase task catalog hardcoded in orchestrator | M |
| AR-10 | Architecture | `PrdChatLive` calls provider directly, owns prompts | S |
| PF-06 | Performance | O(n²) cosine deduplication in retrieval pipeline | M |
| PF-07 | Performance | `get_task_queue_state` loads all tasks to count | S |
| PF-08 | Performance | Missing composite index `(project_id, status)` | S |
| PF-09 | Performance | Missing partial index `(project_id, agent_type)` | S |
| PF-10 | Performance | Memo not shared across nodes in wave computation | S |
| PF-11 | Performance | `load_from_db` loads all memories unbounded | S |
| PF-12 | Performance | JSONB `payload->>'prd_id'` no expression index | S/M |
| CQ-05 | Code Quality | `parse_severity/1` repeats same arm 6 times | S |
| CQ-06 | Code Quality | `parse_vote_response` iterates `lines` 3× | S |
| CQ-07 | Code Quality | `touch_access` double SQL statement | S |
| CQ-08 | Code Quality | `enqueue_phase_tasks` 9-clause 250-line dispatch | L |
| CQ-09 | Code Quality | `import Ecto.Query` inside private function | S |
| CQ-10 | Code Quality | `headers/0` reads `Application.get_env` per request | S |
| CQ-13 | Code Quality | Redundant `Application.get_env` in retry loop | S |
| TS-11 | Testing | Rate limit window expiry never tested | S |
| TS-12 | Testing | Dependency-output propagation untested | M |
| TS-13 | Testing | `BootstrapWorker` enqueue failure path absent | S |
| TS-14 | Testing | Provider error response untested in PrdChatLive | S |
| TS-15 | Testing | Gate mock prevents gate-fail scenarios | M |
| TS-16 | Testing | Token budget truncation boundary untested | S |
| TS-17 | Testing | Recovery PubSub resubscription not verified | M |
| TS-18 | Testing | ProjectLive task stats + agent error events untested | S |
| DOC-09 | Documentation | `agent_types.ex` model routing logic undocumented | S |
| DOC-10 | Documentation | No `@spec` across all context modules | L |
| DOC-11 | Documentation | Stagnation detection is observability-only — undocumented | S |
| DOC-12 | Documentation | devenv.nix and docker-compose not in dev guide | S |
| DOC-13 | Documentation | 8+ runtime config keys undocumented | S |
| DOC-14 | Documentation | Agent crash recovery policy undocumented | S |

### 🟢 Low Priority

| ID | Category | Issue | Effort |
|----|----------|-------|--------|
| SEC-09 | Security | ETS rate limiter `:public` + not cross-node | M |
| SEC-10 | Security | Prompt injection not applied to PRD/webhook content | M |
| AR-11 | Architecture | `Samgita.Projects` god module (5 sub-domains) | L |
| AR-12 | Architecture | Root supervisor missing restart budget | S |
| AR-13 | Architecture | Codex missing session callbacks | S |
| CQ-11 | Code Quality | Anti-sycophancy unanimous path logs only, never acts | M |
| CQ-12 | Code Quality | Hardcoded weights diverge from config path | S |
| CQ-14 | Code Quality | `!` negation non-idiomatic | S |
| DOC-15 | Documentation | `PostgrexTypes` pgvector footgun undocumented | S |
