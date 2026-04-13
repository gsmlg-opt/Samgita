# Samgita — Code Analysis & Suggestions

> Generated: 2026-04-10  
> Scope: All 4 umbrella apps (`samgita_provider`, `samgita`, `samgita_memory`, `samgita_web`)  
> Total issues found: **27**

---

## Table of Contents

1. [Code Quality Issues](#1-code-quality-issues)
2. [Performance Optimizations](#2-performance-optimizations)
3. [Architecture Suggestions](#3-architecture-suggestions)
4. [Security Issues](#4-security-issues)
5. [Testing Improvements](#5-testing-improvements)
6. [Documentation Gaps](#6-documentation-gaps)
7. [Summary & Quick Wins](#7-summary--quick-wins)

---

## 1. Code Quality Issues

---

### CQ-1 — Bare Rescue Clauses in `samgita.ex`

**Priority:** 🔴 High | **Effort:** 0.5 h

**Description:**  
`Samgita.check_repo/1` uses a bare `rescue _ ->` which catches every exception indiscriminately. This swallows genuine programming errors (e.g. misconfigured repo, wrong DSN) and makes debugging difficult.

**Current code** — `apps/samgita/lib/samgita.ex:21-26`
```elixir
def check_repo(repo) do
  repo.query!("SELECT 1")
  :ok
rescue
  _ -> :error   # catches EVERYTHING — real errors hidden
end
```

**Proposed solution:**
```elixir
def check_repo(repo) do
  repo.query!("SELECT 1")
  :ok
rescue
  e in [DBConnection.ConnectionError, Postgrex.Error] ->
    Logger.warning("Repo health check failed: #{Exception.message(e)}")
    :error
end
```

---

### CQ-2 — Bare Rescue in Rate-Limit Plug Hot Path

**Priority:** 🔴 High | **Effort:** 1 h

**Description:**  
`SamgitaWeb.Plugs.RateLimit` wraps ETS calls in `try/rescue` for ETS table creation. Doing this on every HTTP request is expensive and masks actual bugs. The rescue only catches `ArgumentError`, leaving other errors unhandled.

**Current code** — `apps/samgita_web/lib/samgita_web/plugs/rate_limit.ex:26-52`
```elixir
def call(conn, opts) do
  count =
    try do
      cleanup_expired(key, window_start)
      count_requests(key, window_start)
    rescue
      ArgumentError ->
        ensure_table()
        0
    end
  ...
end

defp ensure_table do
  case :ets.whereis(:samgita_rate_limit) do
    :undefined ->
      try do
        :ets.new(:samgita_rate_limit, [:named_table, :public, :duplicate_bag])
      rescue
        ArgumentError -> :ok
      end
    _ -> :ok
  end
end
```

**Proposed solution:**  
Own the ETS table in a dedicated `GenServer` started during application boot. Plug then writes directly via the owning process or uses `:ets.whereis/1` once at startup.

```elixir
# In RateLimit.Server (GenServer)
def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

def init(_) do
  table = :ets.new(:samgita_rate_limit, [:named_table, :public, :duplicate_bag,
                                          write_concurrency: true])
  {:ok, %{table: table}}
end

# In RateLimit Plug — no rescue needed; table is guaranteed to exist
def call(conn, opts) do
  cleanup_expired(key, window_start)
  count = count_requests(key, window_start)
  ...
end
```

---

### CQ-3 — God Module: `Agent.Worker` (946 lines)

**Priority:** 🟡 Medium | **Effort:** 3-4 d

**Description:**  
`apps/samgita/lib/samgita/agent/worker.ex` exceeds 900 lines and bundles at least five distinct concerns: state machine transitions (RARV cycle), agent communication, task result parsing, activity broadcasting, and circuit breaker integration. Each state handler (`handle_event/4`) is 30-50 lines.

**Current code (abbreviated):**
```elixir
# worker.ex handles:
# 1. gen_statem callbacks (state transitions)
# 2. Horde.Registry naming + monitoring
# 3. PromptBuilder.build_prompt/3 (delegate exists but logic bleeds back in)
# 4. PubSub broadcasts
# 5. SessionRegistry / provider calls
# 6. Oban task dispatch
```

**Proposed solution:**  
The 6 delegate modules (`PromptBuilder`, `ResultParser`, `ContextAssembler`, `WorktreeManager`, `ActivityBroadcaster`, `RetryStrategy`) already exist — ensure all logic lives in them and `Worker` is a thin state machine:

```
Samgita.Agent.Worker          — gen_statem skeleton only (~150 lines)
Samgita.Agent.PromptBuilder   — build context + prompt
Samgita.Agent.ResultParser    — parse/validate LLM output
Samgita.Agent.ActivityBroadcaster — PubSub events
Samgita.Agent.RetryStrategy   — back-off, circuit breaker integration
Samgita.Agent.SessionManager  — provider session lifecycle
```

---

### CQ-4 — God Module: `Project.Orchestrator` (1,091 lines)

**Priority:** 🟡 Medium | **Effort:** 3-4 d

**Description:**  
`apps/samgita/lib/samgita/project/orchestrator.ex` manages 11 phase transitions, task stagnation detection, quality gate coordination, agent spawn/monitor, and auto-advance logic — all in a single gen_statem exceeding 1,000 lines.

**Proposed solution:**  
Extract phase-specific logic into protocol implementations or dedicated modules:

```
Samgita.Project.Orchestrator       — gen_statem transitions only
Samgita.Project.Phase.<PhaseName>  — per-phase enter/exit/advance logic
Samgita.Project.StagnationDetector — stagnation + recovery
Samgita.Project.PhaseGates         — quality gate orchestration
```

---

### CQ-5 — God Module: `BootstrapWorker` (716 lines)

**Priority:** 🟡 Medium | **Effort:** 2-3 d

**Description:**  
Regex-based PRD parsing, milestone extraction, task graph construction, wave computation, priority assignment, and Oban enqueueing all live in one Oban worker module.

**Proposed solution:**
```
Samgita.Workers.BootstrapWorker           — Oban entry point only
Samgita.Bootstrap.PrdParser               — section/milestone extraction
Samgita.Bootstrap.TaskGenerator           — per-category task creation
Samgita.Bootstrap.DependencyGraphBuilder  — topological sort + wave calc
```

---

### CQ-6 — Duplicate `get → {:ok, x} | {:error, :not_found}` Pattern

**Priority:** 🟢 Low | **Effort:** 1-2 h

**Description:**  
Appears in 15+ context modules:
```elixir
def get_project(id) do
  case Repo.get(Project, id) do
    nil  -> {:error, :not_found}
    item -> {:ok, item}
  end
end
```

**Proposed solution:**  
Add a shared helper (or use `Ecto.Repo.get/3` with `returning:` option):
```elixir
defmodule Samgita.Repo.Helpers do
  def fetch(queryable, id, opts \\ []) do
    case Samgita.Repo.get(queryable, id, opts) do
      nil    -> {:error, :not_found}
      record -> {:ok, record}
    end
  end
end
```

---

### CQ-7 — Missing `@spec` Annotations (15+ modules)

**Priority:** 🟡 Medium | **Effort:** 2-3 d

**Description:**  
Key modules lack `@spec` annotations, hampering Dialyzer coverage and documentation:
- `Samgita.Agent.Worker` (30+ functions)
- `Samgita.Project.Orchestrator` (20+ functions)
- `Samgita.Workers.BootstrapWorker` (15+ functions)
- All quality gate modules (`AntiSycophancy`, `BlindReview`, `CompletionCouncil`, etc.)

**Proposed solution:**  
Add `@spec` to all public callbacks and functions. Enforce with CI:
```bash
mix dialyzer --no-check-plt --halt-exit-status
```

---

## 2. Performance Optimizations

---

### PF-1 — N+1 Query in `Projects.unblock_tasks/2`

**Priority:** 🔴 High | **Effort:** 1.5 h

**Description:**  
For N dependent tasks, the current implementation executes:
- 1 query → find dependent task IDs
- N queries → get hard dependency IDs per task
- N queries → count completed hard dependencies
- N queries → update eligible tasks

Total: **O(N²)** queries.

**Current code** — `apps/samgita/lib/samgita/projects.ex:376-410`
```elixir
def unblock_tasks(project_id, completed_task_id) do
  dependent_task_ids =
    from(td in TaskDependency,
      where: td.depends_on_id == ^completed_task_id,
      select: td.task_id
    )
    |> Repo.all()                            # Query 1

  Enum.reduce(dependent_task_ids, [], &maybe_unblock_task(&1, &2))
  # maybe_unblock_task calls Repo 2-3× per task → O(N) additional queries
end
```

**Proposed solution:**
```elixir
def unblock_tasks(_project_id, completed_task_id) do
  # Single query: find all tasks waiting on this one
  # and eagerly load ALL their hard deps with status
  unblockable_ids_query =
    from t in Task,
      join: td in TaskDependency, on: td.task_id == t.id and td.depends_on_id == ^completed_task_id,
      where: t.status == :blocked,
      left_join: hard_dep in TaskDependency,
        on: hard_dep.task_id == t.id and hard_dep.dependency_type == :hard,
      left_join: dep_task in Task,
        on: dep_task.id == hard_dep.depends_on_id,
      group_by: t.id,
      having: count(dep_task.id) == count(fragment("CASE WHEN ? = 'completed' THEN 1 END", dep_task.status)),
      select: t.id

  Repo.update_all(
    from(t in Task, where: t.id in subquery(unblockable_ids_query)),
    set: [status: :queued, updated_at: DateTime.utc_now()]
  )
end
```

---

### PF-2 — Missing Composite Database Indexes

**Priority:** 🟡 Medium | **Effort:** 1 h

**Description:**  
Several frequently-used query patterns lack composite indexes:

| Table | Missing index | Used in |
|---|---|---|
| `tasks` | `(project_id, status)` | `list_tasks/2` with status filter |
| `tasks` | `(project_id, wave)` | `tasks_by_wave/2` |
| `agent_runs` | `(project_id, agent_type, ended_at)` | `find_or_create_agent_run/3` |
| `chat_messages` | `(prd_id, role)` | `Prds` context |
| `sm_memories` | `(type, confidence)` | Compaction queries |

**Proposed solution:**
```elixir
# New migration
create index(:tasks, [:project_id, :status])
create index(:tasks, [:project_id, :wave])
create index(:agent_runs, [:project_id, :agent_type, :ended_at])
create index(:chat_messages, [:prd_id, :role])
create index(:sm_memories, [:type, :confidence])
```

---

### PF-3 — Unsupervised `Task.async` Calls (Resource Leak)

**Priority:** 🔴 High | **Effort:** 1.5 h

**Description:**  
`Task.async/1` links the task to the calling process. If the caller exits before `Task.await/2`, the task continues orphaned, leaking processes and potentially Claude CLI subprocesses.

**Current code** — `apps/samgita_provider/lib/samgita_provider/claude_code.ex:24-25`
```elixir
def query(prompt, opts \\ []) do
  task = Task.async(fn -> execute_claude_command(command, args, cmd_opts) end)
  await_task_result(task, timeout)
end
```

Also present in:
- `apps/samgita/lib/samgita/notifications.ex:207`
- `apps/samgita/lib/samgita/quality/blind_review.ex`

**Proposed solution:**
```elixir
# 1. Register a Task.Supervisor in each app's supervision tree
children = [
  {Task.Supervisor, name: SamgitaProvider.TaskSupervisor},
  ...
]

# 2. Use it everywhere
def query(prompt, opts \\ []) do
  task = Task.Supervisor.async(SamgitaProvider.TaskSupervisor,
           fn -> execute_claude_command(command, args, cmd_opts) end)
  Task.await(task, timeout)
end
```

---

### PF-4 — ETS Race Condition in Rate Limiter

**Priority:** 🟡 Medium | **Effort:** 0.5 h

**Description:**  
Between `:ets.whereis/1` returning `:undefined` and `:ets.new/2`, another concurrent request can create the table, causing `ArgumentError` which is then rescued. This is a classic TOCTOU race.

**Current code** — `apps/samgita_web/lib/samgita_web/plugs/rate_limit.ex:69-81` (see CQ-2)

**Proposed solution:** Own the table in a dedicated GenServer (see CQ-2 proposal). The race is impossible when only one process creates the table.

---

### PF-5 — Cache ETS Missing Write Concurrency

**Priority:** 🟡 Medium | **Effort:** 0.5 h

**Description:**  
`Samgita.Cache` opens the ETS table with `read_concurrency: true` but not `write_concurrency: true`. Under concurrent writes (cache invalidation bursts after PubSub events), writes serialize unnecessarily.

**Current code** — `apps/samgita/lib/samgita/cache.ex:67`
```elixir
table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
```

**Proposed solution:**
```elixir
table = :ets.new(@table, [
  :named_table, :set, :public,
  read_concurrency: true,
  write_concurrency: true
])
```

Note: Route ALL writes through the owning `GenServer` (already done for `put/2`) so concurrent write option is safe.

---

## 3. Architecture Suggestions

---

### AR-1 — Dependency Boundary Violation: `samgita_web` → `samgita_memory`

**Priority:** 🔴 High | **Effort:** 1 h

**Description:**  
`samgita_web` directly references `samgita_memory` in `InfoController`, violating the declared dependency graph (`samgita_web → samgita → samgita_memory`). This means `samgita_web` can call memory APIs it should only access via the `samgita` domain layer.

**Current code** — `apps/samgita_web/lib/samgita_web/controllers/info_controller.ex`
```elixir
for app <- [:samgita_provider, :samgita, :samgita_memory, :samgita_web],
```

**Proposed solution:**  
Expose an aggregated `Samgita.system_info/0` function in the `samgita` app, and have `InfoController` call only that:

```elixir
# samgita/lib/samgita.ex
def system_info do
  [:samgita_provider, :samgita, :samgita_memory, :samgita_web]
  |> Enum.map(fn app ->
    {:ok, vsn} = :application.get_key(app, :vsn)
    {app, to_string(vsn)}
  end)
  |> Map.new()
end

# info_controller.ex — no direct :samgita_memory reference
def index(conn, _) do
  render(conn, :index, info: Samgita.system_info())
end
```

---

### AR-2 — `CircuitBreaker` GenServer Bottleneck

**Priority:** 🟡 Medium | **Effort:** 1 d

**Description:**  
All agents of any type funnel through a single `Samgita.Agent.CircuitBreaker` GenServer for `allow?/1` calls. At 100+ concurrent agents, every state check serializes through one mailbox.

**Current code** — `apps/samgita/lib/samgita/agent/circuit_breaker.ex:36-44`
```elixir
def allow?(agent_type) do
  GenServer.call(__MODULE__, {:allow?, agent_type})
end
```

**Proposed solution:**  
Move state to ETS with atomic operations (`:ets.update_counter`, `:ets.lookup`). The GenServer still owns the table but reads are direct:

```elixir
def allow?(agent_type) do
  case :ets.lookup(@table, agent_type) do
    [{^agent_type, :open, _}] -> false
    _ -> true
  end
end

# Only state transitions go through GenServer
def record_failure(agent_type) do
  GenServer.cast(__MODULE__, {:failure, agent_type})
end
```

---

### AR-3 — Tight Coupling: `Projects` ↔ `Project.Orchestrator`

**Priority:** 🟡 Medium | **Effort:** 1.5 h

**Description:**  
`Projects` context calls `Orchestrator.pause/resume` directly via Horde, while Orchestrator dispatches Oban workers that call back into `Projects`. This bidirectional coupling makes failure modes hard to reason about.

**Proposed solution:**  
Replace direct calls with PubSub events:

```elixir
# Projects.pause_project/1 emits event instead of calling Orchestrator directly
Phoenix.PubSub.broadcast(Samgita.PubSub, "project:#{id}", {:pause_requested, id})

# Orchestrator subscribes in init
def init(data) do
  Phoenix.PubSub.subscribe(Samgita.PubSub, "project:#{data.project_id}")
  ...
end
```

---

### AR-4 — Unsupervised Task Spawning in Quality Gates

**Priority:** 🔴 High | **Effort:** 1.5 h

**Description:**  
`Samgita.Quality.BlindReview` and `CompletionCouncil` spawn reviewer agents using bare `Task.async` without a supervisor. A crash in any reviewer leaves sibling tasks running with no owner.

**Proposed solution:**  
Register `Samgita.QualityTaskSupervisor` in `Samgita.Application` and use `Task.Supervisor.async_stream` for parallel reviewer spawning:

```elixir
Task.Supervisor.async_stream(
  Samgita.QualityTaskSupervisor,
  reviewers,
  fn reviewer -> run_reviewer(reviewer, context) end,
  max_concurrency: 4,
  on_timeout: :kill_task
)
```

---

## 4. Security Issues

---

### SC-1 — `String.to_existing_atom` on User Input in LiveView

**Priority:** 🟡 Medium | **Effort:** 0.5 h

**Description:**  
Even when guarded, converting user-supplied strings to atoms via `String.to_existing_atom/1` is fragile. If a future refactor renames atoms, the guard becomes stale and the conversion can fail with `ArgumentError`.

**Current code** — `apps/samgita_web/lib/samgita_web/live/prd_chat_live/index.ex:61-67`
```elixir
def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in ["editor", "chat"] do
  {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
end
```

**Proposed solution:**
```elixir
@valid_tabs %{"editor" => :editor, "chat" => :chat}

def handle_event("switch_tab", %{"tab" => tab}, socket) do
  case Map.get(@valid_tabs, tab) do
    nil  -> {:noreply, socket}
    atom -> {:noreply, assign(socket, active_tab: atom)}
  end
end
```

---

### SC-2 — Open API When `SAMGITA_API_KEYS` Is Unset

**Priority:** 🟢 Low | **Effort:** 0.5 h

**Description:**  
If the `SAMGITA_API_KEYS` environment variable is empty or unset, the REST API accepts all requests. There's no warning emitted at startup.

**Current code** — `config/runtime.exs:20-26`
```elixir
config :samgita, :api_keys,
  if(api_keys_string == "",
    do: [],
    else: String.split(api_keys_string, ",") |> Enum.map(&String.trim/1)
  )
```

**Proposed solution:**
```elixir
if api_keys_string == "" do
  Logger.warning("[Samgita] SAMGITA_API_KEYS not set — REST API is open to all callers!")
end
```

---

### SC-3 — Regex-Based Mutation Detection (Bypassable)

**Priority:** 🟢 Low | **Effort:** 1 h

**Description:**  
`Samgita.Quality.TestMutationDetector` uses regex patterns to detect suppressed assertions in tests. Whitespace variations or alternative forms bypass detection silently.

**Current code** — `apps/samgita/lib/samgita/quality/test_mutation_detector.ex:73-142`
```elixir
catch_all_count =
  Regex.scan(~r/rescue\s+_\s*->\s*(:ok|assert\s+true|nil)/, content)
  |> length()
```

**Proposed solution:**  
Use `Code.string_to_quoted/1` to parse the AST and walk rescue clauses:
```elixir
{:ok, ast} = Code.string_to_quoted(content)
# Walk AST looking for {:rescue, [{:->, _, [[{:_, _, _}], _]}], _}
```

---

## 5. Testing Improvements

---

### TS-1 — Missing Test Files for Core Modules

**Priority:** 🟡 Medium | **Effort:** 2-3 d

**Description:**  
Several non-trivial modules have no corresponding test file:

| Module | File | Risk |
|---|---|---|
| `Samgita.Features` | `samgita/features.ex` | Feature flag logic untested |
| `Samgita.References` | `samgita/references.ex` | Reference lookup untested |
| `Samgita.Release` | `samgita/release.ex` | Migration runner untested |
| `Samgita.Telemetry` | `samgita/telemetry.ex` | Metric aggregation untested |
| `Samgita.Project.Memory` | `samgita/project/memory.ex` | Tested only indirectly |
| Quality gate modules (6) | `samgita/quality/*.ex` | Complex logic, no unit tests |

**Proposed solution:**  
Create test files for each module. Quality gate modules in particular contain complex conditional logic (`AntiSycophancy`, `CompletionCouncil`) that should be unit-tested with fixture responses.

---

### TS-2 — Missing Property-Based Tests for Task Dependency Graph

**Priority:** 🟡 Medium | **Effort:** 1 d

**Description:**  
`BootstrapWorker` builds a task dependency graph and computes waves via topological sort. This logic is subtle (cycle detection, wave propagation) yet only tested with hand-crafted fixtures.

**Proposed solution:**  
Use `StreamData` for property-based testing:
```elixir
property "wave computation never produces cycles" do
  check all tasks <- task_graph_generator() do
    waves = DependencyGraphBuilder.compute_waves(tasks)
    assert no_back_edges?(tasks, waves)
  end
end
```

---

### TS-3 — Async Test Configuration

**Priority:** 🟢 Low | **Effort:** 1 h

**Description:**  
Some test modules don't explicitly set `async: true`. Tests that don't touch the database or shared state could run concurrently, reducing total CI time.

**Proposed solution:**  
Audit all test files and mark database-free tests with `async: true`. Use `Ecto.Adapters.SQL.Sandbox` properly for DB tests.

---

### TS-4 — Regex-Based Mutation Detector Has False Negatives (TS-related)

**Priority:** 🟢 Low | **Effort:** 1 h

*(Also listed in SC-3 — fix applies to both security and test quality.)*

---

## 6. Documentation Gaps

---

### DC-1 — Missing `@doc` on Public Functions

**Priority:** 🟢 Low | **Effort:** 1-2 h

**Description:**  
Several public functions in key modules lack `@doc` strings:
- `Samgita.Cache.get/1`, `put/3`
- `Samgita.Events` callbacks
- `Samgita.Git` helper functions
- All quality gate `run/2` functions

**Proposed solution:**  
Add `@doc` to every public function. Enforce with:
```elixir
# In mix.exs or .credo.exs
{Credo.Check.Readability.ModuleDoc, []},
```

---

### DC-2 — `@moduledoc false` on Non-Private Modules

**Priority:** 🟢 Low | **Effort:** 0.5 h

**Description:**  
Several modules that ARE part of the public API are marked `@moduledoc false`, which hides them from `mix docs` output:
- `Samgita.Application` — acceptable
- Some quality gate modules — should be documented

**Proposed solution:**  
Replace `@moduledoc false` with real documentation on modules that are intentionally public. Reserve `false` for internal implementation details.

---

### DC-3 — Architecture Docs Don't Reflect Split Oban Instances

**Priority:** 🟡 Medium | **Effort:** 1 h

**Description:**  
`docs/architecture/claude-integration.md` and `CLAUDE.md` describe Oban but don't clearly document that `samgita` and `samgita_memory` run **separate Oban instances** (`Oban` vs `SamgitaMemory.Oban`). This confuses contributors adding new workers.

**Proposed solution:**  
Add a clear section to `CLAUDE.md` and `docs/architecture/` with a table mapping each worker to its Oban instance, queue, and config key.

---

## 7. Summary & Quick Wins

### Issue Count by Priority

| Priority | Count |
|---|---|
| 🔴 High | 8 |
| 🟡 Medium | 14 |
| 🟢 Low | 5 |
| **Total** | **27** |

### Estimated Total Effort

**25–35 person-days** to fully address all issues.

---

### Quick Wins (< 2 hours each, high value)

| # | Issue | File | Effort |
|---|---|---|---|
| 1 | Fix bare rescue in `samgita.ex` | `samgita.ex:24` | 30 min |
| 2 | Add 5 missing composite DB indexes | new migration | 1 h |
| 3 | Fix `String.to_existing_atom` in LiveView | `prd_chat_live/index.ex:62` | 30 min |
| 4 | Add write_concurrency to Cache ETS table | `cache.ex:67` | 15 min |
| 5 | Add startup warning for open API | `runtime.exs:22` | 15 min |
| 6 | Register `Task.Supervisor` in app trees | `*/application.ex` | 1 h |

---

### High-Impact Medium-Term (1-5 days each)

| # | Issue | Effort |
|---|---|---|
| 1 | Fix N+1 query in `unblock_tasks/2` | 1.5 h |
| 2 | Move `RateLimit` ETS to owned GenServer | 1 h |
| 3 | Fix architecture boundary `samgita_web → samgita_memory` | 1 h |
| 4 | Convert `CircuitBreaker` to ETS reads | 1 d |
| 5 | Add `@spec` to all public functions | 2-3 d |
| 6 | Add test files for 6 quality gate modules | 2-3 d |

---

### Longer-Term Refactors (3+ days each)

| # | Issue | Effort |
|---|---|---|
| 1 | Break up `Agent.Worker` god module | 3-4 d |
| 2 | Break up `Project.Orchestrator` god module | 3-4 d |
| 3 | Break up `BootstrapWorker` god module | 2-3 d |
| 4 | Decouple `Projects` ↔ `Orchestrator` via PubSub | 1.5 h |
| 5 | Property-based tests for task dependency graph | 1 d |
